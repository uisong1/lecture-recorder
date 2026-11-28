#if canImport(SwiftData)
import Foundation
import Observation

/// 전사할 녹음 하나. `id`는 녹음의 상대 경로라, 끝났을 때 그 녹음을 다시 찾는 데 쓴다.
public struct TranscriptionJob: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// 목록 둘째 줄 (예: "자료구조 · 11월 26일 · 1:28:14").
    public let subtitle: String
    public let audioURL: URL
    /// 녹음 길이(초). 남은 시간 어림에 쓴다.
    public let duration: TimeInterval

    public init(id: String, title: String, subtitle: String, audioURL: URL, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.audioURL = audioURL
        self.duration = duration
    }
}

/// 전사 엔진. 실제로는 샌드박스 밖 도우미 스크립트(mlx-audio)를 부른다. 테스트에서는 가짜를 쓴다.
/// 작업을 취소하면(`Task.cancel`) 하던 일을 멈추고 `CancellationError`를 던져야 한다.
public protocol Transcribing: Sendable {
    func transcribe(_ job: TranscriptionJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript
}

/// 녹음이 끝난 뒤 여러 녹음을 동시에(기본 2개) 전사하는 대기열. 녹음 중이거나 전원 조건이 안 맞으면 멈춘다.
@MainActor
@Observable
public final class TranscriptionQueue {
    public enum State: Equatable, Sendable {
        case waiting
        case running(progress: Double)
        case failed(String)
        case done
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public let job: TranscriptionJob
        public var state: State
        public var id: String { job.id }

        public init(job: TranscriptionJob, state: State) {
            self.job = job
            self.state = state
        }

        public var isRunning: Bool {
            if case .running = state { true } else { false }
        }

        /// 끝났거나 실패한 줄.
        public var isFinished: Bool {
            switch state {
            case .done, .failed: true
            case .waiting, .running: false
            }
        }
    }

    /// 동시에 전사할 수 있는 개수의 범위.
    nonisolated public static let concurrencyRange = 1...4
    nonisolated public static let defaultConcurrency = 2
    /// 오디오 1초를 전사하는 데 드는 시간 어림(초). 사용자 Mac에서 80초 음성에 약 15초(1.7B-8bit) 걸렸다.
    nonisolated public static let secondsPerAudioSecond: Double = 0.2

    public private(set) var entries: [Entry] = []
    /// 사용자가 "모두 멈춤"을 눌렀으면 true. 새 작업을 시작하지 않는다.
    public private(set) var isPaused = false
    /// 녹음 중이거나 전원 조건이 안 맞아 앱이 잠시 멈춘 상태면 그 이유.
    public private(set) var suspendReason: String?

    public var maxConcurrent: Int {
        didSet {
            let clamped = min(max(maxConcurrent, Self.concurrencyRange.lowerBound), Self.concurrencyRange.upperBound)
            if clamped != maxConcurrent { maxConcurrent = clamped }
            pump()
        }
    }

    /// 한 녹음의 전사가 끝나면 부른다. 저장에 실패하면 던진 오류가 그 줄의 실패 문구가 된다.
    @ObservationIgnored public var onFinished: @MainActor (TranscriptionJob, Transcript) throws -> Void = { _, _ in }

    @ObservationIgnored private let engine: Transcribing
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// 대기열에서 뺐거나 멈춘 작업. 취소되어 돌아올 때 대기로 되돌릴지 뺄지 가른다.
    @ObservationIgnored private var removedWhileRunning: Set<String> = []

    public init(engine: Transcribing, maxConcurrent: Int = TranscriptionQueue.defaultConcurrency) {
        self.engine = engine
        self.maxConcurrent = min(max(maxConcurrent, Self.concurrencyRange.lowerBound), Self.concurrencyRange.upperBound)
    }

    // MARK: 읽기

    public func state(for id: String) -> State? {
        entries.first { $0.id == id }?.state
    }

    public var runningCount: Int {
        entries.filter(\.isRunning).count
    }

    public var waitingCount: Int {
        entries.filter { $0.state == .waiting }.count
    }

    public var doneCount: Int {
        entries.filter { $0.state == .done }.count
    }

    /// 아직 끝나지 않은(대기·진행) 작업이 있는지.
    public var isActive: Bool {
        entries.contains { $0.state == .waiting || $0.isRunning }
    }

    /// 실패를 뺀 이번 묶음 전체 진행률(0...1). 끝난 것은 1, 대기는 0, 진행 중은 그 진행률로 센다. 녹음 길이로 가중한다.
    public var overallProgress: Double {
        Self.overallProgress(entries)
    }

    nonisolated public static func overallProgress(_ entries: [Entry]) -> Double {
        var total: Double = 0
        var done: Double = 0
        for entry in entries {
            let weight = max(entry.job.duration, 1)
            switch entry.state {
            case .failed: continue
            case .done: total += weight; done += weight
            case .waiting: total += weight
            case .running(let progress): total += weight; done += weight * min(max(progress, 0), 1)
            }
        }
        return total > 0 ? done / total : 0
    }

    /// 남은 시간 어림(초). 남은 오디오 길이 × 속도 ÷ 동시 개수.
    public var estimatedRemainingSeconds: TimeInterval {
        Self.estimatedRemainingSeconds(entries, concurrency: maxConcurrent)
    }

    nonisolated public static func estimatedRemainingSeconds(_ entries: [Entry], concurrency: Int) -> TimeInterval {
        var remainingAudio: Double = 0
        for entry in entries {
            switch entry.state {
            case .waiting: remainingAudio += entry.job.duration
            case .running(let progress): remainingAudio += entry.job.duration * (1 - min(max(progress, 0), 1))
            case .failed, .done: continue
            }
        }
        return remainingAudio * secondsPerAudioSecond / Double(max(concurrency, 1))
    }

    // MARK: 조작

    /// 대기열에 넣는다. 이미 대기·진행 중인 녹음은 건너뛰고, 실패·끝난 줄은 다시 대기로 바꾼다.
    /// 새 묶음을 시작할 때(진행 중인 것이 없을 때) 지난 묶음의 끝난 줄은 치운다.
    public func enqueue(_ jobs: [TranscriptionJob]) {
        if !isActive { entries.removeAll { $0.state == .done } }
        for job in jobs {
            if let index = entries.firstIndex(where: { $0.id == job.id }) {
                switch entries[index].state {
                case .failed, .done: entries[index] = Entry(job: job, state: .waiting)
                case .waiting, .running: continue
                }
            } else {
                entries.append(Entry(job: job, state: .waiting))
            }
        }
        pump()
    }

    /// 대기열에서 뺀다. 진행 중이면 멈추고 뺀다.
    public func remove(id: String) {
        if let task = tasks[id] {
            removedWhileRunning.insert(id)
            task.cancel()
        }
        entries.removeAll { $0.id == id && !$0.isRunning }
    }

    /// 실패한 줄을 다시 대기로.
    public func retry(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .failed = entries[index].state else { return }
        entries[index].state = .waiting
        pump()
    }

    /// 끝난 줄과 실패한 줄을 치운다.
    public func clearFinished() {
        entries.removeAll(where: \.isFinished)
    }

    /// "모두 멈춤": 진행 중인 것은 멈춰 대기로 되돌리고 새로 시작하지 않는다.
    public func pauseAll() {
        isPaused = true
        stopRunning()
    }

    public func resumeAll() {
        isPaused = false
        pump()
    }

    /// 녹음이 시작됐거나 전원 조건이 안 맞으면 이유를 넣어 멈추고, nil이면 다시 시작한다.
    public func setSuspended(_ reason: String?) {
        guard reason != suspendReason else { return }
        suspendReason = reason
        if reason != nil {
            stopRunning()
        } else {
            pump()
        }
    }

    // MARK: 내부

    private func stopRunning() {
        for task in tasks.values { task.cancel() }
    }

    private func pump() {
        guard !isPaused, suspendReason == nil else { return }
        while tasks.count < maxConcurrent, let index = entries.firstIndex(where: { $0.state == .waiting }) {
            start(entries[index].job)
        }
    }

    private func start(_ job: TranscriptionJob) {
        setState(.running(progress: 0), for: job.id)
        let engine = engine
        // 대기열은 앱이 켜져 있는 동안 계속 살아 있으므로 작업이 끝날 때까지 강하게 붙잡아도 된다.
        tasks[job.id] = Task {
            do {
                let transcript = try await engine.transcribe(job) { progress in
                    Task { @MainActor in self.updateProgress(progress, for: job.id) }
                }
                try Task.checkCancellation()
                self.finish(job, with: .success(transcript))
            } catch {
                self.finish(job, with: .failure(error))
            }
        }
    }

    private func updateProgress(_ progress: Double, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .running = entries[index].state else { return }
        entries[index].state = .running(progress: min(max(progress, 0), 1))
    }

    private func finish(_ job: TranscriptionJob, with result: Result<Transcript, Error>) {
        tasks[job.id] = nil
        let wasRemoved = removedWhileRunning.remove(job.id) != nil
        if wasRemoved {
            entries.removeAll { $0.id == job.id }
        } else {
            switch result {
            case .success(let transcript):
                do {
                    try onFinished(job, transcript)
                    setState(.done, for: job.id)
                } catch {
                    setState(.failed("저장하지 못했어요: \(error.localizedDescription)"), for: job.id)
                }
            case .failure(let error):
                if error is CancellationError {
                    // 멈춤·녹음 시작으로 끊긴 것: 처음부터 다시 하도록 대기로 되돌린다.
                    setState(.waiting, for: job.id)
                } else {
                    setState(.failed(Self.message(for: error)), for: job.id)
                }
            }
        }
        pump()
    }

    private func setState(_ state: State, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = state
    }

    private static func message(for error: Error) -> String {
        if let error = error as? TranscriptionError { return error.message }
        return error.localizedDescription
    }
}
#endif

/// 전사 실패 이유. 화면에 그대로 보인다.
public struct TranscriptionError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }

    /// 도우미 스크립트 종료 코드별 문구.
    public static func helperExit(_ status: Int?) -> TranscriptionError {
        switch status {
        case 20: TranscriptionError("전사 도구가 아직 설치되지 않았어요. 설정 > 전사에서 설치해 주세요.")
        case 21: TranscriptionError("녹음 파일을 읽지 못했어요.")
        case 22: TranscriptionError("전사 모델을 불러오지 못했어요. 인터넷 연결(처음 한 번 모델을 받아요)과 저장 공간을 확인해 주세요.")
        case 23: TranscriptionError("전사하다 멈췄어요. 다시 시도해 주세요.")
        default: TranscriptionError("전사하지 못했어요 (코드 \(status.map(String.init) ?? "?")). 로그: ~/Library/Logs/LectureRecorder-transcribe.log")
        }
    }
}
