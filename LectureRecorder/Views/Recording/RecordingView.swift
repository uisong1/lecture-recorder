import LectureCore
import AppKit
import SwiftData
import SwiftUI

/// 녹음 버튼 하나로 시작·정지하는 화면. 대기 / 녹음 중 / 정지 직후 세 구역으로 나뉜다.
struct RecordingView: View {
    let recording: RecordingController
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary
    /// 과목이 하나도 없을 때 보이는 첫 안내.
    let showsFirstRunGuide: Bool

    /// 마이크 권한이 꺼져 있으면 시작 버튼 대신 안내가 나오므로 하단 고정 버튼도 숨긴다.
    private var showsRecordButton: Bool {
        recording.isRecording || !recording.isPermissionDenied
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: 460)
                    .padding(Design.Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
            if playback.current != nil && !playback.isPanelHidden { PlaybackPanel(playback: playback, manager: manager, library: library) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designCanvas(Design.Palette.parchment)
        .onDisappear { recording.stopPreview() }
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

    private var content: some View {
        VStack(spacing: Design.Spacing.md) {
            header
                .designCard(padding: Design.Spacing.xl)

            if recording.isRecording, let device = recording.inputDeviceName {
                Label("마이크: \(device)", systemImage: "mic")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("inputDevice")
            }

            if let notice = recording.pausedNotice {
                Label(notice, systemImage: "pause.circle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.primary)
                    .accessibilityIdentifier("pausedNotice")
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

            VStack(spacing: Design.Spacing.sm) {
                if recording.isRecording {
                    RecordingActiveSection(recording: recording)
                } else {
                    RecordingIdleSection(recording: recording, playback: playback, manager: manager, library: library, showsFirstRunGuide: showsFirstRunGuide)
                }
            }
            .designCard(padding: Design.Spacing.md, radius: Design.Radius.group)

            if let message = recording.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("recordingError")
            }

            if let saved = recording.lastSaved, !recording.isRecording {
                SavedRecordingSection(recording: recording, playback: playback, manager: manager, library: library, saved: saved)
                    .id(saved.persistentModelID)
                    .designCard(padding: Design.Spacing.md, radius: Design.Radius.group)
            }
        }
    }

    /// 시안 01: 위 카드에 지금 과목, 타이머, 시작·정지 버튼을 함께 둔다.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: Design.Spacing.xs) {
                if recording.isRecording {
                    RecordingIndicator(isPaused: recording.isPaused)
                } else {
                    Text("지금 녹음하면")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                        .accessibilityIdentifier("expectedSubject")
                }
                Text(recording.isRecording ? recording.currentSubjectName + (recording.isPaused ? " (일시정지)" : "") : recording.expectedSubjectName)
                    .designText(.displayLg)
                    .foregroundStyle(Design.Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recordingSubject")
                Text(recording.elapsedText)
                    .designText(.hero)
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.ink)
                    .padding(.vertical, Design.Spacing.xs)
                    .accessibilityIdentifier("elapsedTime")
                if !recording.isRecording {
                    Text(recording.isPermissionDenied ? "마이크 권한이 필요해요" : "준비됐어요")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                if showsRecordButton {
                    RecordButton(recording: recording, isWide: true)
                        .padding(.top, Design.Spacing.sm)
                }
            }
        }
    }
}

/// 녹음 시작·정지 버튼. 대기와 녹음 중 구역이 함께 쓴다.
struct RecordButton: View {
    let recording: RecordingController
    /// 카드 폭을 꽉 채우는 큰 버튼 (시안 01).
    var isWide = false

    var body: some View {
        Button {
            Task { await recording.toggle() }
        } label: {
            Label(recording.isRecording ? "녹음 정지" : "녹음 시작", systemImage: recording.isRecording ? "stop.fill" : "mic.fill")
                .frame(maxWidth: isWide ? .infinity : nil)
        }
        .buttonStyle(.pill)
        .keyboardShortcut("r", modifiers: .command)
        .help(recording.isRecording ? "녹음 정지 (⌘R)" : "녹음 시작 (⌘R)")
        .accessibilityLabel(recording.isRecording ? "녹음 정지" : "녹음 시작")
        .accessibilityIdentifier("recordButton")
    }
}

/// 경고(danger 색)와, 경고가 없을 때만 보이는 고정 안내 한 줄. 우선순위는 `RecordingScreenNotices`가 정한다.
struct RecordingNoticeLines: View {
    let notices: RecordingScreenNotices

    var body: some View {
        ForEach(notices.warnings, id: \.kind) { warning in
            switch warning.kind {
            case .stallResume:
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .designText(.bodyStrong)
                    .foregroundStyle(Design.Palette.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("stallResumeNotice")
            case .storage:
                line(warning.message, icon: "externaldrive.badge.exclamationmark", id: "storageWarning")
            case .battery:
                line(warning.message, icon: "battery.25percent", id: "batteryWarning")
            case .inputDevice:
                line(warning.message, icon: "exclamationmark.triangle", id: "inputDeviceWarning")
            case .silence:
                line(warning.message, icon: "mic.slash", id: "silenceWarning")
            }
        }
        if let standing = notices.standingNotice {
            Text(standing)
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .accessibilityIdentifier("standingNotice")
        }
    }

    private func line(_ message: String, icon: String, id: String) -> some View {
        Label(message, systemImage: icon)
            .designText(.caption)
            .foregroundStyle(Design.Palette.danger)
            .accessibilityIdentifier(id)
    }
}

/// 입력 크기를 가로 막대로 보여준다.
struct InputLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Design.Palette.fill)
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

/// 녹음 중임을 알리는 표시. 버튼은 검정이고 이 표시만 빨강이다 (DECISIONS.md 2026-11-28).
private struct RecordingIndicator: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            Circle()
                .fill(isPaused ? Design.Palette.inkMuted : Design.Palette.recording)
                .frame(width: 10, height: 10)
            Text(isPaused ? "일시정지 중" : "녹음 중")
                .designText(.captionStrong)
                .foregroundStyle(isPaused ? Design.Palette.inkMuted : Design.Palette.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recordingIndicator")
    }
}
