import LectureCore
import SwiftUI

/// 끌어다 놓거나 고른 mp4·m4a를 목록에 넣기 전에 과목과 날짜를 확인하는 창.
struct MediaImportSheet: View {
    let model: MediaImportModel
    let subjects: SubjectManager

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text("녹음으로 가져오기")
                .designText(.tagline)
                .foregroundStyle(Design.Palette.ink)
            Text("영상(mp4)은 소리만 꺼내 m4a로 저장하고, 원본 파일은 건드리지 않습니다.")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)

            if !model.items.isEmpty {
                HStack(spacing: Design.Spacing.xs) {
                    Text("과목")
                        .designText(.body)
                        .foregroundStyle(Design.Palette.ink)
                    Picker("과목", selection: $model.subject) {
                        Text("미분류").tag(Subject?.none)
                        ForEach(subjects.subjects) { subject in
                            Text(subject.name).tag(Subject?.some(subject))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .disabled(model.isImporting)
                    .accessibilityIdentifier("importSubject")
                }
                VStack(spacing: 0) {
                    ForEach(model.items) { item in
                        row(item)
                        Divider().overlay(Design.Palette.hairline)
                    }
                }
            }

            if let message = model.message {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("importMessage")
            }

            HStack {
                Spacer()
                Button("닫기") { model.close() }
                    .buttonStyle(.pillSecondary)
                    .disabled(model.isImporting)
                    .accessibilityIdentifier("importClose")
                Button("가져오기") { Task { await model.run() } }
                    .buttonStyle(.pill)
                    .disabled(!model.canImport)
                    .accessibilityIdentifier("importRun")
            }
        }
        .padding(Design.Spacing.lg)
        .frame(width: 560)
        .designCanvas()
    }

    private func row(_ item: MediaImportModel.Item) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(item.name)
                    .designText(.body)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failed(let reason) = item.status {
                    Text(reason)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                }
            }
            Spacer()
            DatePicker("수업 날짜", selection: Binding(
                get: { item.startedAt },
                set: { model.setDate($0, for: item.id) }
            ))
            .labelsHidden()
            .disabled(model.isImporting || item.status == .done)
            switch item.status {
            case .importing: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle").foregroundStyle(Design.Palette.primary)
            default: EmptyView()
            }
        }
        .padding(.vertical, Design.Spacing.xs)
    }
}
