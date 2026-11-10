import LectureCore
import SwiftUI

/// 수업이 시작됐는데 녹음 전일 때 노치 아래에 뜨는 불빛과 안내 (DECISIONS.md 2026-11-10).
/// 불빛은 Action Blue 하나만 쓰고, 소리는 내지 않는다. 그림자 대신 번지는 흐림 효과로만 표현한다.
struct NotchAlertView: View {
    let info: NotchAlertInfo
    let notchWidth: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @State private var isBright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 240, height: 76)

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(Design.Palette.primary)
                    .frame(width: notchWidth + 20, height: 40)
                    .blur(radius: 14)
                    .opacity(reduceMotion || isBright ? 0.7 : 0.4)
                    .offset(y: -12)
                VStack(spacing: 2) {
                    Text("\(info.subjectName) 수업이 시작됐어요")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("눌러서 녹음 창 열기")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                .padding(.top, 38)
                .foregroundStyle(.white)
            }
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("이번 수업은 알리지 않기", action: onDismiss)
        }
        .accessibilityLabel("\(info.subjectName) 수업이 시작됐어요. 눌러서 녹음 창 열기")
        .accessibilityIdentifier("notchAlert")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { isBright = true }
        }
    }
}
