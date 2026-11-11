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

private struct NoticeLine: Identifiable {
    let id: String
    let text: String
    let color: Color
}

/// 메뉴 막대 아이콘을 눌렀을 때 뜨는 창. macOS 제어 센터의 "지금 재생 중" 위젯처럼
/// 왼쪽 둥근 칸, 굵은 과목명과 회색 부제, 오른쪽 아이콘 버튼으로 보여준다.
/// 앱이 뒤에 있어도 시작·정지·일시정지·북마크를 누를 수 있다.
struct MenuBarContent: View {
    let recording: RecordingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content(for: recording.menuBarStatus)
        }
        .frame(width: 320)
    }

    private func content(for status: MenuBarStatus) -> some View {
        VStack(spacing: 0) {
            widgetRow(for: status)
            notices(for: status)
            Divider().overlay(Design.Palette.hairline)
            Button("창 열기") {
                openWindow(id: LectureRecorderApp.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.textLink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .accessibilityIdentifier("menuBarOpenWindow")
        }
    }

    /// 위젯의 한 줄: 왼쪽 칸 + 제목/부제 + 오른쪽 아이콘 버튼.
    private func widgetRow(for status: MenuBarStatus) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            tile(for: status)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.isRecording ? status.subjectName : status.headline)
                    .designText(.bodyStrong)
                    .lineLimit(1)
                    .foregroundStyle(Design.Palette.ink)
                    .accessibilityIdentifier("menuBarHeadline")
                subtitle(for: status)
                    .accessibilityIdentifier("menuBarDetail")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if status.isRecording {
                Button {
                    recording.togglePause()
                } label: {
                    Image(systemName: status.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.iconPlain)
                .help(status.pauseTitle)
                .accessibilityLabel(status.pauseTitle)
                .disabled(!status.canPause)
                .accessibilityIdentifier("menuBarPause")

                Button {
                    recording.addBookmark()
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.iconPlain)
                .help(status.bookmarkTitle)
                .accessibilityLabel(status.bookmarkTitle)
                .disabled(!status.canBookmark)
                .accessibilityIdentifier("menuBarBookmark")
            }

            Button {
                Task { await recording.toggle() }
            } label: {
                Image(systemName: status.isRecording ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.iconFilled)
            .help(status.toggleTitle)
            .accessibilityLabel(status.toggleTitle)
            .disabled(!status.canToggle)
            .accessibilityIdentifier("menuBarToggle")
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.sm)
    }

    /// 왼쪽 둥근 칸. 녹음 중이면 파란 칸에 빨간 점, 아니면 회색 칸.
    private func tile(for status: MenuBarStatus) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Design.Radius.sm + 3, style: .continuous)
                .fill(status.isRecording ? Design.Palette.primary : Design.Palette.parchment)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: status.isPaused ? "pause.fill" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(status.isRecording ? Design.Palette.onPrimary : Design.Palette.inkMuted)
                }
            if status.isRecording && !status.isPaused {
                Circle()
                    .fill(Design.Palette.danger)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Design.Palette.canvas, lineWidth: 2))
                    .offset(x: 3, y: -3)
            }
        }
        .accessibilityHidden(true)
    }

    /// 회색 부제. 녹음 중이면 "녹음 중 · 15:17"(앞 글자만 빨강), 아니면 "지금 녹음하면: 과목".
    @ViewBuilder
    private func subtitle(for status: MenuBarStatus) -> some View {
        if status.isRecording {
            HStack(spacing: 0) {
                Text(status.headline)
                    .designText(.captionStrong)
                    .foregroundStyle(status.isPaused ? Design.Palette.inkMuted : Design.Palette.danger)
                Text(" · \(status.elapsedText)")
                    .designText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        } else {
            Text(status.detail.isEmpty ? "녹음 버튼을 눌러 시작해요" : status.detail)
                .designText(.caption)
                .lineLimit(1)
                .foregroundStyle(Design.Palette.inkMuted)
        }
    }

    /// 안내와 오류 문구. 있을 때만 위젯 줄 아래에 보인다.
    @ViewBuilder
    private func notices(for status: MenuBarStatus) -> some View {
        let lines: [NoticeLine] = [
            NoticeLine(id: "menuBarPausedNotice", text: status.pausedNotice ?? "", color: Design.Palette.primary),
            NoticeLine(id: "menuBarPermissionNotice", text: status.permissionNotice ?? "", color: Design.Palette.danger),
            NoticeLine(id: "menuBarError", text: recording.errorMessage ?? "", color: Design.Palette.danger),
        ].filter { !$0.text.isEmpty }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                ForEach(lines) { line in
                    Text(line.text)
                        .designText(.caption)
                        .foregroundStyle(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(line.id)
                }
            }
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.sm)
        }
    }
}
