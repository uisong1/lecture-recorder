#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

/// 전사 도구(도우미 스크립트 + Python 가상환경의 mlx-audio)가 준비됐는지.
public enum TranscriptionToolStatus: Equatable, Sendable {
    case checking
    case ready
    /// 도우미는 있지만 Python 도구를 아직 설치하지 않았다.
    case notInstalled
    /// install.sh로 설치하지 않아 도우미 스크립트가 없다.
    case helperMissing
    case installing
    case failed(String)
}

public enum TranscriptionToolError: Error, Equatable, Sendable {
    case helperMissing
    case failed(String)
}

/// 전사 도구를 확인하고 설치한다. 실제로는 도우미 스크립트의 status·setup을 부른다.
public protocol TranscriptionToolManaging: Sendable {
    /// 도구가 준비됐으면 true. 도우미가 없으면 `TranscriptionToolError.helperMissing`.
    func isReady() async throws -> Bool
    func install() async throws
}

/// 전사 설정(동시 개수, 전원 연결 때만). 테스트에서는 메모리에 둔다.
@MainActor
public protocol TranscriptionPreferences: AnyObject {
    var concurrency: Int { get set }
    var powerOnly: Bool { get set }
}

@MainActor
public final class UserDefaultsTranscriptionPreferences: TranscriptionPreferences {
    private let defaults: UserDefaults
    static let concurrencyKey = "transcriptionConcurrency"
    static let powerOnlyKey = "transcriptionPowerOnly"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var concurrency: Int {
        get { defaults.object(forKey: Self.concurrencyKey) as? Int ?? TranscriptionQueue.defaultConcurrency }
        set { defaults.set(newValue, forKey: Self.concurrencyKey) }
    }

    public var powerOnly: Bool {
        get { defaults.bool(forKey: Self.powerOnlyKey) }
        set { defaults.set(newValue, forKey: Self.powerOnlyKey) }
    }
}

/// "전사" 탭의 상태. 전사할 녹음 목록, 고르기, 대기열, 도구 설치, 녹음 중·전원 조건에 따른 멈춤을 맡는다.
@MainActor
@Observable
public final class TranscriptionCenter {
    public static let recordingPauseReason = "녹음 중이라 전사를 잠시 멈췄어요. 녹음이 끝나면 이어서 해요."
    public static let powerPauseReason = "전원에 연결되면 전사를 시작해요 (설정 > 전사)."

    public let queue: TranscriptionQueue
    public private(set) var toolStatus: TranscriptionToolStatus = .checking
    /// 아직 전사하지 않은 녹음. 최근 녹음이 위.
    public private(set) var candidates: [Recording] = []
    /// 전사를 마친 녹음. 최근 녹음이 위.
    public private(set) var transcribed: [Recording] = []
    public var isSelecting = false {
        didSet { if !isSelecting { selection = [] } }
    }
    /// 고른 녹음의 상대 경로.
    public var selection: Set<String> = []
    public var errorMessage: String?

    public var concurrency: Int {
        get { queue.maxConcurrent }
        set {
            queue.maxConcurrent = newValue
            preferences.concurrency = queue.maxConcurrent
        }
    }

    public var powerOnly: Bool {
        didSet {
            preferences.powerOnly = powerOnly
            refreshConditions()
        }
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let storage: RecordingStorage
    @ObservationIgnored private let tool: TranscriptionToolManaging
    @ObservationIgnored private let preferences: TranscriptionPreferences
    @ObservationIgnored private let power: PowerStatusProviding?
    @ObservationIgnored private let activePaths: () -> Set<String>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    private var isRecording = false

    public init(
        context: ModelContext,
        storage: RecordingStorage,
        engine: Transcribing,
        tool: TranscriptionToolManaging,
        preferences: TranscriptionPreferences,
        power: PowerStatusProviding? = nil,
        activePaths: @escaping () -> Set<String> = { [] },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.context = context
        self.storage = storage
        self.tool = tool
        self.preferences = preferences
        self.power = power
        self.activePaths = activePaths
        self.now = now
        self.calendar = calendar
        powerOnly = preferences.powerOnly
        queue = TranscriptionQueue(engine: engine, maxConcurrent: preferences.concurrency)
        queue.onFinished = { [weak self] job, transcript in
            try self?.save(transcript, for: job)
        }
        reload()
        refreshConditions()
    }

    // MARK: 목록

    public func reload() {
        let all: [Recording]
        do {
            all = try context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        } catch {
            Log.data.error("전사 목록을 읽지 못함: \(error.localizedDescription, privacy: .public)")
            errorMessage = "녹음 목록을 읽지 못했어요: \(error.localizedDescription)"
            return
        }
        let active = activePaths()
        transcribed = all.filter(\.hasTranscript)
        candidates = all.filter { !$0.hasTranscript && Self.canTranscribe($0, active: active) }
        selection = selection.intersection(candidates.map(\.relativePath))
    }

    /// 녹음 중인 파일, 아직 압축 전(.caf)인 파일은 전사하지 않는다. 압축이 끝나면 경로가 바뀌기 때문이다.
    nonisolated static func canTranscribe(_ recording: Recording, active: Set<String>) -> Bool {
        !active.contains(recording.relativePath) && !recording.relativePath.lowercased().hasSuffix(".caf")
    }

    public func recording(for id: String) -> Recording? {
        (candidates + transcribed).first { $0.relativePath == id }
    }

    /// 대기·진행 중이 아닌 전사 안 된 녹음.
    public var idleCandidates: [Recording] {
        candidates.filter { queue.state(for: $0.relativePath) == nil }
    }

    public var candidatesDuration: TimeInterval {
        candidates.reduce(0) { $0 + $1.duration }
    }

    public var selectedDuration: TimeInterval {
        candidates.filter { selection.contains($0.relativePath) }.reduce(0) { $0 + $1.duration }
    }

    /// "자료구조 · 11월 26일 · 1:28:14"
    public func subtitle(for recording: Recording) -> String {
        let components = calendar.dateComponents([.month, .day], from: recording.startedAt)
        let date = "\(components.month ?? 0)월 \(components.day ?? 0)일"
        return [recording.subject?.name ?? "미분류", date, Transcript.timestamp(recording.duration)].joined(separator: " · ")
    }

    public func job(for recording: Recording) -> TranscriptionJob {
        TranscriptionJob(
            id: recording.relativePath,
            title: recording.title,
            subtitle: subtitle(for: recording),
            audioURL: storage.url(for: recording.relativePath),
            duration: recording.duration
        )
    }

    // MARK: 전사 시작

    public func transcribeAll() {
        enqueue(candidates)
    }

    public func transcribeSelected() {
        enqueue(candidates.filter { selection.contains($0.relativePath) })
        isSelecting = false
    }

    public func transcribe(_ recording: Recording) {
        enqueue([recording])
    }

    public func toggleSelection(_ recording: Recording) {
        if selection.contains(recording.relativePath) {
            selection.remove(recording.relativePath)
        } else {
            selection.insert(recording.relativePath)
        }
    }

    public func selectAll() {
        selection = Set(idleCandidates.map(\.relativePath))
    }

    private func enqueue(_ recordings: [Recording]) {
        switch toolStatus {
        case .notInstalled, .helperMissing, .failed, .installing:
            errorMessage = "먼저 전사 도구를 설치해 주세요 (설정 > 전사)."
            return
        case .ready, .checking:
            break
        }
        errorMessage = nil
        let active = activePaths()
        queue.enqueue(recordings.filter { Self.canTranscribe($0, active: active) }.map(job(for:)))
    }

    private func save(_ transcript: Transcript, for job: TranscriptionJob) throws {
        let id = job.id
        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.relativePath == id })
        descriptor.fetchLimit = 1
        guard let recording = try context.fetch(descriptor).first else {
            throw TranscriptionError("녹음을 찾지 못했어요. 옮겼거나 지웠을 수 있어요.")
        }
        recording.transcriptData = try transcript.encoded()
        recording.transcribedAt = now()
        do {
            try context.save()
        } catch {
            context.rollback()
            Log.data.error("전사 결과 저장 실패: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        reload()
    }

    /// 전사 결과를 지운다 (다시 전사하고 싶을 때).
    public func removeTranscript(of recording: Recording) {
        recording.transcriptData = nil
        recording.transcribedAt = nil
        do {
            try context.save()
        } catch {
            context.rollback()
            Log.data.error("전사 결과 지우기 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "전사 결과를 지우지 못했어요: \(error.localizedDescription)"
        }
        reload()
    }

    // MARK: 도구

    public func checkTool() async {
        do {
            toolStatus = try await tool.isReady() ? .ready : .notInstalled
        } catch TranscriptionToolError.helperMissing {
            toolStatus = .helperMissing
        } catch {
            Log.app.error("전사 도구 확인 실패: \(error.localizedDescription, privacy: .public)")
            toolStatus = .failed("전사 도구를 확인하지 못했어요: \(error.localizedDescription)")
        }
    }

    public func installTool() async {
        guard toolStatus != .installing else { return }
        toolStatus = .installing
        do {
            try await tool.install()
            toolStatus = .ready
        } catch TranscriptionToolError.helperMissing {
            toolStatus = .helperMissing
        } catch TranscriptionToolError.failed(let message) {
            Log.app.error("전사 도구 설치 실패: \(message, privacy: .public)")
            toolStatus = .failed(message)
        } catch {
            Log.app.error("전사 도구 설치 실패: \(error.localizedDescription, privacy: .public)")
            toolStatus = .failed("설치하지 못했어요: \(error.localizedDescription)")
        }
    }

    // MARK: 멈춤 조건

    /// 녹음을 시작하면 전사를 멈춘다(녹음이 항상 먼저). 끝나면 이어서 한다.
    public func recordingDidStart() {
        isRecording = true
        refreshConditions()
    }

    public func recordingDidStop() {
        isRecording = false
        reload()
        refreshConditions()
    }

    /// 녹음 중이거나, "전원 연결 때만"인데 배터리로 쓰고 있으면 멈춘다. 전원 상태가 바뀔 수 있어 주기적으로 부른다.
    public func refreshConditions() {
        if isRecording {
            queue.setSuspended(Self.recordingPauseReason)
        } else if powerOnly, let status = power?.current(), !status.isPluggedIn {
            queue.setSuspended(Self.powerPauseReason)
        } else {
            queue.setSuspended(nil)
        }
    }
}
#endif
