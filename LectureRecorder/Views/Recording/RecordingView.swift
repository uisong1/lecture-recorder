import LectureCore
import AppKit
import SwiftUI

/// 녹음 버튼 하나로 시작·정지하는 화면.
struct RecordingView: View {
    let recording: RecordingController
    let playback: PlaybackController

    var body: some View {
        VStack(spacing: Design.Spacing.lg) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: Design.Spacing.xs) {
                    Text(recording.isRecording ? recording.currentSubjectName + (recording.isPaused ? " (일시정지)" : "") : "녹음 대기")
                        .designText(.tagline)
                        .foregroundStyle(Design.Palette.ink)
                        .accessibilityIdentifier("recordingSubject")
                    if !recording.isRecording {
                        Text("지금 녹음하면: \(recording.expectedSubjectName)")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                            .accessibilityIdentifier("expectedSubject")
                    }
                    Text(recording.elapsedText)
                        .font(.system(size: 56, weight: .semibold))
                        .tracking(-0.28)
                        .monospacedDigit()
                        .foregroundStyle(Design.Palette.ink)
                        .accessibilityIdentifier("elapsedTime")
                }
            }

            if recording.isRecording {
                InputLevelBar(level: recording.inputLevel)
                    .accessibilityIdentifier("inputLevel")
                if recording.isInputSilent {
                    Label("소리가 거의 들어오지 않습니다", systemImage: "mic.slash")
                        .designText(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("silenceWarning")
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
            .buttonStyle(PillButtonStyle(kind: recording.isRecording ? .dark : .primary))
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
                Text(BatteryAdvice.lidNotice)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("lidNotice")
                if let warning = recording.batteryWarning {
                    Label(warning, systemImage: "battery.25percent")
                        .designText(.caption)
                        .foregroundStyle(.red)
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
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("recordingError")
            }

            if let warning = recording.storageWarning, recording.isRecording {
                Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                    .designText(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("storageWarning")
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
                }
                .foregroundStyle(Design.Palette.inkMuted)
                if let message = playback.errorMessage {
                    Text(message).designText(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(Design.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designCanvas(Design.Palette.parchment)
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
