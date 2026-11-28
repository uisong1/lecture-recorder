import LectureCore
import SwiftUI

/// "내보내기…"를 누르면 먼저 뜨는 작은 창: 녹음과 전사본 / 녹음만 / 전사본만 (시안 export-options C, 2026-11-28 사용자 선택).
/// 고른 뒤 "위치 고르기…"로 폴더를 정한다.
struct ExportBundleSheet: View {
    let label: String
    let choices: BundleExportChoices
    let onCancel: () -> Void
    let onChoose: (BundleContents) -> Void

    @State private var selected: BundleContents = .both

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("내보내기")
                .designText(.tagline)
                .foregroundStyle(Design.Palette.ink)
            Text("\(label) · 녹음 \(choices.recordingCount)개")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, Design.Spacing.xxs)
            ForEach(BundleContents.allCases, id: \.self) { contents in
                option(contents)
            }
            HStack(spacing: Design.Spacing.xs) {
                Spacer()
                Button("취소", action: onCancel)
                    .buttonStyle(.pillSecondaryCompact)
                    .keyboardShortcut(.cancelAction)
                Button("위치 고르기…") { onChoose(selected) }
                    .buttonStyle(.pillCompact)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!choices.isAvailable(selected))
                    .accessibilityIdentifier("exportChooseLocation")
            }
            .padding(.top, Design.Spacing.sm)
        }
        .padding(22)
        .frame(width: 400)
        .background(Design.Palette.canvas)
        .accessibilityIdentifier("exportBundleSheet")
    }

    private func option(_ contents: BundleContents) -> some View {
        let isOn = selected == contents
        let isAvailable = choices.isAvailable(contents)
        return Button {
            selected = contents
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.xs) {
                Circle()
                    .strokeBorder(isOn ? Design.Palette.ink : Design.Palette.inkFaint, lineWidth: isOn ? 5 : 1.5)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contents.label)
                        .designText(.captionStrong)
                        .foregroundStyle(Design.Palette.ink)
                    Text(choices.detail(for: contents))
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, Design.Spacing.sm)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.md)
                    .strokeBorder(isOn ? Design.Palette.ink : Design.Palette.hairline, lineWidth: isOn ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("exportOption-\(contents.rawValue)")
    }
}
