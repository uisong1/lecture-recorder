import AppKit
import LectureCore
import SwiftUI

/// 메뉴 막대 아이콘. 녹음 중이면 모양이 바뀐다.
struct MenuBarLabel: View {
    let recording: RecordingController

    var body: some View {
        switch recording.menuBarStatus.icon {
        case .idle: Image(systemName: "mic").accessibilityLabel(recording.menuBarStatus.headline)
        case .recording: Image(systemName: "record.circle.fill").accessibilityLabel(recording.menuBarStatus.headline)
        case .paused: Image(systemName: "pause.circle.fill").accessibilityLabel(recording.menuBarStatus.headline)
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
        .padding(Design.Spacing.sm)
        .frame(width: 220)
        .designCanvas()
    }

    private func content(for status: MenuBarStatus) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                if status.isRecording {
                    Circle()
                        .fill(status.isPaused ? Design.Palette.inkMuted : Design.Palette.danger)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(status.headline)
                    .designText(.captionStrong)
                    .foregroundStyle(status.isRecording && !status.isPaused ? Design.Palette.danger : Design.Palette.ink)
                    .accessibilityIdentifier("menuBarHeadline")
            }
            if !status.detail.isEmpty {
                Text(status.detail)
                    .designText(.finePrint)
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("menuBarDetail")
            }
            if let notice = status.pausedNotice {
                Text(notice)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.primary)
                    .accessibilityIdentifier("menuBarPausedNotice")
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
            .buttonStyle(.pillCompact)
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
                    .buttonStyle(.pillSecondaryCompact)
                    .disabled(!status.canPause)
                    .accessibilityIdentifier("menuBarPause")

                    Button {
                        recording.addBookmark()
                    } label: {
                        Label(status.bookmarkTitle, systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillSecondaryCompact)
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
