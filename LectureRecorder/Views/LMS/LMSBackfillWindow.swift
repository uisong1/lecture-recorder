import LectureCore
import SwiftUI

/// "녹음 없는 수업일" 창: 빠진 수업을 고르고, LMS 강의 항목을 골라 소리를 그 수업 녹음으로 채운다.
struct LMSBackfillWindow: View {
    static let windowID = "lms-backfill"

    @Bindable var model: LMSBackfillModel
    let token: CanvasTokenModel

    private static let dateFormat = Date.FormatStyle().month().day().weekday(.abbreviated).hour().minute().locale(Locale(identifier: "ko_KR"))

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("녹음 없는 수업일")
                .designText(.tagline)
            Text("시간표에 수업이 있었는데 녹음이 없는 날입니다. 날짜를 고른 뒤 LMS의 강의 영상을 고르면 소리만 꺼내 그 수업의 녹음으로 넣습니다. 개인 복습용이라 공유·업로드되지 않습니다.")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
            if model.isHalted {
                halted
            } else if !token.hasToken {
                Label("설정 > LMS에서 Canvas 액세스 토큰을 먼저 저장하세요.", systemImage: "key")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("backfillNoToken")
            }
            HStack(alignment: .top, spacing: Design.Spacing.md) {
                classList
                    .frame(minWidth: 260, maxWidth: 300)
                itemList
            }
            statusLine
        }
        .padding(Design.Spacing.md)
        .frame(minWidth: 760, minHeight: 480)
        .designCanvas()
        .onAppear {
            token.refresh()
            model.reload()
        }
    }

    private var halted: some View {
        HStack(spacing: Design.Spacing.sm) {
            Label("가져오기를 멈췄습니다. 영상이 암호화되었거나 스트리밍 형식이라 우회하지 않습니다.", systemImage: "exclamationmark.triangle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.danger)
            Spacer()
            Button("다시 시도 허용") { model.resumeAfterHalt() }
                .buttonStyle(.pillSecondary)
        }
        .accessibilityIdentifier("backfillHalted")
    }

    private var classList: some View {
        List {
            if model.rows.isEmpty {
                Text("최근 4주 안에 녹음이 빠진 수업이 없습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            ForEach(model.rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(row.subjectName).designText(.bodyStrong)
                        Text(row.start.formatted(Self.dateFormat))
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.inkMuted)
                    }
                    Spacer()
                    Button("건너뛰기") { model.skip(row) }
                        .buttonStyle(.textLink)
                        .disabled(model.isBusy)
                }
                .padding(.vertical, Design.Spacing.xxs)
                .contentShape(Rectangle())
                .listRowBackground(model.selected?.id == row.id ? Design.Palette.parchment : Color.clear)
                .onTapGesture { Task { await model.select(row) } }
                .accessibilityIdentifier("backfillRow")
            }
        }
        .listStyle(.plain)
        .disabled(model.isHalted || !token.hasToken)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            if let selected = model.selected {
                Text("\(selected.subjectName) · \(selected.start.formatted(Self.dateFormat)) 녹음으로 넣을 강의")
                    .designText(.captionStrong)
                List(model.choices, id: \.itemID) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                            Text(item.title).designText(.body)
                            Text(item.moduleName)
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                        }
                        Spacer()
                        Button("이 강의로 채우기") { Task { await model.importItem(item) } }
                            .buttonStyle(.pill)
                            .disabled(model.isBusy || model.isHalted)
                    }
                    .accessibilityIdentifier("backfillItem")
                }
                .listStyle(.plain)
            } else {
                Text("왼쪽에서 수업일을 고르세요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .loadingItems:
            HStack(spacing: Design.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("LMS 강의 목록을 불러오는 중…").designText(.caption).foregroundStyle(Design.Palette.inkMuted)
            }
        case .working(let text):
            HStack(spacing: Design.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text(text).designText(.caption).foregroundStyle(Design.Palette.inkMuted)
            }
        case .done(let title):
            Label("녹음 목록에 넣었습니다: \(title)", systemImage: "checkmark.circle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.primary)
                .accessibilityIdentifier("backfillDone")
        case .failed(let message):
            if !model.isHalted {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("backfillFailed")
            }
        }
    }
}
