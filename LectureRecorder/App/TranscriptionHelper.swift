import Foundation
import LectureCore

/// 전사는 샌드박스 밖에서 Python(mlx-audio)을 돌려야 해서, install.sh가 둔 도우미 스크립트를 `NSUserUnixTask`로 실행한다.
/// 스크립트: ~/Library/Application Scripts/com.uisong.LectureRecorder/transcribe.sh (scripts/transcribe-helper.sh)
enum TranscriptionHelperScript {
    static let logPath = "~/Library/Logs/LectureRecorder-transcribe.log"
    static let missingMessage = "전사 도우미가 없어요. 터미널에서 저장소 폴더로 가서 git pull && ./scripts/install.sh 를 실행해 주세요."

    /// 도우미를 실행하고 종료 코드를 돌려준다(0이면 성공). 도우미가 없으면 `TranscriptionToolError.helperMissing`.
    static func run(_ arguments: [String]) async throws -> Int {
        let task: NSUserUnixTask
        do {
            let folder = try FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            task = try NSUserUnixTask(url: folder.appending(path: "transcribe.sh"))
        } catch {
            Log.app.error("전사 도우미를 열지 못함: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionToolError.helperMissing
        }
        let command = arguments.first ?? ""
        return await withCheckedContinuation { continuation in
            task.execute(withArguments: arguments) { error in
                guard let error else {
                    continuation.resume(returning: 0)
                    return
                }
                let status = (error as NSError).userInfo["NSUnixExitStatus"] as? Int ?? -1
                Log.app.error("전사 도우미 \(command, privacy: .public) 실패(코드 \(status, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: status)
            }
        }
    }
}

/// 녹음 하나를 도우미로 전사한다. 진행 파일을 1초마다 읽어 진행률을 알리고, 취소되면 취소 파일을 만들어 도우미가 다음 조각 전에 멈추게 한다.
/// 작업 폴더는 작업마다 고정(Caches/Transcribe/<workID>)이라, 멈춘 뒤 "이어서" 하면 끝낸 조각은 건너뛴다.
/// 폴더는 대기열이 결과를 저장했거나 줄을 뺐을 때 `discardWork`로 지운다. 저장이 실패하거나 도우미가 실패해도 남겨,
/// "다시 시도"가 끝낸 조각을 건너뛰게 한다.
struct HelperScriptTranscriber: Transcribing {
    static let cancelledStatus = 40

    static func workFolder(for job: TranscriptionJob) throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return caches.appending(path: "Transcribe/\(job.workID.uuidString)", directoryHint: .isDirectory)
    }

    func transcribe(_ job: TranscriptionJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        let files = FileManager.default
        let folder: URL
        do {
            folder = try Self.workFolder(for: job)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.app.error("전사 작업 폴더를 만들지 못함: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError("작업 폴더를 만들지 못했어요. 저장 공간을 확인해 주세요.", detail: error.localizedDescription)
        }
        let output = folder.appending(path: "result.json")
        let progressFile = folder.appending(path: "progress.json")
        let cancelFile = folder.appending(path: "progress.json.cancel")
        let errorLog = folder.appending(path: "progress.json.log")
        let resumeFile = folder.appending(path: "resume.json")
        // 지난번 멈춤에서 남은 취소 표시와 오류 기록은 지우고 시작한다(이어하기 기록은 남긴다).
        for leftover in [cancelFile, errorLog, output] where files.fileExists(atPath: leftover.path) {
            do { try files.removeItem(at: leftover) } catch {
                Log.app.error("전사 작업 폴더 정리 실패 \(leftover.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw TranscriptionError("지난 전사 기록을 정리하지 못했어요. 빼고 다시 넣어 주세요.", detail: error.localizedDescription)
            }
        }

        let poller = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let data = try? Data(contentsOf: progressFile), let fraction = TranscriptionProgressFile.fraction(from: data) {
                    progress(fraction)
                }
            }
        }
        defer { poller.cancel() }

        let arguments = ["run", job.audioURL.path, output.path, progressFile.path, String(ProcessInfo.processInfo.processIdentifier), resumeFile.path]
        let status: Int
        do {
            status = try await withTaskCancellationHandler {
                try await TranscriptionHelperScript.run(arguments)
            } onCancel: {
                if !FileManager.default.createFile(atPath: cancelFile.path, contents: Data()) {
                    Log.app.error("전사 취소 파일을 만들지 못함")
                }
            }
        } catch TranscriptionToolError.helperMissing {
            throw TranscriptionError(TranscriptionHelperScript.missingMessage)
        }
        // 결과가 다 나왔으면 그 사이 멈춤을 눌렀어도 결과를 돌려준다(버리지 않는다).
        // 폴더는 대기열이 결과를 저장한 뒤 지운다(저장이 실패하면 다시 시도 때 다시 쓴다).
        if status == 0 {
            do {
                return try Transcript.decode(Data(contentsOf: output))
            } catch {
                Log.app.error("전사 결과를 읽지 못함: \(error.localizedDescription, privacy: .public)")
                throw TranscriptionError("전사 결과를 읽지 못했어요. 다시 시도해 주세요.", detail: error.localizedDescription)
            }
        }
        // 취소로 멈춘 것만 멈춤으로 본다. 멈춤과 같은 때 난 진짜 실패(다른 코드)는 실패로 알린다.
        if status == Self.cancelledStatus { throw CancellationError() }
        Log.app.error("전사 도우미 실패 코드 \(status, privacy: .public)")
        throw TranscriptionError.helperExit(status).with(detail: Self.errorTail(at: errorLog))
    }

    /// 앱을 켤 때 부른다. 대기열은 앱을 끄면 비므로, 지난번에 멈춰 둔 작업 폴더는 더 쓰지 않는다.
    static func removeAllWork() {
        do {
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            removeWork(at: caches.appending(path: "Transcribe", directoryHint: .isDirectory))
        } catch {
            Log.app.error("전사 작업 폴더 위치를 찾지 못함: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardWork(for job: TranscriptionJob) {
        do {
            Self.removeWork(at: try Self.workFolder(for: job))
        } catch {
            Log.app.error("전사 작업 폴더를 찾지 못함: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func errorTail(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return TranscriptionError.tail(of: try String(contentsOf: url, encoding: .utf8))
        } catch {
            Log.app.error("전사 오류 기록을 읽지 못함: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func removeWork(at folder: URL) {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do { try FileManager.default.removeItem(at: folder) } catch {
            Log.app.error("전사 작업 폴더 정리 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 설정 > 전사의 "전사 도구 설치". 처음 한 번 Python 가상환경과 mlx-audio를 설치한다 (몇 분 걸림, 모델은 첫 전사 때 받음).
struct HelperScriptTranscriptionTool: TranscriptionToolManaging {
    /// 0이면 준비됨, 20이면 아직 설치 안 됨. 그 밖의 코드는 도우미를 실행하지 못한 것이라 "설치 안 됨"과 구별해 알린다.
    func isReady() async throws -> Bool {
        let status = try await TranscriptionHelperScript.run(["status"])
        switch status {
        case 0: return true
        case 20: return false
        default:
            throw TranscriptionToolError.failed("전사 도우미를 실행하지 못했어요 (코드 \(status)). 터미널에서 ./scripts/install.sh 를 다시 실행해 주세요. 로그: \(TranscriptionHelperScript.logPath)")
        }
    }

    func install() async throws {
        let status = try await TranscriptionHelperScript.run(["setup"])
        switch status {
        case 0: return
        case 30: throw TranscriptionToolError.failed("Python 3.10 이상이 필요해요. 터미널에서 brew install python@3.12 를 실행한 뒤 다시 설치해 주세요.")
        case 31: throw TranscriptionToolError.failed("설치하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요. 로그: \(TranscriptionHelperScript.logPath)")
        default: throw TranscriptionToolError.failed("설치하지 못했어요 (코드 \(status)). 로그: \(TranscriptionHelperScript.logPath)")
        }
    }
}
