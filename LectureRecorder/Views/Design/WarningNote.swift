import SwiftUI

/// 경고 안내 카드 (DESIGN.md "안내 줄"): 흰 바탕에 ⚠ 아이콘, 굵은 첫 줄, 회색 설명, 아래에 버튼.
/// 빨강을 쓰지 않는다. `isStrong`이면 테두리를 검정으로 두껍게 해 사라지지 않는 중요한 알림을 구분한다.
struct WarningNote<Actions: View>: View {
    let title: String
    var detail: String?
    var isStrong = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title)
                    .designText(.captionStrong)
                    .foregroundStyle(Design.Palette.danger)
                if let detail {
                    Text(detail)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Design.Spacing.xs) { actions() }
                    .padding(.top, Design.Spacing.xxs)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Design.Spacing.sm)
        .padding(.horizontal, Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Palette.canvas, in: RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                .strokeBorder(isStrong ? Design.Palette.ink : Design.Palette.hairline, lineWidth: isStrong ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
    }
}

extension WarningNote where Actions == EmptyView {
    init(title: String, detail: String? = nil, isStrong: Bool = false) {
        self.init(title: title, detail: detail, isStrong: isStrong) { EmptyView() }
    }
}
