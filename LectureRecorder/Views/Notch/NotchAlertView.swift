import LectureCore
import SwiftUI

/// 노치 자리에 뜨는 두 가지 표시 (DECISIONS.md 2026-11-11). 그림자는 쓰지 않는다.
enum NotchLayout {
    static let bannerSize = CGSize(width: 420, height: 78)
    /// 날개 하나의 폭. 노치 폭 양옆으로 이만큼 늘어난다.
    static let wingWidth: CGFloat = 64
    static func recordingSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        CGSize(width: notchWidth + wingWidth * 2, height: notchHeight)
    }
}

/// 수업이 시작됐는데 녹음 전일 때 노치 아래에 뜨는 파란 배너. 흰 "녹음 열기" 버튼이 있고 배너 전체를 눌러도 같다.
/// 소리는 내지 않는다. 누르면 녹음 창을 열고, 우클릭으로 이번 수업은 끈다.
struct NotchBannerView: View {
    let info: NotchAlertInfo
    let notchHeight: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.subjectName) 수업이 시작됐어요")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("녹음 전이에요")
                        .font(.system(size: 12))
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Text("녹음 열기")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Palette.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Design.Palette.primary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, notchHeight + 6)
        .frame(width: NotchLayout.bannerSize.width, height: NotchLayout.bannerSize.height + notchHeight, alignment: .top)
        .contextMenu {
            Button("이번 수업은 알리지 않기", action: onDismiss)
        }
        .accessibilityLabel("\(info.subjectName) 수업이 시작됐어요. 녹음 전이에요. 눌러서 녹음 창 열기")
        .accessibilityIdentifier("notchAlert")
    }
}

/// 녹음 중에 노치 양옆으로 늘어나는 검은 날개. 왼쪽은 마이크 칸, 오른쪽은 움직이는 막대. 녹음 중 표시라 빨강이다.
/// 일시정지면 막대가 멈춘다. 눌러도 녹음은 건드리지 않고 앱 창만 연다.
struct NotchRecordingView: View {
    let isPaused: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = NotchLayout.recordingSize(notchWidth: notchWidth, notchHeight: notchHeight)
        Button(action: onOpen) {
            HStack(spacing: 0) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Design.Palette.danger))
                    .frame(width: NotchLayout.wingWidth)
                Spacer(minLength: notchWidth)
                bars.frame(width: NotchLayout.wingWidth)
            }
            .frame(width: size.width, height: size.height)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous).fill(Color.black)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(isPaused ? "녹음 일시정지 중. 눌러서 녹음 창 열기" : "녹음 중. 눌러서 녹음 창 열기")
        .accessibilityIdentifier("notchRecording")
    }

    private var bars: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: isPaused || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Design.Palette.danger)
                        .frame(width: 3, height: Self.barHeight(index: index, time: t, still: isPaused || reduceMotion))
                }
            }
        }
    }

    /// 막대 높이(4~16). 멈출 때는 낮고 고른 모양이다.
    static func barHeight(index: Int, time: TimeInterval, still: Bool) -> CGFloat {
        if still { return 6 }
        let wave = sin(time * 5 + Double(index) * 1.3)
        return 4 + CGFloat((wave + 1) / 2) * 12
    }
}
