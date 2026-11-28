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
struct HelperScriptTranscriber: Transcribing {
    static let cancelledStatus = 40

    func transcribe(_ job: TranscriptionJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appending(path: "Transcribe/\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.app.error("전사 임시 폴더를 만들지 못함: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError("임시 폴더를 만들지 못했어요. 저장 공간을 확인해 주세요.")
        }
        defer {
            do { try files.removeItem(at: folder) } catch {
                Log.app.error("전사 임시 폴더 정리 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        let output = folder.appending(path: "result.json")
        let progressFile = folder.appending(path: "progress.json")
        let cancelFile = folder.appending(path: "progress.json.cancel")

        let poller = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let data = try? Data(contentsOf: progressFile), let fraction = TranscriptionProgressFile.fraction(from: data) {
                    progress(fraction)
                }
            }
        }
        defer { poller.cancel() }

        let arguments = ["run", job.audioURL.path, output.path, progressFile.path, String(ProcessInfo.processInfo.processIdentifier)]
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
        if Task.isCancelled || status == Self.cancelledStatus { throw CancellationError() }
        guard status == 0 else { throw TranscriptionError.helperExit(status) }
        do {
            return try Transcript.decode(Data(contentsOf: output))
        } catch {
            Log.app.error("전사 결과를 읽지 못함: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError("전사 결과를 읽지 못했어요. 다시 시도해 주세요.")
        }
    }
}

/// 설정 > 전사의 "전사 도구 설치". 처음 한 번 Python 가상환경과 mlx-audio를 설치한다 (몇 분 걸림, 모델은 첫 전사 때 받음).
struct HelperScriptTranscriptionTool: TranscriptionToolManaging {
    func isReady() async throws -> Bool {
        try await TranscriptionHelperScript.run(["status"]) == 0
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
