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

/// 녹음을 시작하기 전에 고른 과목. 고르지 않으면 시간표로 자동 분류한다.
public enum SubjectChoice: Hashable {
    case automatic
    case unclassified
    case subject(PersistentIdentifier)
}

/// 녹음 시작·정지 흐름을 맡는 뷰모델.
/// 시작할 때 시간표로 과목을 정하고, 정지하면 `Recording`을 저장한다.
@MainActor
@Observable
public final class RecordingController {
    /// 녹음을 시작하려면 남아 있어야 하는 공간. 3시간 CAF(약 346MB)와 압축한 m4a(약 43MB)가 함께 있어도 남는 크기.
    public static let minimumFreeBytes: Int64 = 600 * 1024 * 1024
    /// 녹음 중 남은 공간이 이보다 적으면 경고한다 (1시간 분량).
    public static let storageWarningBytes = StorageSpaceStatus.warningBytes
    /// 녹음 중 남은 공간이 이보다 적으면 바닥나기 전에 자동으로 정지·저장한다 (10분 분량).
    public static let storageCriticalBytes = StorageSpaceStatus.criticalBytes

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
    /// 시작 전에 직접 고른 과목 (보강·휴강으로 시간표와 다른 날). 녹음을 시작하면 자동으로 돌아간다.
    public var subjectChoice: SubjectChoice = .automatic
    /// 녹음 중인 과목. nil이면 미분류.
    public private(set) var currentSubject: Subject?
    /// 녹음 중에 과목이 지워져도 안전하게 읽도록 시작할 때 따로 적어 둔 과목 식별자와 이름.
    /// 지워진 모델의 속성을 읽으면 앱이 죽을 수 있어, 녹음 중에는 `currentSubject`의 속성을 읽지 않는다.
    private var currentSubjectID: PersistentIdentifier?
    private var currentSubjectLabel: String?
    public private(set) var currentRelativePath: String?
    /// 마지막으로 저장된 녹음.
    public private(set) var lastSaved: Recording?
    public var errorMessage: String?
    /// 잠자기나 종료 때문에 녹음이 중단되어 저장됐을 때 보여줄 안내.
    public var interruptionNotice: String?
    /// 녹음기가 조용히 멈춰 녹음을 저장했을 때 보일 큰 경고. 멈추지 않았으면 nil. 새 녹음을 시작하면 사라진다.
    public private(set) var recorderStallNotice: String?
    /// 녹음기가 멈춰 새 파일로 이어 녹음하는 중일 때의 안내. 이어 녹음하는 동안만 값이 있다.
    public private(set) var stallResumeNotice: String?
    /// 녹음 중 저장 공간이 부족해질 때 보여줄 경고. 문제가 없으면 nil.
    public private(set) var storageWarning: String?
    /// 이 시간(초)보다 짧게 끝난 녹음은 저장할지 묻는다.
    public static let shortRecordingSeconds: TimeInterval = 5
    /// 방금 정지한, 너무 짧아서 저장할지 묻는 중인 녹음. 없으면 nil.
    public private(set) var shortRecordingPrompt: Recording?
    /// 녹음 중 마이크가 바뀌거나 끊겼을 때 보일 경고. 문제가 없으면 nil. 녹음은 계속된다.
    public private(set) var inputDeviceWarning: String?
    /// 지금 쓰는 마이크 이름. 대기·녹음 화면에 보인다. 알 수 없으면 nil.
    public var inputDeviceName: String? {
        inputMonitor?.currentDevice()?.name
    }
    /// 지금 입력 크기 (0...1). 녹음 중이 아니거나 일시정지 중이면 0.
    public private(set) var inputLevel: Float = 0
    /// 마이크 확인에 걸리는 시간(초).
    public static let previewDuration: TimeInterval = 5
    /// 마이크 확인 결과.
    public enum PreviewOutcome: Equatable {
        /// 소리가 들어옴.
        case heard
        /// 확인하는 동안 소리가 거의 안 들어옴.
        case quiet
    }
    /// 마이크 확인 중인 입력 크기 (0...1). 확인 중이 아니면 0.
    public private(set) var previewLevel: Float = 0
    /// 마이크 확인이 진행 중인지.
    public private(set) var isPreviewing = false
    /// 방금 끝난 마이크 확인의 결과. 다시 확인하거나 녹음을 시작하면 지워진다.
    public private(set) var previewOutcome: PreviewOutcome?
    /// 10초 넘게 거의 무음이면 true. 화면이 "소리가 거의 들어오지 않습니다"를 보인다.
    public private(set) var isInputSilent = false
    /// 지금 녹음에 찍은 북마크 시점(초). 정지하면 `Recording`의 북마크로 저장된다.
    public private(set) var bookmarkTimes: [TimeInterval] = []
    /// `bookmarkTimes`와 같은 순서의 짧은 메모. 메모가 없으면 빈 문자열.
    public private(set) var bookmarkNotes: [String] = []
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
    private let powerStatus: (any PowerStatusProviding)?
    private let inputMonitor: (any AudioInputMonitoring)?
    private let levelPreview: (any AudioLevelPreviewing)?
    private var previewMonitor: Task<Void, Never>?
    private var previewStartedAt: Date?
    private var previewPeak: Float = 0
    private let overrunNotifier: (any NotificationScheduling)?
    private var classEnd: Date?
    private var overrunNotified = false
    /// 지금 일시정지가 시작된 시각. 일시정지 중이 아니면 nil.
    private var pausedAt: Date?
    /// 녹음을 시작할 때 읽어 둔 시간표와 과목 (화면이 자주 다시 읽어도 매번 DB를 조회하지 않는다).
    private var scheduleSnapshot: ClassSchedule<PersistentIdentifier>?
    private var subjectsByID: [PersistentIdentifier: Subject] = [:]
    private var nextClassNotifiedID: PersistentIdentifier?
    private let alertRaiser: RecordingAlertRaiser
    private var recordingInputDevice: AudioInputDevice?
    private let compressor: RecordingCompressor?
    private var compressionTask: Task<Void, Never>?
    private var storageMonitor: Task<Void, Never>?
    private let storageCheckInterval: Duration?
    private var discardTask: Task<Void, Never>?
    private var levelMonitor: Task<Void, Never>?
    private let levelCheckInterval: Duration?
    private var silenceDetector = SilenceDetector()
    private var healthMonitor = RecorderHealthMonitor()
    /// 지금 녹음이 멈춘 녹음을 이은 두 번째 파일인지. 사용자가 직접 시작하면 지워지고, 이어 녹음은 한 번만 한다.
    private var isStallContinuation = false
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
        powerStatus: (any PowerStatusProviding)? = nil,
        inputMonitor: (any AudioInputMonitoring)? = nil,
        levelPreview: (any AudioLevelPreviewing)? = nil,
        overrunNotifier: (any NotificationScheduling)? = nil,
        lifecycle: (any LifecycleEventSource)? = nil,
        compressor: RecordingCompressor? = nil,
        storageCheckInterval: Duration? = .seconds(10),
        levelCheckInterval: Duration? = .milliseconds(100),
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
        self.powerStatus = powerStatus
        self.inputMonitor = inputMonitor
        self.levelPreview = levelPreview
        self.overrunNotifier = overrunNotifier
        alertRaiser = RecordingAlertRaiser(notifier: overrunNotifier)
        self.compressor = compressor
        self.storageCheckInterval = storageCheckInterval
        self.levelCheckInterval = levelCheckInterval
        self.calendar = calendar
        self.now = now
        lifecycle?.observe { [weak self] event in self?.handle(event) }
        inputMonitor?.observe { [weak self] in self?.checkInputDevice() }
    }

    /// 잠자기나 종료 직전이면 그때까지의 녹음을 정상 파일로 닫아 저장한다.
    /// 깨어난 뒤에는 자동으로 이어 녹음하지 않고, 사용자가 다시 시작하도록 안내만 남긴다.
    func handle(_ event: LifecycleEvent) {
        switch event {
        case .willSleep, .willTerminate:
            guard isRecording else { return }
            let reason = event == .willSleep ? "맥이 잠자기에 들어가서" : "앱이 종료되어서"
            Log.recording.notice("\(reason, privacy: .public) 녹음을 저장")
            stopAndNotify(because: reason, advice: "이어서 녹음하려면 녹음을 다시 시작하세요.", alert: event == .willSleep ? .savedBeforeSleep : .savedBeforeQuit)
        case .didWake:
            break
        }
    }

    /// 녹음을 정상 정지해 저장하고, 왜 멈췄는지 안내를 남긴다.
    private func stopAndNotify(because reason: String, advice: String, alert: RecordingAlert, recorderStalled: Bool = false) {
        // 저장이 실패해도 멈춘 사실은 알린다.
        raise(alert)
        do {
            let saved = try finishRecording(recorderStalled: recorderStalled)
            interruptionNotice = "\(reason) '\(saved.title)' 녹음을 여기까지 저장했습니다. \(advice)"
        } catch {
            errorMessage = error.errorDescription
        }
    }

    /// 녹음 중 남은 저장 공간을 확인한다. 1시간 분량 미만이면 경고하고, 10분 분량 미만이면 자동으로 정지·저장한다.
    /// 녹음 중에는 주기적으로 불리고, 공간을 알 수 없으면 아무 일도 하지 않는다.
    public func checkStorage() {
        guard isRecording, let free = files.availableCapacity(at: storage.root) else { return }
        let status = StorageSpaceStatus.assess(freeBytes: free)
        if status == .critical {
            Log.recording.error("저장 공간 바닥, 자동 정지: \(free, privacy: .public) bytes")
            stopAndNotify(because: "저장 공간이 거의 없어서", advice: "공간을 비운 뒤 다시 녹음하세요.", alert: .storageFull)
        } else {
            storageWarning = status.warningMessage
        }
    }

    /// 녹음기가 실제로 녹음하고 있는지 확인한다. 녹음기가 끝났다고 알렸거나 경과 시간이 30초(연속 3번 점검) 동안
    /// 늘지 않으면 지금까지의 녹음을 정상 파일로 닫아 저장한다. 처음 멈춘 것이면 같은 과목으로 새 파일에 한 번 이어 녹음하고
    /// (`stallResumeNotice`), 이어 녹음하다 또 멈췄거나 이어 녹음을 시작하지 못하면 멈추고 `recorderStallNotice`로 크게 알린다.
    /// 일시정지 중에는 확인하지 않는다. 녹음 중에는 10초마다 불린다.
    public func checkRecorderHealth() {
        guard isRecording else { return }
        guard let reason = healthMonitor.check(recorder, isPaused: isPaused) else { return }
        Log.recording.fault("녹음기가 멈춤 (\(String(describing: reason), privacy: .public)), 지금까지 녹음을 저장")
        if !isStallContinuation {
            resumeAfterStall()
            return
        }
        stopAndNotify(because: "녹음기가 멈춰서", advice: "녹음을 다시 시작하세요.", alert: .recorderStalled, recorderStalled: true)
        if recorderStallNotice == nil {
            // 저장 자체가 실패한 경우에도 멈춘 사실은 크게 보인다. 이유는 errorMessage에 있다.
            recorderStallNotice = RecorderHealthMonitor.unsavedNotice
        }
    }

    /// 멈춘 녹음을 저장하고 같은 과목으로 새 파일에 이어 녹음한다.
    /// 저장하지 못했거나 새 녹음을 시작하지 못하면 녹음은 멈춘 채로 크게 알린다.
    private func resumeAfterStall() {
        let subject = liveCurrentSubject()
        let saved: Recording
        do {
            saved = try finishRecording(recorderStalled: true)
        } catch {
            // 저장이 실패했으면 이어 녹음하지 않고 멈춘 사실을 크게 알린다.
            raise(.recorderStalled)
            errorMessage = error.errorDescription
            recorderStallNotice = RecorderHealthMonitor.unsavedNotice
            return
        }
        do {
            try beginRecording(subject: subject, startedAt: now(), isContinuation: true)
        } catch {
            Log.recording.fault("멈춘 녹음 뒤 이어 녹음 시작 실패: \(error.localizedDescription, privacy: .public)")
            raise(.recorderStalled)
            errorMessage = error.errorDescription
            // finishRecording이 남긴 "여기까지 저장했습니다. 다시 시작하세요" 안내를 그대로 둔다.
            return
        }
        recorderStallNotice = nil
        stallResumeNotice = RecorderHealthMonitor.resumedNotice(title: saved.title)
        raise(.recorderResumed)
    }

    /// 입력 크기를 읽어 막대와 무음 경고를 갱신한다. 녹음 중에는 주기적으로 불린다.
    /// 일시정지 중에는 소리가 없는 게 정상이므로 경고하지 않고 세던 시간도 지운다.
    public func sampleInputLevel() {
        guard case .recording = state else {
            inputLevel = 0
            isInputSilent = false
            silenceDetector.reset()
            return
        }
        inputLevel = recorder.inputLevel
        isInputSilent = silenceDetector.update(level: inputLevel, at: now())
        if isInputSilent { raise(.inputSilent) }
    }

    /// "마이크 확인"을 누르면 불린다. `previewDuration`초 동안 마이크 소리 크기를 보여 주고 스스로 끝난다.
    /// 녹음 중이면 아무 일도 하지 않는다. 아직 권한을 묻지 않았으면 이때 묻고, 거부돼 있으면 켜지 않는다
    /// (화면이 기존 권한 안내를 보인다). 켜지 못해도 녹음에는 영향이 없다.
    public func startPreview() async {
        guard let levelPreview, !isRecording, !isPreviewing else { return }
        permissionStatus = await permission.requestIfNeeded()
        guard permissionStatus == .granted, !isRecording, !isPreviewing else { return }
        do {
            try levelPreview.start()
        } catch {
            Log.recording.error("마이크 확인 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "마이크 소리를 확인하지 못했습니다. 입력 장치를 확인해 주세요."
            return
        }
        isPreviewing = true
        previewOutcome = nil
        previewPeak = 0
        previewStartedAt = now()
        guard let interval = levelCheckInterval else { return }
        previewMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.samplePreviewLevel()
            }
        }
    }

    /// 확인을 바로 끝낸다. 결과는 남기지 않는다.
    public func stopPreview() {
        endPreview()
        previewOutcome = nil
    }

    private func endPreview() {
        previewMonitor?.cancel()
        previewMonitor = nil
        levelPreview?.stop()
        isPreviewing = false
        previewLevel = 0
        previewStartedAt = nil
    }

    /// 확인 중 입력 크기를 읽어 막대를 갱신하고, `previewDuration`초가 지나면 끝내며 결과를 정한다.
    /// 확인하는 동안 한 번이라도 무음 기준을 넘는 소리가 있었으면 `.heard`, 아니면 `.quiet`.
    public func samplePreviewLevel() {
        guard isPreviewing, let levelPreview, let startedAt = previewStartedAt else { return }
        previewLevel = levelPreview.level
        previewPeak = max(previewPeak, previewLevel)
        guard now().timeIntervalSince(startedAt) >= Self.previewDuration else { return }
        previewOutcome = previewPeak >= InputLevel.silenceThreshold ? .heard : .quiet
        endPreview()
    }

    private func raise(_ alert: RecordingAlert, body: String? = nil) {
        alertRaiser.raise(alert, body: body)
    }

    /// 녹음 중인 수업이 끝난 지 10분이 지났을 때 화면에 보일 안내. 아직이거나 수업을 모르면 nil.
    public var overrunNotice: String? {
        guard isRecording, nextClassSubject == nil else { return nil }
        return ClassOverrunAdvice.notice(subjectName: currentSubjectName, classEnd: classEnd, now: now())
    }

    /// 일시정지가 10분 넘게 이어질 때 화면에 보일 안내. 일시정지 중이 아니거나 아직이면 nil.
    public var pausedNotice: String? {
        guard isPaused else { return nil }
        return PausedAdvice.notice(pausedAt: pausedAt, now: now())
    }

    /// 안내할 때가 되면 시스템 알림도 일시정지마다 한 번 보낸다. 주기적으로 불린다.
    public func checkPaused() {
        guard let notice = pausedNotice else { return }
        Log.recording.notice("일시정지가 오래 이어짐")
        raise(.pausedTooLong, body: notice)
    }

    /// 안내할 때가 되면 시스템 알림도 한 번 보낸다 (다른 앱을 보고 있어도 알 수 있게). 주기적으로 불린다.
    public func checkOverrun() {
        guard let notice = overrunNotice, !overrunNotified else { return }
        overrunNotified = true
        Log.recording.notice("수업이 끝난 뒤에도 녹음 중: \(notice, privacy: .public)")
        guard let overrunNotifier else { return }
        Task { await overrunNotifier.notify(title: "수업이 끝났습니다", body: notice) }
    }

    /// 녹음 중인 수업이 끝나고 다른 과목의 수업이 시작됐으면 그 과목. 아니면 nil.
    /// 시간표에서 시작한 녹음(수업 종료 시각을 아는 녹음)만 본다. 과목을 직접 골랐거나 미분류인 녹음은 건드리지 않는다.
    private var nextClassSubject: Subject? {
        guard isRecording, let classEnd, let currentID = currentSubjectID, let scheduleSnapshot,
              let id = scheduleSnapshot.nextClassStarted(
                replacing: currentID, classEnd: classEnd, now: now(), calendar: calendar)
        else { return nil }
        return subjectsByID[id]
    }

    /// "○○ 수업이 시작됐습니다"와 "정지하고 ○○ 녹음 시작" 버튼에 쓸 안내. 해당하지 않으면 nil.
    public var nextClassNotice: NextClassNotice? {
        nextClassSubject.map { NextClassNotice(subjectName: $0.name) }
    }

    /// 다음 수업이 시작됐으면 시스템 알림도 한 번 보낸다 (과목마다 한 번). 주기적으로 불린다.
    public func checkNextClass() {
        guard let next = nextClassSubject, nextClassNotifiedID != next.persistentModelID else { return }
        nextClassNotifiedID = next.persistentModelID
        let notice = NextClassNotice(subjectName: next.name)
        Log.recording.notice("녹음 중 다음 수업 시작: \(next.name, privacy: .public)")
        guard let overrunNotifier else { return }
        Task { await overrunNotifier.notify(title: notice.notificationTitle, body: notice.notificationBody, identifier: "class-next") }
    }

    /// 지금 녹음을 정상 저장하고 다음 수업 과목으로 새 녹음을 바로 시작한다.
    /// 정지에 실패하면 녹음을 그대로 이어 간다. 새 녹음을 시작하지 못하면 앞 녹음은 저장된 채로 오류를 알린다.
    public func switchToNextClass() async {
        guard let next = nextClassSubject else { return }
        do {
            try stop()
        } catch {
            errorMessage = error.errorDescription
            return
        }
        subjectChoice = .subject(next.persistentModelID)
        do {
            try await start()
            errorMessage = nil
        } catch {
            subjectChoice = .automatic
            errorMessage = error.errorDescription
        }
    }

    private func scheduledEnd(of subject: Subject, startedAt: Date) -> Date? {
        guard let (schedule, _) = loadSchedule() else { return nil }
        return schedule.classEnd(of: subject.persistentModelID, startedAt: startedAt, calendar: calendar)
    }

    /// 녹음을 시작할 때의 마이크와 지금 마이크를 비교해 경고를 갱신한다. 장치가 바뀔 때마다 불린다.
    public func checkInputDevice() {
        guard isRecording else { return }
        inputDeviceWarning = InputDeviceAdvice.warning(started: recordingInputDevice, current: inputMonitor?.currentDevice())
        if inputDeviceWarning != nil { raise(.inputDeviceChanged) }
    }

    private func startLevelMonitor() {
        guard let interval = levelCheckInterval else { return }
        levelMonitor?.cancel()
        levelMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.sampleInputLevel()
            }
        }
    }

    private func stopLevelMonitor() {
        levelMonitor?.cancel()
        levelMonitor = nil
        inputLevel = 0
        isInputSilent = false
        silenceDetector.reset()
    }

    private func startStorageMonitor() {
        guard let interval = storageCheckInterval else { return }
        storageMonitor?.cancel()
        storageMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.checkRecorderHealth()
                self?.checkStorage()
                self?.checkOverrun()
                self?.checkPaused()
                self?.checkNextClass()
            }
        }
    }

    /// 녹음 중 화면에 보일 배터리 경고. 전원이 연결되어 있거나 20% 이상이면 nil.
    /// 화면이 주기적으로 다시 읽으므로 충전기를 꽂거나 뽑으면 바로 바뀐다.
    public var batteryWarning: String? {
        guard isRecording else { return nil }
        return BatteryAdvice.recordingWarning(for: powerStatus?.current())
    }

    /// 녹음 시작 전 화면에 보일 충전 권장. 녹음 중이거나 충전기가 연결되어 있으면 nil.
    public var preRecordingAdvice: String? {
        guard !isRecording else { return nil }
        return BatteryAdvice.preRecordingAdvice(for: powerStatus?.current())
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
        currentSubjectLabel ?? SubjectManager.unclassifiedName
    }

    /// 녹음 중에 과목이 지워졌다면 nil (미분류로 저장된다). 아직 있으면 그 과목.
    private func liveCurrentSubject() -> Subject? {
        guard let id = currentSubjectID else { return nil }
        return availableSubjects().first { $0.persistentModelID == id }
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

        shortRecordingPrompt = nil
        stopPreview()
        let startedAt = now()
        try beginRecording(subject: resolvedSubject(at: startedAt), startedAt: startedAt, isContinuation: false)
    }

    /// 새 파일에 녹음을 시작하고 모니터를 켠다. `isContinuation`이면 멈춘 녹음을 이은 것이라
    /// 사용자가 이미 본 알림·수업 종료 안내는 다시 내보내지 않는다.
    private func beginRecording(subject: Subject?, startedAt: Date, isContinuation: Bool) throws(RecordingError) {
        let relativePath = storage.newRelativePath(subjectName: subject?.name, semester: subject?.semester, startedAt: startedAt, calendar: calendar, fileExtension: RecordingStorage.workingExtension)
        do {
            try storage.prepareFolder(for: relativePath)
            try recorder.start(to: storage.url(for: relativePath))
        } catch {
            Log.recording.error("녹음 시작 실패: \(error.localizedDescription, privacy: .public)")
            throw .startFailed(error.localizedDescription)
        }
        currentSubject = subject
        currentSubjectID = subject?.persistentModelID
        currentSubjectLabel = subject?.name
        subjectChoice = .automatic
        currentRelativePath = relativePath
        bookmarkTimes = []
        bookmarkNotes = []
        state = .recording(startedAt: startedAt)
        pausedAt = nil
        isStallContinuation = isContinuation
        interruptionNotice = nil
        recorderStallNotice = nil
        stallResumeNotice = nil
        healthMonitor.reset()
        if !isContinuation { alertRaiser.reset() }
        storageWarning = nil
        startStorageMonitor()
        silenceDetector.reset()
        startLevelMonitor()
        recordingInputDevice = inputMonitor?.currentDevice()
        inputDeviceWarning = nil
        classEnd = subject.flatMap { scheduledEnd(of: $0, startedAt: startedAt) }
        if !isContinuation {
            overrunNotified = false
            nextClassNotifiedID = nil
        }
        loadNextClassSnapshot()
        sleepPreventer?.begin(reason: "수업 녹음 중")
        onStarted?()
        keepUnsavedLeftover()
        do {
            try journal?.save(pendingRecording(bookmarkTimes: []))
        } catch {
            // 녹음은 계속한다. 복구만 안 될 뿐이다.
            Log.recording.error("녹음 저널 기록 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    public func stop() throws(RecordingError) -> Recording {
        try finishRecording(recorderStalled: false)
    }

    /// 멈춘 녹음을 이어 녹음한 파일의 제목 끝에 붙는다. 같은 수업의 앞 파일과 같은 과목 목록에서 이어져 보인다.
    public static let continuationTitleSuffix = " (이어서)"

    /// 녹음을 닫고 저장한다. 녹음기가 멈춘 경우 `currentTime`이 0으로 돌아갈 수 있으니 실제 파일 크기로 길이를 어림한다.
    private func finishRecording(recorderStalled: Bool) throws(RecordingError) -> Recording {
        guard let startedAt = state.startedAt, let relativePath = currentRelativePath else {
            throw .notRecording
        }
        stallResumeNotice = nil
        var duration = recorder.stop()
        if recorderStalled {
            let bytes = files.fileSize(at: storage.url(for: relativePath)) ?? 0
            duration = max(duration, Double(bytes) * 8 / RecordingRecovery.workingBitsPerSecond)
        }
        sleepPreventer?.end()
        storageMonitor?.cancel()
        storageMonitor = nil
        storageWarning = nil
        stopLevelMonitor()
        recordingInputDevice = nil
        inputDeviceWarning = nil
        classEnd = nil
        scheduleSnapshot = nil
        subjectsByID = [:]
        let subjectName = currentSubjectName
        let recording = Recording(
            title: Self.defaultTitle(subjectName: subjectName, startedAt: startedAt, calendar: calendar) + (isStallContinuation ? Self.continuationTitleSuffix : ""),
            subject: liveCurrentSubject(),
            startedAt: startedAt,
            duration: duration,
            relativePath: relativePath
        )
        if recorderStalled {
            recorderStallNotice = RecorderHealthMonitor.savedNotice(title: recording.title)
        }
        state = .idle
        pausedAt = nil
        currentSubject = nil
        currentSubjectID = nil
        currentSubjectLabel = nil
        currentRelativePath = nil

        context.insert(recording)
        let createdAt = now()
        for (index, time) in bookmarkTimes.enumerated() {
            let note = bookmarkNotes.indices.contains(index) ? bookmarkNotes[index] : ""
            context.insert(Bookmark(time: min(time, duration), note: note, createdAt: createdAt, recording: recording))
        }
        bookmarkTimes = []
        bookmarkNotes = []
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
        bookmarkNotes.append("")
        saveBookmarksToJournal()
    }

    /// `index`번째 북마크에 짧은 메모를 붙인다. 공백뿐인 메모나 없는 번호는 무시한다.
    public func setBookmarkNote(_ note: String, at index: Int) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, bookmarkNotes.indices.contains(index) else { return }
        bookmarkNotes[index] = trimmed
        saveBookmarksToJournal()
    }

    /// 앱이 꺼져도 북마크 시점과 메모를 되살릴 수 있게 저널에 함께 남긴다. 실패해도 녹음은 계속한다.
    private func saveBookmarksToJournal() {
        do {
            try journal?.save(pendingRecording(bookmarkTimes: bookmarkTimes))
        } catch {
            Log.recording.error("북마크 저널 기록 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 저널에 다른 녹음의 기록이 남아 있으면(정지 때 DB 저장이 실패한 경우) 새 녹음이 덮어쓰기 전에 따로 보관한다.
    /// 그래야 앱을 다시 켤 때 앞 녹음도 복구된다. 보관에 실패해도 새 녹음은 시작한다(파일은 남아 있어 "폴더 다시 읽기"로 되살릴 수 있다).
    private func keepUnsavedLeftover() {
        guard let leftover = journal?.load(), leftover.relativePath != currentRelativePath else { return }
        do {
            try journal?.keepUnsaved(leftover)
            Log.recording.notice("저장되지 못한 앞 녹음의 저널을 보관: \(leftover.relativePath, privacy: .public)")
        } catch {
            Log.recording.error("앞 녹음의 저널을 보관하지 못함: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pendingRecording(bookmarkTimes: [TimeInterval]) -> PendingRecording {
        PendingRecording(
            relativePath: currentRelativePath ?? "",
            subjectName: currentSubjectLabel,
            startedAt: state.startedAt ?? now(),
            bookmarkTimes: bookmarkTimes,
            bookmarkNotes: bookmarkNotes
        )
    }

    /// 녹음을 잠시 멈춘다. 이미 멈춘 상태면 아무 일도 하지 않는다.
    public func pause() throws(RecordingError) {
        switch state {
        case .idle: throw .notRecording
        case .paused: return
        case .recording(let startedAt):
            recorder.pause()
            state = .paused(startedAt: startedAt)
            pausedAt = now()
            alertRaiser.rearm(.pausedTooLong)
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
        pausedAt = nil
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
                let saved = try stop()
                if saved.duration < Self.shortRecordingSeconds {
                    shortRecordingPrompt = saved
                }
            } else {
                try await start()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.errorDescription
        }
    }

    /// 너무 짧은 녹음을 그대로 둔다.
    public func keepShortRecording() {
        shortRecordingPrompt = nil
    }

    /// 너무 짧은 녹음을 파일과 DB 기록 모두 지운다. 압축이 끝난 뒤에 지워야 파일이 남지 않는다.
    /// 지우지 못하면 녹음은 그대로 두고 `errorMessage`에 이유를 남긴다.
    public func discardShortRecording() {
        guard let recording = shortRecordingPrompt else { return }
        shortRecordingPrompt = nil
        let previous = compressionTask
        discardTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try RecordingManager(context: context, storage: storage).delete(recording)
                if lastSaved === recording { lastSaved = nil }
            } catch {
                Log.recording.error("짧은 녹음 삭제 실패: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 진행 중인 버리기가 끝날 때까지 기다린다. 주로 테스트에서 쓴다.
    public func waitForDiscard() async {
        await discardTask?.value
    }

    /// "자료구조 3월 2일 10:00"
    nonisolated public static func defaultTitle(subjectName: String, startedAt: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: startedAt)
        let time = (try? TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0))?.description ?? ""
        return "\(subjectName) \(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }

    /// 지금 녹음을 시작하면 분류될 과목. 시간표를 읽을 때마다 새로 계산하므로 시간표를 바꾸면 바로 반영된다.
    /// 수업이 없으면 nil (미분류).
    public func expectedSubject() -> Subject? {
        resolvedSubject(at: now())
    }

    /// 고를 수 있는 과목 (이름순). 조회에 실패하면 빈 목록.
    public func availableSubjects() -> [Subject] {
        do {
            return try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)]))
        } catch {
            Log.data.error("과목 조회 실패: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 직접 고른 과목이 있으면 그것을, 없으면(또는 그 사이 지워졌으면) 시간표로 정한 과목을 쓴다.
    private func resolvedSubject(at date: Date) -> Subject? {
        switch subjectChoice {
        case .automatic: return subject(at: date)
        case .unclassified: return nil
        case .subject(let id): return availableSubjects().first { $0.persistentModelID == id } ?? subject(at: date)
        }
    }

    /// 대기 화면에 보일 "지금 녹음하면 분류될 과목" 이름. 수업이 없으면 "미분류".
    public var expectedSubjectName: String {
        expectedSubject()?.name ?? SubjectManager.unclassifiedName
    }

    private func loadNextClassSnapshot() {
        guard classEnd != nil, let (schedule, slots) = loadSchedule() else {
            scheduleSnapshot = nil
            subjectsByID = [:]
            return
        }
        scheduleSnapshot = schedule
        subjectsByID = Dictionary(
            slots.compactMap { slot in slot.subject.map { ($0.persistentModelID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func loadSchedule() -> (ClassSchedule<PersistentIdentifier>, [TimeSlot])? {
        do {
            let slots = try context.fetch(FetchDescriptor<TimeSlot>())
            let schedule = ClassSchedule(entries: slots.compactMap { slot -> ClassSchedule<PersistentIdentifier>.Entry? in
                guard let period = slot.period, let subject = slot.subject else { return nil }
                return .init(period: period, subjectID: subject.persistentModelID)
            })
            return (schedule, slots)
        } catch {
            Log.data.error("시간표 조회 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func subject(at date: Date) -> Subject? {
        guard let (schedule, slots) = loadSchedule() else { return nil }
        guard case .subject(let id) = schedule.classify(at: date, calendar: calendar) else { return nil }
        return slots.first { $0.subject?.persistentModelID == id }?.subject
    }
}

extension RecordingController: ReminderRecordingStarting {
    /// 수업 시작 알림의 "녹음 시작" 버튼. 알림에 적힌 과목으로 녹음을 시작한다.
    /// 이미 녹음 중이면 건드리지 않는다. 시작하지 못하면 이유를 `errorMessage`에 남겨 녹음 화면에서 보이게 한다.
    public func startRecording(forSubjectNamed subjectName: String) async -> ReminderStartOutcome {
        guard !isRecording else {
            Log.recording.notice("이미 녹음 중이라 알림의 녹음 시작을 무시")
            return .alreadyRecording
        }
        guard let subject = availableSubjects().first(where: { $0.name == subjectName }) else {
            Log.recording.notice("알림에 적힌 과목이 없어 녹음을 시작하지 않음")
            errorMessage = "알림에 적힌 과목을 찾을 수 없어 녹음을 시작하지 못했습니다. 녹음 화면에서 직접 시작해 주세요."
            return .subjectMissing
        }
        subjectChoice = .subject(subject.persistentModelID)
        do {
            try await start()
            errorMessage = nil
            return .started
        } catch {
            subjectChoice = .automatic
            errorMessage = error.errorDescription
            return .failed
        }
    }
}
#endif
