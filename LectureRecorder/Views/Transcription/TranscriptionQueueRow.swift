import LectureCore
import SwiftUI

/// 전사 대기열 한 줄. 창이 좁으면 시안 A(제목 · 상태 · 버튼 세 칸 고정폭), 넓으면 시안 B(상태·막대를 제목 아래 한 줄로).
/// 버튼 개수가 달라도 진행 막대가 줄마다 같은 자리에 오게 칸 폭을 고정한다 (2026-11-28 사용자 결정).
struct TranscriptionQueueRow: View {
    /// 대기열 카드가 이 폭 이상이면 B로 보인다.
    static let wideWidth: CGFloat = 760
    static let statusWidth: CGFloat = 280
    static let actionsWidth: CGFloat = 170

    let entry: TranscriptionQueue.Entry
    let waitingPosition: Int
    let isWide: Bool
    let queue: TranscriptionQueue
    let onOpen: () -> Void

    private var display: TranscriptionRowDisplay {
        TranscriptionRowDisplay(entry: entry, waitingPosition: waitingPosition)
    }

    var body: some View {
        let display = display
        VStack(spacing: 0) {
            Group {
                if isWide { wide(display) } else { narrow(display) }
            }
            .padding(.vertical, Design.Spacing.sm)
            .padding(.horizontal, Design.Spacing.md)
            Rectangle().fill(Design.Palette.fill).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcriptionRow-\(entry.job.title)")
    }

    // MARK: 시안 A

    private func narrow(_ display: TranscriptionRowDisplay) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.job.title)
                    .designText(.bodyStrong)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.job.subtitle)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            status(display)
                .frame(width: Self.statusWidth, alignment: .leading)
            actions(display)
                .frame(width: Self.actionsWidth, alignment: .trailing)
        }
    }

    // MARK: 시안 B

    private func wide(_ display: TranscriptionRowDisplay) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
                Text(entry.job.title)
                    .designText(.bodyStrong)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Text("· \(entry.job.subtitle)")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Design.Spacing.sm)
                actions(display)
            }
            status(display)
        }
    }

    // MARK: 공통

    @ViewBuilder
    private func status(_ display: TranscriptionRowDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Design.Spacing.xs) {
                if display.isFailure {
                    // DESIGN.md: 경고는 빨강 대신 ⚠ + 굵은 글자.
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Design.Palette.ink)
                        .accessibilityHidden(true)
                }
                Text(display.status)
                    .designText(display.isFailure || display.progress != nil ? .captionStrong : .caption)
                    .foregroundStyle(display.isFailure || display.progress != nil ? Design.Palette.ink : Design.Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(display.status)
                Spacer(minLength: 0)
                if let remaining = display.remainingSeconds {
                    Text("\(TranscriptionView.approx(remaining)) 남음")
                        .designText(.finePrint)
                        .foregroundStyle(Design.Palette.inkMuted)
                } else if let note = display.note {
                    Text(note)
                        .designText(.finePrint)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
            }
            if let progress = display.progress {
                DesignProgressBar(value: progress, height: 4)
            }
            if let detail = display.failureDetail {
                Text(detail)
                    .designText(.finePrint)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(entry.failureDetail ?? detail)
                    .accessibilityIdentifier("transcriptionFailureDetail")
            }
        }
    }

    private func actions(_ display: TranscriptionRowDisplay) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(display.actions, id: \.self) { action in
                Button(action.title) { perform(action) }
                    .buttonStyle(.pillSecondaryCompact)
                    .help(help(for: action))
            }
        }
    }

    private func perform(_ action: TranscriptionRowDisplay.Action) {
        switch action {
        case .pause: queue.pause(id: entry.id)
        case .resume: queue.resume(id: entry.id)
        case .remove: queue.remove(id: entry.id)
        case .retry: queue.retry(id: entry.id)
        case .open: onOpen()
        }
    }

    private func help(for action: TranscriptionRowDisplay.Action) -> String {
        switch action {
        case .pause: "지금 조각(최대 3분)까지 마치고 멈춰요. 나중에 이어서 할 수 있어요"
        case .resume: "멈춘 데서 이어서 전사해요"
        case .remove: "대기열에서 빼요. 하던 것은 지워져요"
        case .retry: "처음부터 다시 전사해요"
        case .open: "전사 결과를 봐요"
        }
    }
}
