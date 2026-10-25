import AppKit
import LectureCore
import SwiftUI

/// 메뉴 막대 아이콘. 녹음 중이면 모양이 바뀐다.
struct MenuBarLabel: View {
    let recording: RecordingController

    var body: some View {
        switch recording.menuBarStatus.icon {
        case .idle: Image(systemName: "mic")
        case .recording: Image(systemName: "record.circle.fill")
        case .paused: Image(systemName: "pause.circle.fill")
        }
    }
}

/// 메뉴 막대 아이콘을 눌렀을 때 뜨는 창. 앱이 뒤에 있어도 시작·정지·북마크를 누를 수 있다.
struct MenuBarContent: View {
    let recording: RecordingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content(for: recording.menuBarStatus)
        }
        .padding(Design.Spacing.md)
        .frame(width: 260)
        .designCanvas()
    }

    private func content(for status: MenuBarStatus) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.xs) {
                if status.isRecording {
                    Circle()
                        .fill(status.isPaused ? Design.Palette.inkMuted : Design.Palette.danger)
                        .frame(width: 10, height: 10)
                }
                Text(status.headline)
                    .designText(.bodyStrong)
                    .foregroundStyle(status.isRecording && !status.isPaused ? Design.Palette.danger : Design.Palette.ink)
                    .accessibilityIdentifier("menuBarHeadline")
            }
            if !status.detail.isEmpty {
                Text(status.detail)
                    .designText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("menuBarDetail")
            }
            if let notice = status.permissionNotice {
                Text(notice)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
            }

            Button {
                Task { await recording.toggle() }
            } label: {
                Label(status.toggleTitle, systemImage: status.isRecording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(!status.canToggle)
            .accessibilityIdentifier("menuBarToggle")

            if status.isRecording {
                HStack(spacing: Design.Spacing.xs) {
                    Button {
                        recording.togglePause()
                    } label: {
                        Label(status.pauseTitle, systemImage: status.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillSecondary)
                    .disabled(!status.canPause)
                    .accessibilityIdentifier("menuBarPause")

                    Button {
                        recording.addBookmark()
                    } label: {
                        Label(status.bookmarkTitle, systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillSecondary)
                    .disabled(!status.canBookmark)
                    .accessibilityIdentifier("menuBarBookmark")
                }
            }

            if let message = recording.errorMessage {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("menuBarError")
            }

            Divider()
            HStack {
                Button("창 열기") {
                    openWindow(id: LectureRecorderApp.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.textLink)
                .accessibilityIdentifier("menuBarOpenWindow")
                Spacer()
            }
        }
    }
}
