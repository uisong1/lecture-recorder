#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 전사할 녹음 하나. `id`는 녹음의 고정 id(`Recording.transcriptionKey`)라, 전사 중 과목을 옮겨 경로가 바뀌어도 같은 녹음을 찾는다.
public struct TranscriptionJob: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// 목록 둘째 줄 (예: "자료구조 · 11월 26일 · 1:28:14").
    public let subtitle: String
    public let audioURL: URL
    /// 녹음 길이(초). 남은 시간 어림에 쓴다.
    public let duration: TimeInterval
    /// 결과를 저장할 녹음. 없으면(테스트) `id`로만 구분한다.
    public let recordingID: PersistentIdentifier?
    /// 멈췄다 이어서 할 때 엔진이 하던 일(끝낸 조각)을 찾는 열쇠. 대기열에 넣을 때 정해지고 멈춰도 바뀌지 않는다.
    public let workID: UUID

    public init(
        id: String,
        title: String,
        subtitle: String,
        audioURL: URL,
        duration: TimeInterval,
        recordingID: PersistentIdentifier? = nil,
        workID: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.audioURL = audioURL
        self.duration = duration
        self.recordingID = recordingID
        self.workID = workID
    }

    /// 녹음이 옮겨졌거나 이름이 바뀐 뒤의 최신 정보로 바꾼 작업. 이어 하기 열쇠는 그대로 둔다.
    public func refreshed(title: String, subtitle: String, audioURL: URL, duration: TimeInterval) -> TranscriptionJob {
        TranscriptionJob(id: id, title: title, subtitle: subtitle, audioURL: audioURL, duration: duration, recordingID: recordingID, workID: workID)
    }
}

/// 전사 엔진. 실제로는 샌드박스 밖 도우미 스크립트(mlx-audio)를 부른다. 테스트에서는 가짜를 쓴다.
/// 작업을 취소하면(`Task.cancel`) 하던 일을 멈추고 `CancellationError`를 던져야 한다.
public protocol Transcribing: Sendable {
    func transcribe(_ job: TranscriptionJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript
    /// 멈춰 둔 작업을 대기열에서 뺐을 때, 이어 하려고 남겨 둔 것(끝낸 조각)을 지운다.
    func discardWork(for job: TranscriptionJob)
}

extension Transcribing {
    public func discardWork(for job: TranscriptionJob) {}
}

/// 녹음이 끝난 뒤 여러 녹음을 동시에(기본 2개) 전사하는 대기열. 녹음 중이거나 전원 조건이 안 맞으면 멈춘다.
@MainActor
@Observable
public final class TranscriptionQueue {
    public enum State: Equatable, Sendable {
        case waiting
        case running(progress: Double)
        /// "멈춤"을 눌렀고, 도구가 지금 조각(최대 3분)을 마치길 기다리는 중.
        case stopping(progress: Double)
        /// 사용자가 멈춘 작업. "이어서"를 누르기 전에는 시작하지 않는다.
        case paused(progress: Double)
        case failed(String)
        case done
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public internal(set) var job: TranscriptionJob
        public var state: State
        /// 실패했을 때 도우미가 남긴 마지막 몇 줄. 실패 줄 아래 작게 보인다.
        public var failureDetail: String?
        public var id: String { job.id }

        public init(job: TranscriptionJob, state: State, failureDetail: String? = nil) {
            self.job = job
            self.state = state
            self.failureDetail = failureDetail
        }

        /// 엔진이 돌고 있는 줄 (멈추는 중 포함).
        public var isRunning: Bool {
            switch state {
            case .running, .stopping: true
            case .waiting, .paused, .failed, .done: false
            }
        }

        /// 끝났거나 실패한 줄.
        public var isFinished: Bool {
            switch state {
            case .done, .failed: true
            case .waiting, .running, .stopping, .paused: false
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
    /// 작업을 시작하기 직전에 부른다. 그 사이 녹음이 옮겨졌으면 새 경로로 바꾼 작업을, 지워졌으면 nil을 돌려준다.
    /// 찾다가 오류가 나면 던지고, 그 이유가 줄의 실패 문구가 된다.
    @ObservationIgnored public var resolveJob: @MainActor (TranscriptionJob) throws -> TranscriptionJob? = { $0 }

    @ObservationIgnored private let engine: Transcribing
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// 대기열에서 뺐거나 멈춘 작업. 취소되어 돌아올 때 대기로 되돌릴지 뺄지 가른다.
    @ObservationIgnored private var removedWhileRunning: Set<String> = []
    /// 사용자가 "멈춤"을 눌러 취소한 작업. 돌아오면 대기 대신 멈춤으로 둔다.
    @ObservationIgnored private var pausingIDs: Set<String> = []

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

    /// 아직 끝나지 않은(대기·진행) 작업이 있는지. 사용자가 멈춘 줄은 넣지 않는다.
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
            case .running(let progress), .stopping(let progress), .paused(let progress):
                total += weight; done += weight * min(max(progress, 0), 1)
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
            case .running(let progress), .stopping(let progress): remainingAudio += entry.job.duration * (1 - min(max(progress, 0), 1))
            case .paused, .failed, .done: continue
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
                case .done: entries[index] = Entry(job: job, state: .waiting)
                // 실패한 작업은 남은 조각을 이어 쓰도록 작업을 그대로 두고 대기로 돌린다.
                case .failed:
                    entries[index].state = .waiting
                    entries[index].failureDetail = nil
                // 멈춰 둔 작업은 하던 데서 이어 하도록 작업(이어 하기 열쇠)을 그대로 두고 대기로 돌린다.
                case .paused(let progress):
                    lastProgress[job.id] = progress
                    entries[index].state = .waiting
                case .waiting, .running, .stopping: continue
                }
            } else {
                entries.append(Entry(job: job, state: .waiting))
            }
        }
        pump()
    }

    /// 대기열에서 뺀다. 진행 중이면 멈추고 뺀다. 이어 하려고 남겨 둔 것도 지운다.
    public func remove(id: String) {
        lastProgress[id] = nil
        if let task = tasks[id] {
            removedWhileRunning.insert(id)
            pausingIDs.remove(id)
            task.cancel()
        }
        if let entry = entries.first(where: { $0.id == id && !$0.isRunning }) {
            engine.discardWork(for: entry.job)
        }
        entries.removeAll { $0.id == id && !$0.isRunning }
    }

    /// 진행 중인 작업을 멈춘다. 도구가 지금 조각을 마칠 때까지 "멈추는 중"이고, 그 뒤 멈춤이 된다.
    /// 대기 중인 작업은 바로 멈춤이 된다. "이어서"(`resume`)로 하던 데서 다시 한다.
    public func pause(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        switch entries[index].state {
        case .running(let progress):
            pausingIDs.insert(id)
            entries[index].state = .stopping(progress: progress)
            tasks[id]?.cancel()
        case .waiting:
            entries[index].state = .paused(progress: lastProgress[id] ?? 0)
        case .stopping, .paused, .failed, .done:
            return
        }
    }

    /// 멈춘 작업을 대기로 돌려 다시 시작한다.
    public func resume(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .paused(let progress) = entries[index].state else { return }
        lastProgress[id] = progress
        entries[index].state = .waiting
        pump()
    }

    /// 실패한 줄을 다시 대기로.
    public func retry(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .failed = entries[index].state else { return }
        entries[index].state = .waiting
        entries[index].failureDetail = nil
        pump()
    }

    /// 끝난 줄과 실패한 줄을 치운다. 실패한 줄이 남겨 둔 것도 지운다.
    public func clearFinished() {
        for entry in entries where entry.isFinished { engine.discardWork(for: entry.job) }
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

    private func start(_ queued: TranscriptionJob) {
        // 기다리는 사이 녹음을 옮겼거나 지웠을 수 있다. 시작 직전에 다시 찾는다.
        let resolved: TranscriptionJob?
        do {
            resolved = try resolveJob(queued)
        } catch {
            // 녹음을 찾다가 난 오류(DB). 지운 것과 다르니 하던 것은 남기고 이유를 보인다.
            setState(.failed("녹음을 찾지 못했어요: \(Self.message(for: error))"), for: queued.id)
            return
        }
        guard let job = resolved else {
            setState(.failed("녹음을 찾지 못했어요. 지웠을 수 있어요."), for: queued.id)
            engine.discardWork(for: queued)
            return
        }
        if let index = entries.firstIndex(where: { $0.id == job.id }) { entries[index].job = job }
        setState(.running(progress: startingProgress(for: job.id)), for: job.id)
        let engine = engine
        // 대기열은 앱이 켜져 있는 동안 계속 살아 있으므로 작업이 끝날 때까지 강하게 붙잡아도 된다.
        tasks[job.id] = Task {
            do {
                let transcript = try await engine.transcribe(job) { progress in
                    Task { @MainActor in self.updateProgress(progress, for: job.id) }
                }
                // 결과가 다 나왔으면 그 사이 멈춤·녹음 시작이 있었어도 버리지 않고 저장한다.
                self.finish(job, with: .success(transcript))
            } catch {
                self.finish(job, with: .failure(error))
            }
        }
    }

    /// 멈췄다 이어 할 때는 멈춘 진행률에서 시작해 보인다 (도구가 끝낸 조각을 건너뛴다).
    private func startingProgress(for id: String) -> Double {
        guard let entry = entries.first(where: { $0.id == id }) else { return 0 }
        switch entry.state {
        case .paused(let progress), .running(let progress), .stopping(let progress): return progress
        case .waiting, .failed, .done: return lastProgress[id] ?? 0
        }
    }

    /// 녹음 시작 등으로 끊겨 대기로 돌아간 작업의 진행률. 다시 시작할 때 0으로 보이지 않게 기억한다.
    @ObservationIgnored private var lastProgress: [String: Double] = [:]

    private func updateProgress(_ progress: Double, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(progress, 0), 1)
        switch entries[index].state {
        case .running: entries[index].state = .running(progress: clamped)
        case .stopping: entries[index].state = .stopping(progress: clamped)
        case .waiting, .paused, .failed, .done: return
        }
    }

    private func progress(of id: String) -> Double {
        switch entries.first(where: { $0.id == id })?.state {
        case .running(let progress), .stopping(let progress), .paused(let progress): progress
        default: 0
        }
    }

    private func finish(_ job: TranscriptionJob, with result: Result<Transcript, Error>) {
        tasks[job.id] = nil
        let wasRemoved = removedWhileRunning.remove(job.id) != nil
        let wasPausing = pausingIDs.remove(job.id) != nil
        if wasRemoved {
            engine.discardWork(for: job)
            entries.removeAll { $0.id == job.id }
        } else {
            switch result {
            case .success(let transcript):
                lastProgress[job.id] = nil
                do {
                    try onFinished(job, transcript)
                    setState(.done, for: job.id)
                    engine.discardWork(for: job)
                } catch {
                    // 결과는 엔진이 남겨 두어 "다시 시도"하면 처음부터 하지 않고 다시 저장한다.
                    setState(.failed("저장하지 못했어요: \(Self.message(for: error))"), for: job.id)
                    if let index = entries.firstIndex(where: { $0.id == job.id }) {
                        entries[index].failureDetail = (error as? TranscriptionError)?.detail ?? error.localizedDescription
                    }
                }
            case .failure(let error):
                if error is CancellationError {
                    let progress = progress(of: job.id)
                    if wasPausing {
                        // 사용자가 멈춘 것: 하던 데까지 기억하고 "이어서"를 기다린다.
                        setState(.paused(progress: progress), for: job.id)
                    } else {
                        // 모두 멈춤·녹음 시작으로 끊긴 것: 대기로 돌려 조건이 맞으면 이어서 한다.
                        lastProgress[job.id] = progress
                        setState(.waiting, for: job.id)
                    }
                } else {
                    lastProgress[job.id] = nil
                    setState(.failed(Self.message(for: error)), for: job.id)
                    if let index = entries.firstIndex(where: { $0.id == job.id }) {
                        entries[index].failureDetail = (error as? TranscriptionError)?.detail
                    }
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
    /// 도우미가 남긴 오류의 마지막 몇 줄. 실패 줄 아래 작게 보인다.
    public let detail: String?
    public init(_ message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }

    /// 같은 이유에 도우미 오류 내용을 붙인다.
    public func with(detail: String?) -> TranscriptionError {
        TranscriptionError(message, detail: detail)
    }

    /// 도우미가 stderr에 남긴 글에서 마지막 `lines`줄(빈 줄 제외)을 고른다. 없으면 nil.
    public static func tail(of log: String, lines: Int = 3) -> String? {
        let kept = log.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !kept.isEmpty else { return nil }
        return kept.suffix(lines).joined(separator: "\n")
    }

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
