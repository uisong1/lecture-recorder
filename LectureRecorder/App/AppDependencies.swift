import LectureCore
import SwiftData
import SwiftUI

/// 앱 전체에서 함께 쓰는 저장소와 뷰모델을 한곳에서 만든다.
@MainActor
final class AppDependencies {
    /// UI 테스트에서는 디스크에 남기지 않고, 마이크 대신 시뮬레이션 녹음기를 쓴다.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")

    let container: ModelContainer
    /// 저장소나 녹음 폴더를 열지 못해 임시로 대신 실행 중이면 그 이유.
    let startupError: String?
    /// 앱이 녹음 중에 꺼졌다가 되살린 녹음이 있으면 그 안내.
    let recoveryNotice: String?
    let subjects: SubjectManager
    let schedule: ScheduleManager
    let reminders: ClassReminderController
    let recording: RecordingController
    let playback: PlaybackController
    let mediaKeys: MediaKeyController
    let library: RecordingLibrary
    let manager: RecordingManager
    let timetableImport: TimetableImportModel
    let rescan: RecordingRescanModel
    let launchAtLogin: LaunchAtLoginModel
    /// 저장소 백업. 설정에서 백업 폴더 위치와 마지막 백업 시각을 보여 준다. UI 테스트에서는 nil.
    let storeBackup: StoreBackup?
    /// 녹음 폴더. 설정에서 위치를 보여 주고 열어 준다.
    let storage: RecordingStorage

    /// 알림 버튼으로 녹음을 시작하지 못했을 때 창을 보여 준다. Dock 아이콘을 누른 것과 같아서, 창이 닫혀 있어도 다시 열린다.
    private static func bringAppToFront() {
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.recording.error("앱을 앞으로 가져오지 못함: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    init() {
        var problems: [String] = []
        let storeBackup = Self.makeStoreBackup()
        self.storeBackup = storeBackup
        let container = Self.makeContainer(problems: &problems, backup: storeBackup)
        // UI 테스트에서는 사용자의 실제 휴지통 대신 임시 폴더로 옮긴다.
        let files: any FileStoring = Self.isUITesting
            ? LocalFileStore(trashDirectory: FileManager.default.temporaryDirectory.appending(path: "LectureRecorder/FakeTrash", directoryHint: .isDirectory))
            : LocalFileStore()
        let storage = RecordingStorage(root: Self.makeRecordingsRoot(problems: &problems), files: files)
        self.storage = storage

        let journal: any RecordingJournaling = Self.isUITesting
            ? InMemoryRecordingJournal()
            : FileRecordingJournal(url: storage.root.deletingLastPathComponent().appending(path: "pending-recording.json"))
        self.container = container
        subjects = SubjectManager(context: container.mainContext, storage: storage)
        schedule = ScheduleManager(context: container.mainContext)
        let compressor = Self.isUITesting ? nil : RecordingCompressor(
            context: container.mainContext,
            storage: storage,
            converter: SystemAudioConverter()
        )
        // UI 테스트에서는 시스템 알림 센터를 건드리지 않는다.
        let notifications: any NotificationScheduling = Self.isUITesting ? NoNotificationScheduler() : SystemNotificationScheduler()
        if Self.isUITesting {
            recording = RecordingController(
                context: container.mainContext,
                recorder: SimulatedAudioRecorder(),
                storage: storage,
                permission: GrantedMicrophonePermission(),
                journal: journal
            )
        } else {
            recording = RecordingController(
                context: container.mainContext,
                recorder: SystemAudioRecorder(),
                storage: storage,
                permission: SystemMicrophonePermission(),
                journal: journal,
                sleepPreventer: SystemSleepPreventer(),
                powerStatus: SystemPowerStatus(),
                inputMonitor: SystemAudioInput(),
                levelPreview: SystemAudioLevelPreview(),
                overrunNotifier: notifications,
                lifecycle: SystemLifecycleEvents(),
                compressor: compressor
            )
        }
        let recordingController = recording
        reminders = ClassReminderController(
            context: container.mainContext,
            notifications: notifications,
            recordingStarter: recording,
            bringAppToFront: Self.bringAppToFront,
            isRecording: { recordingController.isRecording }
        )
        let reminders = reminders
        schedule.onChange = { Task { await reminders.reschedule() } }
        subjects.onChange = { Task { await reminders.reschedule() } }
        Task { await reminders.reschedule() }
        // 하루가 바뀌면 오늘 남은 수업 기준으로 "녹음 중이 아닙니다" 알림을 다시 예약한다. 앱을 오래 켜 둬도 날마다 새로 만들어진다.
        let reminderTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await reminders.reschedule() }
        }
        reminderTimer.tolerance = 60  // 시스템이 다른 작업과 묶어 깨울 수 있게 한다
        launchAtLogin = LaunchAtLoginModel(controller: SystemLoginItem())
        library = RecordingLibrary(context: container.mainContext)
        manager = RecordingManager(context: container.mainContext, storage: storage)
        let context = container.mainContext
        let library = library
        let manager = manager
        let recording = recording
        subjects.activePaths = { recording.currentRelativePath.map { [$0] } ?? [] }
        playback = PlaybackController(
            player: SystemAudioPlayer(),
            storage: storage,
            bookmarkManager: BookmarkManager(context: context),
            savePosition: {
                do {
                    try context.save()
                } catch {
                    Log.playback.error("재생 위치 저장 실패: \(error.localizedDescription, privacy: .public)")
                }
            },
            queue: { library.recordings },
            isPlayable: { manager.status(for: $0).isPlayable },
            allowsAdvance: { !recording.isRecording },
            isRecording: { recording.isRecording },
            outputInspector: SystemAudioOutput()
        )
        let remoteCommands = SystemRemoteCommands(skipInterval: playback.skipInterval.seconds)
        playback.onSkipIntervalChange = { [weak remoteCommands] in remoteCommands?.setSkipInterval($0.seconds) }
        let mediaKeys = MediaKeyController(playback: playback, commands: remoteCommands, nowPlaying: remoteCommands)
        self.mediaKeys = mediaKeys
        // 재생 상태를 "지금 재생 중"에 반영한다. 바뀐 것이 없으면 아무것도 올리지 않는다.
        let publishTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { mediaKeys.publish() }
        }
        publishTimer.tolerance = 0.5
        do {
            let recovery = RecordingRecovery(context: container.mainContext, storage: storage, journal: journal)
            recoveryNotice = try recovery.recoverIfNeeded().map {
                "이전에 녹음 중 앱이 꺼져서 '\($0.title)'을 되살렸습니다. 끝부분이 없을 수 있습니다."
            }
        } catch {
            Log.recording.error("녹음 복구 실패: \(error.localizedDescription, privacy: .public)")
            problems.append("꺼진 녹음을 되살리지 못했습니다: \(error.localizedDescription)")
            recoveryNotice = nil
        }
        let migrator = RecordingMigrator(context: container.mainContext, storage: storage)
        // 예전 폴더 구조의 녹음을 학기/과목 폴더로 옮긴다. 복사해 확인한 뒤에만 원본을 지우고, 실패하면 그대로 둔다.
        // 옮기고 남은 빈 예전 폴더는 정리한다. 녹음이 막 시작된 폴더를 지우지 않도록 녹음 중이면 건너뛴다.
        Task {
            if await migrator.migrateIfNeeded().moved > 0, !recording.isRecording { storage.removeEmptyFolders() }
        }
        let subjects = subjects
        let schedule = schedule
        rescan = RecordingRescanModel(
            rescanner: RecordingRescanner(context: context, storage: storage, durations: SystemAudioDurationReader()),
            activePaths: { recording.currentRelativePath.map { [$0] } ?? [] },
            onFinished: { library.reload() }
        )
        timetableImport = TimetableImportModel(
            reader: VisionTimetableReader(),
            importer: TimetableImporter(context: context),
            onImported: {
                // 새 과목·시간표를 화면에 반영하고, 수업 알림을 다시 예약하고, 학기가 정해진 과목의 예전 녹음을 새 폴더로 옮긴다.
                subjects.reload()
                schedule.reload()
                library.reload()
                await reminders.reschedule()
                if await migrator.migrateIfNeeded().moved > 0, !recording.isRecording { storage.removeEmptyFolders() }
                library.reload()
            }
        )
        if let compressor {
            // 지난 실행에서 압축하지 못한 CAF 녹음(꺼졌거나 실패한 것)을 이어서 압축한다.
            Task { await compressor.compressPending() }
        }
        startupError = problems.isEmpty ? nil : problems.joined(separator: "\n")
        // 녹음을 시작하면 재생 중인 소리를 멈춘다.
        let player = playback
        // 녹음을 시작하면 "녹음 중이 아닙니다" 알림을 취소하고, 끝나면 남은 수업 기준으로 다시 예약한다.
        recording.onStarted = {
            player.recordingDidStart()
            Task { await reminders.reschedule() }
        }
        recording.onStopped = { Task { await reminders.reschedule() } }
    }

    private static func makeStoreBackup() -> StoreBackup? {
        guard !isUITesting, let backupsRoot = try? StoreBackup.defaultRoot() else { return nil }
        return StoreBackup(storeURL: LectureModelContainer.defaultStoreURL(), backupsRoot: backupsRoot)
    }

    private static func makeContainer(problems: inout [String], backup: StoreBackup?) -> ModelContainer {
        // 저장소를 열기 전에 하루 한 번 복사해 둔다. 실패해도 앱은 켠다.
        backup?.backupIfNeeded()
        do {
            return try LectureModelContainer.make(inMemory: isUITesting)
        } catch {
            Log.data.fault("저장소 열기 실패: \(error.localizedDescription, privacy: .public)")
        }
        do {
            problems.append(LectureModelContainer.openFailureNotice)
            return try LectureModelContainer.make(inMemory: true)
        } catch {
            // 메모리 저장소조차 만들 수 없으면 앱을 계속할 방법이 없다.
            fatalError("메모리 저장소를 만들 수 없음: \(error)")
        }
    }

    private static func makeRecordingsRoot(problems: inout [String]) -> URL {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "LectureRecorder/Recordings", directoryHint: .isDirectory)
        if isUITesting { return temporary }
        do {
            return try RecordingStorage.defaultRoot()
        } catch {
            Log.storage.fault("녹음 폴더를 열지 못함: \(error.localizedDescription, privacy: .public)")
            problems.append("녹음 폴더를 열지 못해 임시 폴더에 저장합니다.")
            return temporary
        }
    }
}
