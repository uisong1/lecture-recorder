import LectureCore
import AppKit
import SwiftUI

/// 녹음 버튼 하나로 시작·정지하는 화면.
struct RecordingView: View {
    let recording: RecordingController
    let playback: PlaybackController

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: 6) {
                    Text(recording.isRecording ? recording.currentSubjectName + (recording.isPaused ? " (일시정지)" : "") : "녹음 대기")
                        .font(.title2.bold())
                        .accessibilityIdentifier("recordingSubject")
                    Text(recording.elapsedText)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("elapsedTime")
                }
            }

            if recording.isPermissionDenied && !recording.isRecording {
                VStack(spacing: 8) {
                    Label("마이크 권한이 꺼져 있어 녹음할 수 없습니다.", systemImage: "mic.slash")
                        .font(.headline)
                        .accessibilityIdentifier("microphoneDenied")
                    Text("시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 LectureRecorder를 켜 주세요.")
                        .foregroundStyle(.secondary)
                    Button("시스템 설정 열기") {
                        if let url = Self.microphoneSettingsURL { NSWorkspace.shared.open(url) }
                    }
                    .accessibilityIdentifier("openSystemSettings")
                }
            } else {
            Button {
                Task { await recording.toggle() }
            } label: {
                Image(systemName: recording.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
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
                .keyboardShortcut("p", modifiers: .command)
                .accessibilityIdentifier("pauseButton")
            }

            if let message = recording.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("recordingError")
            }

            if let saved = recording.lastSaved, !recording.isRecording {
                HStack {
                    Text("저장됨: \(saved.title)")
                        .accessibilityIdentifier("lastSavedTitle")
                    Button(playback.current === saved && playback.isPlaying ? "일시정지" : "듣기") {
                        playback.select(saved)
                        playback.togglePlayPause()
                    }
                    .accessibilityIdentifier("playLastSaved")
                }
                .foregroundStyle(.secondary)
                if let message = playback.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recording.refreshPermission()
        }
    }

    private static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
}
