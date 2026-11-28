import LectureCore
import SwiftUI

struct SettingsView: View {
    let subjects: SubjectManager
    let schedule: ScheduleManager
    let reminders: ClassReminderController
    let rescan: RecordingRescanModel
    let recording: RecordingController
    let launchAtLogin: LaunchAtLoginModel
    let appUpdate: AppUpdateModel
    let playback: PlaybackController
    let storeBackup: StoreBackup?
    let storage: RecordingStorage
    let canvasToken: CanvasTokenModel
    let lectureMaterials: LectureMaterialsModel
    let transcription: TranscriptionCenter
    let storageHealth: StorageHealth

    @AppStorage(SettingsTab.defaultsKey) private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(launchAtLogin: launchAtLogin, appUpdate: appUpdate, isRecording: recording.isRecording, playback: playback)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SubjectSettingsView(manager: subjects)
                .tabItem { Label("과목", systemImage: "books.vertical") }
                .tag("subjects")
            ScheduleSettingsView(subjects: subjects, manager: schedule)
                .tabItem { Label("시간표", systemImage: "calendar") }
                .tag("schedule")
            TranscriptionSettingsView(center: transcription)
                .tabItem { Label("전사", systemImage: "doc.text") }
                .tag("transcription")
            NotificationSettingsView(reminders: reminders)
                .tabItem { Label("알림", systemImage: "bell") }
                .tag("notifications")
            RecordingFilesSettingsView(model: rescan, isRecording: recording.isRecording, storeBackup: storeBackup, storage: storage, health: storageHealth)
                .tabItem { Label("녹음 파일", systemImage: "folder") }
                .tag(SettingsTab.recordingFiles)
            CanvasSettingsView(model: canvasToken, materials: lectureMaterials, storage: storage)
                .tabItem { Label("LMS", systemImage: "graduationcap") }
                .tag("lms")
        }
        .frame(width: 560, height: 560)
        // 다른 화면에서 "녹음 파일" 탭으로 열었더라도 다음에는 평소처럼 첫 탭으로 연다.
        .onDisappear { selectedTab = SettingsTab.general }
    }
}

/// 설정 창의 탭 이름. 다른 화면에서 특정 탭을 열 때 이 값을 저장한 뒤 설정 창을 연다.
enum SettingsTab {
    static let defaultsKey = "settingsSelectedTab"
    static let general = "general"
    static let recordingFiles = "recordingFiles"
}

/// 설정 창을 "녹음 파일" 탭으로 여는 버튼 (저장 상태 알림의 "자세히", "백업에서 되살리기").
struct OpenRecordingFilesSettingsButton: View {
    let title: String
    var isPrimary = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            UserDefaults.standard.set(SettingsTab.recordingFiles, forKey: SettingsTab.defaultsKey)
            openSettings()
        }
        .buttonStyle(isPrimary ? .pillCompact : .pillSecondaryCompact)
    }
}
