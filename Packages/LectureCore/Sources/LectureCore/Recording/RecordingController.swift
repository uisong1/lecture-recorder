#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData

public enum RecordingError: Error, Equatable, LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case notPaused
    case resumeFailed(String)
    case insufficientStorage
    case startFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "마이크 권한이 없어 녹음할 수 없습니다. 시스템 설정에서 권한을 켜 주세요."
        case .alreadyRecording: "이미 녹음 중입니다."
        case .notRecording: "녹음 중이 아닙니다."
        case .notPaused: "일시정지 중이 아닙니다."
        case .resumeFailed(let reason): "녹음을 다시 시작하지 못했습니다: \(reason)"
        case .insufficientStorage: "저장 공간이 부족해 녹음을 시작할 수 없습니다."
        case .startFailed(let reason): "녹음을 시작하지 못했습니다: \(reason)"
        case .saveFailed(let reason): "녹음을 저장하지 못했습니다: \(reason)"
        }
    }
}

/// 녹음 시작·정지 흐름을 맡는 뷰모델.
/// 시작할 때 시간표로 과목을 정하고, 정지하면 `Recording`을 저장한다.
@MainActor
@Observable
public final class RecordingController {
    /// 녹음을 시작하려면 남아 있어야 하는 공간. 3시간 CAF(약 346MB)와 압축한 m4a(약 43MB)가 함께 있어도 남는 크기.
    public static let minimumFreeBytes: Int64 = 600 * 1024 * 1024
    /// 녹음 중 남은 공간이 이보다 적으면 경고한다 (1시간 분량).
    public static let storageWarningBytes = RecordingFormat.workingBytes(for: 3_600)
    /// 녹음 중 남은 공간이 이보다 적으면 바닥나기 전에 자동으로 정지·저장한다 (10분 분량).
    public static let storageCriticalBytes = RecordingFormat.workingBytes(for: 600)

    public enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case paused(startedAt: Date)

        var startedAt: Date? {
            switch self {
            case .idle: nil
            case .recording(let date), .paused(let date): date
            }
        }
    }

    public private(set) var state: State = .idle
    /// 녹음 중인 과목. nil이면 미분류.
    public private(set) var currentSubject: Subject?
    public private(set) var currentRelativePath: String?
    /// 마지막으로 저장된 녹음.
    public private(set) var lastSaved: Recording?
    public var errorMessage: String?
    /// 잠자기나 종료 때문에 녹음이 중단되어 저장됐을 때 보여줄 안내.
    public var interruptionNotice: String?
    /// 녹음 중 저장 공간이 부족해질 때 보여줄 경고. 문제가 없으면 nil.
    public private(set) var storageWarning: String?
    /// 지금 녹음에 찍은 북마크 시점(초). 정지하면 `Recording`의 북마크로 저장된다.
    public private(set) var bookmarkTimes: [TimeInterval] = []
    /// 녹음이 시작된 직후 불린다. 재생 중인 소리를 멈추는 데 쓴다 (재생 소리가 마이크로 들어가는 것 방지).
    public var onStarted: (@MainActor () -> Void)?
    /// 마지막으로 확인한 마이크 권한. 거부 상태면 화면이 녹음 버튼 대신 안내를 보여준다.
    public private(set) var permissionStatus: MicrophonePermissionStatus

    private let context: ModelContext
    private let recorder: any AudioRecording
    private let storage: RecordingStorage
    private let files: any FileStoring
    private let permission: any MicrophonePermissionProviding
    private let journal: (any RecordingJournaling)?
    private let sleepPreventer: (any SleepPreventing)?
    private let compressor: RecordingCompressor?
    private var compressionTask: Task<Void, Never>?
    private var storageMonitor: Task<Void, Never>?
    private let storageCheckInterval: Duration?
    private let calendar: Calendar
    private let now: @MainActor () -> Date

    public init(
        context: ModelContext,
        recorder: any AudioRecording,
        storage: RecordingStorage,
        files: any FileStoring = LocalFileStore(),
        permission: any MicrophonePermissionProviding,
        journal: (any RecordingJournaling)? = nil,
        sleepPreventer: (any SleepPreventing)? = nil,
        lifecycle: (any LifecycleEventSource)? = nil,
        compressor: RecordingCompressor? = nil,
        storageCheckInterval: Duration? = .seconds(10),
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.context = context
        self.recorder = recorder
        self.storage = storage
        self.files = files
        self.permission = permission
        self.permissionStatus = permission.currentStatus()
        self.journal = journal
        self.sleepPreventer = sleepPreventer
        self.compressor = compressor
        self.storageCheckInterval = storageCheckInterval
        self.calendar = calendar
        self.now = now
        lifecycle?.observe { [weak self] event in self?.handle(event) }
    }

    /// 잠자기나 종료 직전이면 그때까지의 녹음을 정상 파일로 닫아 저장한다.
    /// 깨어난 뒤에는 자동으로 이어 녹음하지 않고, 사용자가 다시 시작하도록 안내만 남긴다.
    func handle(_ event: LifecycleEvent) {
        switch event {
        case .willSleep, .willTerminate:
            guard isRecording else { return }
            let reason = event == .willSleep ? "맥이 잠자기에 들어가서" : "앱이 종료되어서"
            Log.recording.notice("\(reason, privacy: .public) 녹음을 저장")
            stopAndNotify(because: reason, advice: "이어서 녹음하려면 녹음을 다시 시작하세요.")
        case .didWake:
            break
        }
    }

    /// 녹음을 정상 정지해 저장하고, 왜 멈췄는지 안내를 남긴다.
    private func stopAndNotify(because reason: String, advice: String) {
        do {
            let saved = try stop()
            interruptionNotice = "\(reason) '\(saved.title)' 녹음을 여기까지 저장했습니다. \(advice)"
        } catch {
            errorMessage = error.errorDescription
        }
    }

    /// 녹음 중 남은 저장 공간을 확인한다. 1시간 분량 미만이면 경고하고, 10분 분량 미만이면 자동으로 정지·저장한다.
    /// 녹음 중에는 주기적으로 불리고, 공간을 알 수 없으면 아무 일도 하지 않는다.
    public func checkStorage() {
        guard isRecording, let free = files.availableCapacity(at: storage.root) else { return }
        if free < Self.storageCriticalBytes {
            Log.recording.error("저장 공간 바닥, 자동 정지: \(free, privacy: .public) bytes")
            stopAndNotify(because: "저장 공간이 거의 없어서", advice: "공간을 비운 뒤 다시 녹음하세요.")
        } else if free < Self.storageWarningBytes {
            let minutes = Int(free / RecordingFormat.workingBytesPerSecond / 60)
            storageWarning = "저장 공간이 부족합니다. 약 \(minutes)분 더 녹음할 수 있어요. 공간을 비워 주세요."
        } else {
            storageWarning = nil
        }
    }

    private func startStorageMonitor() {
        guard let interval = storageCheckInterval else { return }
        storageMonitor?.cancel()
        storageMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.checkStorage()
            }
        }
    }

    /// 마이크 권한이 거부되어 녹음할 수 없는 상태인지.
    public var isPermissionDenied: Bool { permissionStatus == .denied }

    /// 시스템 설정에서 권한을 바꾸고 돌아왔을 때 상태를 다시 읽는다.
    public func refreshPermission() {
        permissionStatus = permission.currentStatus()
        if permissionStatus != .denied, errorMessage == RecordingError.permissionDenied.errorDescription {
            errorMessage = nil
        }
    }

    /// 일시정지 중에도 true다 (녹음 세션이 열려 있다).
    public var isRecording: Bool { state != .idle }

    public var isPaused: Bool {
        if case .paused = state { true } else { false }
    }

    /// 화면에 보여줄 과목 이름.
    public var currentSubjectName: String {
        currentSubject?.name ?? SubjectManager.unclassifiedName
    }

    /// 녹음된 길이(초).
    public var elapsed: TimeInterval { isRecording ? recorder.currentTime : 0 }

    /// "mm:ss". 한 시간이 넘으면 분이 60 이상으로 늘어난다 (예: 95:03).
    public var elapsedText: String { Self.format(elapsed) }

    nonisolated public static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let secs = total % 60
        return (minutes < 10 ? "0\(minutes)" : "\(minutes)") + ":" + (secs < 10 ? "0\(secs)" : "\(secs)")
    }

    public func start() async throws(RecordingError) {
        guard !isRecording else { throw .alreadyRecording }
        permissionStatus = await permission.requestIfNeeded()
        guard permissionStatus == .granted else {
            Log.recording.notice("마이크 권한 없음")
            throw .permissionDenied
        }
        if let free = files.availableCapacity(at: storage.root), free < Self.minimumFreeBytes {
            Log.recording.error("저장 공간 부족: \(free, privacy: .public) bytes")
            throw .insufficientStorage
        }

        let startedAt = now()
        let subject = subject(at: startedAt)
        let relativePath = storage.newRelativePath(subjectName: subject?.name, startedAt: startedAt, calendar: calendar, fileExtension: RecordingStorage.workingExtension)
        do {
            try storage.prepareFolder(for: relativePath)
            try recorder.start(to: storage.url(for: relativePath))
        } catch {
            Log.recording.error("녹음 시작 실패: \(error.localizedDescription, privacy: .public)")
            throw .startFailed(error.localizedDescription)
        }
        currentSubject = subject
        currentRelativePath = relativePath
        bookmarkTimes = []
        state = .recording(startedAt: startedAt)
        interruptionNotice = nil
        storageWarning = nil
        startStorageMonitor()
        sleepPreventer?.begin(reason: "수업 녹음 중")
        onStarted?()
        do {
            try journal?.save(PendingRecording(relativePath: relativePath, subjectName: subject?.name, startedAt: startedAt))
        } catch {
            // 녹음은 계속한다. 복구만 안 될 뿐이다.
            Log.recording.error("녹음 저널 기록 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    public func stop() throws(RecordingError) -> Recording {
        guard let startedAt = state.startedAt, let relativePath = currentRelativePath else {
            throw .notRecording
        }
        let duration = recorder.stop()
        sleepPreventer?.end()
        storageMonitor?.cancel()
        storageMonitor = nil
        storageWarning = nil
        let recording = Recording(
            title: Self.defaultTitle(subjectName: currentSubjectName, startedAt: startedAt, calendar: calendar),
            subject: currentSubject,
            startedAt: startedAt,
            duration: duration,
            relativePath: relativePath
        )
        state = .idle
        currentSubject = nil
        currentRelativePath = nil

        context.insert(recording)
        let createdAt = now()
        for time in bookmarkTimes {
            context.insert(Bookmark(time: min(time, duration), createdAt: createdAt, recording: recording))
        }
        bookmarkTimes = []
        do {
            try context.save()
        } catch {
            // 파일은 이미 디스크에 있다. 다음 실행 때 복구할 수 있도록 로그를 남긴다.
            Log.recording.fault("녹음 메타데이터 저장 실패 \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .saveFailed(error.localizedDescription)
        }
        journal?.clear()
        lastSaved = recording
        startCompression(of: recording)
        return recording
    }

    /// 정지한 녹음을 백그라운드에서 m4a로 압축한다. 끝나기 전에도 녹음은 CAF로 재생된다.
    /// 여러 건이 겹쳐도 한 번에 하나씩 차례로 처리한다.
    private func startCompression(of recording: Recording) {
        guard let compressor else { return }
        let previous = compressionTask
        compressionTask = Task {
            await previous?.value
            await compressor.compress(recording)
        }
    }

    /// 진행 중인 압축이 모두 끝날 때까지 기다린다. 주로 테스트에서 쓴다.
    public func waitForCompression() async {
        await compressionTask?.value
    }

    /// 지금 녹음된 시점에 북마크를 찍는다. 녹음 중(일시정지 포함)이 아니면 아무 일도 하지 않는다.
    public func addBookmark() {
        guard isRecording else { return }
        bookmarkTimes.append(elapsed)
    }

    /// 녹음을 잠시 멈춘다. 이미 멈춘 상태면 아무 일도 하지 않는다.
    public func pause() throws(RecordingError) {
        switch state {
        case .idle: throw .notRecording
        case .paused: return
        case .recording(let startedAt):
            recorder.pause()
            state = .paused(startedAt: startedAt)
        }
    }

    /// 일시정지한 녹음을 같은 파일에 이어서 녹음한다.
    public func resume() throws(RecordingError) {
        guard case .paused(let startedAt) = state else { throw isRecording ? .notPaused : .notRecording }
        do {
            try recorder.resume()
        } catch {
            Log.recording.error("녹음 재개 실패: \(error.localizedDescription, privacy: .public)")
            throw .resumeFailed(error.localizedDescription)
        }
        state = .recording(startedAt: startedAt)
    }

    /// 일시정지 중이면 재개하고, 녹음 중이면 일시정지한다.
    public func togglePause() {
        do {
            if isPaused { try resume() } else { try pause() }
            errorMessage = nil
        } catch {
            errorMessage = error.errorDescription
        }
    }

    /// 버튼 하나로 시작·정지한다. 실패하면 `errorMessage`에 남긴다.
    public func toggle() async {
        do {
            if isRecording {
                try stop()
            } else {
                try await start()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.errorDescription
        }
    }

    /// "자료구조 3월 2일 10:00"
    nonisolated public static func defaultTitle(subjectName: String, startedAt: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: startedAt)
        let time = (try? TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0))?.description ?? ""
        return "\(subjectName) \(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }

    private func subject(at date: Date) -> Subject? {
        do {
            let slots = try context.fetch(FetchDescriptor<TimeSlot>())
            let schedule = ClassSchedule(entries: slots.compactMap { slot -> ClassSchedule<PersistentIdentifier>.Entry? in
                guard let period = slot.period, let subject = slot.subject else { return nil }
                return .init(period: period, subjectID: subject.persistentModelID)
            })
            guard case .subject(let id) = schedule.classify(at: date, calendar: calendar) else { return nil }
            return slots.first { $0.subject?.persistentModelID == id }?.subject
        } catch {
            Log.data.error("시간표 조회 실패, 미분류로 녹음: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
