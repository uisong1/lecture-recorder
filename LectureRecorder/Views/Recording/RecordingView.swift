import LectureCore
import AppKit
import SwiftData
import SwiftUI

/// 녹음 버튼 하나로 시작·정지하는 화면.
struct RecordingView: View {
    let recording: RecordingController
    let playback: PlaybackController
    let manager: RecordingManager
    /// 과목이 하나도 없을 때 보이는 첫 안내.
    let showsFirstRunGuide: Bool

    @State private var isEditingSaved = false
    @State private var titleDraft = ""

    var body: some View {
        VStack(spacing: Design.Spacing.lg) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: Design.Spacing.xs) {
                    Text(recording.isRecording ? recording.currentSubjectName + (recording.isPaused ? " (일시정지)" : "") : "녹음 대기")
                        .designText(.tagline)
                        .foregroundStyle(Design.Palette.ink)
                        .accessibilityIdentifier("recordingSubject")
                    if recording.isRecording {
                        RecordingIndicator(isPaused: recording.isPaused)
                    } else {
                        Text("지금 녹음하면: \(recording.expectedSubjectName)")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                            .accessibilityIdentifier("expectedSubject")
                        Picker("과목", selection: Bindable(recording).subjectChoice) {
                            Text("자동 (시간표)").tag(SubjectChoice.automatic)
                            ForEach(recording.availableSubjects()) { subject in
                                Text(subject.name).tag(SubjectChoice.subject(subject.persistentModelID))
                            }
                            Text("미분류").tag(SubjectChoice.unclassified)
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("subjectChoice")
                    }
                    Text(recording.elapsedText)
                        .designText(.hero)
                        .monospacedDigit()
                        .foregroundStyle(Design.Palette.ink)
                        .accessibilityIdentifier("elapsedTime")
                }
            }

            if let device = recording.inputDeviceName {
                Label("마이크: \(device)", systemImage: "mic")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("inputDevice")
            }

            if let notice = recording.overrunNotice {
                Label(notice, systemImage: "clock.badge.exclamationmark")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.primary)
                    .accessibilityIdentifier("classOverrunNotice")
            }

            if let next = recording.nextClassNotice {
                VStack(spacing: Design.Spacing.sm) {
                    Label(next.message, systemImage: "bell")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.primary)
                        .accessibilityIdentifier("nextClassNotice")
                    Button(next.buttonTitle) {
                        Task { await recording.switchToNextClass() }
                    }
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("switchToNextClass")
                }
            }

            if let warning = recording.inputDeviceWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("inputDeviceWarning")
            }

            if recording.isRecording {
                InputLevelBar(level: recording.inputLevel)
                    .accessibilityIdentifier("inputLevel")
                if recording.isInputSilent {
                    Label("소리가 거의 들어오지 않습니다", systemImage: "mic.slash")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("silenceWarning")
                }
            }

            if showsFirstRunGuide && !recording.isRecording {
                VStack(spacing: Design.Spacing.sm) {
                    Text(SubjectManager.firstRunGuideText)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                        .accessibilityIdentifier("firstRunGuide")
                    SettingsLink {
                        Text("과목과 시간표 설정 열기")
                    }
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("firstRunOpenSettings")
                }
            }

            if let advice = recording.preRecordingAdvice {
                Label(advice, systemImage: "battery.100percent.bolt")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("chargeAdvice")
            }

            if recording.isPermissionDenied && !recording.isRecording {
                VStack(spacing: Design.Spacing.xs) {
                    Label("마이크 권한이 꺼져 있어 녹음할 수 없습니다.", systemImage: "mic.slash")
                        .designText(.bodyStrong)
                        .accessibilityIdentifier("microphoneDenied")
                    Text("시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 LectureRecorder를 켜 주세요.")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                    Button("시스템 설정 열기") {
                        if let url = Self.microphoneSettingsURL { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("openSystemSettings")
                }
            } else {
            Button {
                Task { await recording.toggle() }
            } label: {
                Label(recording.isRecording ? "녹음 정지" : "녹음 시작", systemImage: recording.isRecording ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.pill)
            .keyboardShortcut("r", modifiers: .command)
            .help(recording.isRecording ? "녹음 정지 (⌘R)" : "녹음 시작 (⌘R)")
            .accessibilityLabel(recording.isRecording ? "녹음 정지" : "녹음 시작")
            .accessibilityIdentifier("recordButton")
            }

            if recording.isRecording {
                Button {
                    recording.togglePause()
                } label: {
                    Label(recording.isPaused ? "재개" : "일시정지", systemImage: recording.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.pillSecondary)
                .keyboardShortcut("p", modifiers: .command)
                .accessibilityIdentifier("pauseButton")

                Button {
                    recording.addBookmark()
                } label: {
                    Label("북마크 \(recording.bookmarkTimes.count)", systemImage: "bookmark")
                }
                .buttonStyle(.pillSecondary)
                .keyboardShortcut("b", modifiers: .command)
                .help("중요한 구간 표시 (⌘B)")
                .accessibilityIdentifier("bookmarkButton")
            }

            if recording.isRecording {
                BookmarkNoteField(recording: recording)
            }

            if recording.isRecording {
                Text(BatteryAdvice.lidNotice)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("lidNotice")
                if let warning = recording.batteryWarning {
                    Label(warning, systemImage: "battery.25percent")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .accessibilityIdentifier("batteryWarning")
                }
                Text("창을 닫아도 녹음은 계속됩니다. Dock 아이콘을 누르면 창이 다시 열립니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("windowCloseHint")
            }

            if let message = recording.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("recordingError")
            }

            if let warning = recording.storageWarning, recording.isRecording {
                Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("storageWarning")
            }

            if let notice = recording.recorderStallNotice, !recording.isRecording {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .designText(.bodyStrong)
                    .foregroundStyle(Design.Palette.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recorderStallNotice")
            }

            if let notice = recording.interruptionNotice, !recording.isRecording {
                Label(notice, systemImage: "moon.zzz")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("interruptionNotice")
            }

            if let saved = recording.lastSaved, !recording.isRecording {
                HStack(spacing: Design.Spacing.sm) {
                    Text("저장됨: \(saved.title)")
                        .designText(.caption)
                        .accessibilityIdentifier("lastSavedTitle")
                    Button(playback.current === saved && playback.isPlaying ? "일시정지" : "듣기") {
                        playback.select(saved)
                        playback.togglePlayPause()
                    }
                    .buttonStyle(.textLink)
                    .accessibilityIdentifier("playLastSaved")
                    Button(isEditingSaved ? "완료" : "제목·과목 수정") {
                        if isEditingSaved {
                            if titleDraft != saved.title { try? manager.rename(saved, to: titleDraft) }
                        } else {
                            titleDraft = saved.title
                        }
                        isEditingSaved.toggle()
                    }
                    .buttonStyle(.textLink)
                    .accessibilityIdentifier("editLastSaved")
                }
                .foregroundStyle(Design.Palette.inkMuted)
                if isEditingSaved {
                    HStack(spacing: Design.Spacing.sm) {
                        TextField("제목", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .onSubmit { try? manager.rename(saved, to: titleDraft) }
                            .accessibilityIdentifier("lastSavedTitleField")
                        Menu("과목: \(saved.subject?.name ?? SubjectManager.unclassifiedName)") {
                            ForEach(recording.availableSubjects()) { subject in
                                Button(subject.name) { try? manager.move(saved, to: subject) }
                            }
                            Button(SubjectManager.unclassifiedName) { try? manager.move(saved, to: nil) }
                        }
                        .fixedSize()
                        .accessibilityIdentifier("lastSavedSubjectMenu")
                    }
                }
                if let message = manager.errorMessage {
                    Text(message).designText(.caption).foregroundStyle(Design.Palette.danger)
                }
                if let message = playback.errorMessage {
                    Text(message).designText(.caption).foregroundStyle(Design.Palette.danger)
                }
            }
        }
        .padding(Design.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designCanvas(Design.Palette.parchment)
        .onChange(of: recording.lastSaved) { isEditingSaved = false }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.current != nil { PlaybackBar(playback: playback) }
        }
        .alert(
            "너무 짧은 녹음입니다",
            isPresented: Binding(get: { recording.shortRecordingPrompt != nil }, set: { _ in })
        ) {
            Button("저장", role: .cancel) { recording.keepShortRecording() }
                .accessibilityIdentifier("keepShortRecording")
            Button("버리기", role: .destructive) { recording.discardShortRecording() }
                .accessibilityIdentifier("discardShortRecording")
        } message: {
            Text("\(Int(RecordingController.shortRecordingSeconds))초가 안 되는 녹음입니다. 저장할까요?")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recording.refreshPermission()
        }
    }

    private static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
}

/// 입력 크기를 가로 막대로 보여준다.
private struct InputLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Design.Palette.inkMuted.opacity(0.2))
                Capsule()
                    .fill(Design.Palette.primary)
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(width: 200, height: 6)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// 녹음 중임을 알리는 표시. 버튼은 파랑이고 이 표시만 빨강이다 (DECISIONS.md).
private struct RecordingIndicator: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            Circle()
                .fill(isPaused ? Design.Palette.inkMuted : Design.Palette.danger)
                .frame(width: 10, height: 10)
            Text(isPaused ? "일시정지 중" : "녹음 중")
                .designText(.captionStrong)
                .foregroundStyle(isPaused ? Design.Palette.inkMuted : Design.Palette.danger)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recordingIndicator")
    }
}
