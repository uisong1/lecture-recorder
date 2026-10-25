import LectureCore
import SwiftUI
import UniformTypeIdentifiers

/// 에브리타임 시간표 캡처를 끌어다 놓거나 골라서 가져오는 창.
/// 읽은 결과를 미리보기 표에서 고친 뒤 "저장"을 눌러야만 과목과 시간표가 바뀐다.
struct TimetableImportView: View {
    static let windowID = "timetable-import"

    let model: TimetableImportModel
    @State private var isTargeted = false
    @State private var isPickingFile = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .waiting: dropZone
            case .reading: reading
            case .preview: preview
            case .saved(let result): saved(result)
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .designCanvas(Design.Palette.parchment)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.phase == .waiting, let url = urls.first else { return false }
            Task { await model.load(fileAt: url) }
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): Task { await model.load(fileAt: url) }
            case .failure(let error): Log.data.error("시간표 이미지 선택 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        // 창을 닫으면 저장하지 않은 초안은 버린다.
        .onDisappear { model.reset() }
    }

    // MARK: 이미지 놓기

    private var dropZone: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "calendar.badge.plus")
                .designText(.displayLg)
                .foregroundStyle(Design.Palette.primary)
            Text("에브리타임 시간표 캡처를 여기에 끌어다 놓으세요")
                .designText(.tagline)
                .foregroundStyle(Design.Palette.ink)
            Text("시간표 화면 전체가 나온 이미지(PNG, JPEG)를 쓰세요. 이미지는 이 Mac 안에서만 읽으며, 로그인이나 전송은 없습니다.")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .multilineTextAlignment(.center)
            Button("이미지 고르기…") { isPickingFile = true }
                .buttonStyle(.pill)
                .accessibilityIdentifier("pickTimetableImage")
            if let message = model.errorMessage {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("timetableImportError")
            }
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Palette.canvas, in: RoundedRectangle(cornerRadius: Design.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.lg)
                .strokeBorder(isTargeted ? Design.Palette.primaryFocus : Design.Palette.hairline, lineWidth: isTargeted ? 2 : 1)
        }
        .padding(Design.Spacing.lg)
        .accessibilityIdentifier("timetableDropZone")
    }

    private var reading: some View {
        VStack(spacing: Design.Spacing.md) {
            ProgressView().controlSize(.large)
            Text("시간표를 읽는 중…")
                .designText(.body)
                .foregroundStyle(Design.Palette.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 미리보기

    private var preview: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text("읽은 시간표를 확인하세요")
                        .designText(.tagline)
                        .foregroundStyle(Design.Palette.ink)
                    Text("틀린 곳은 바로 고칠 수 있습니다. 저장을 누르기 전에는 아무것도 바뀌지 않습니다. 강의실이 없거나 채플인 칸은 꺼 두었습니다.")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                Spacer()
                HStack(spacing: Design.Spacing.xs) {
                    Text("학기")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                    TextField("2026년 2학기", text: semesterBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityIdentifier("timetableSemester")
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.editor?.draft.rows.indices ?? 0..<0, id: \.self) { index in
                        rowView(index)
                        Divider().overlay(Design.Palette.hairline)
                    }
                    HStack {
                        Button("줄 추가") { _ = model.editor?.addRow() }
                            .buttonStyle(.textLink)
                            .accessibilityIdentifier("addTimetableRow")
                        Spacer()
                    }
                    .padding(Design.Spacing.sm)
                    untimedSection
                }
            }
            .background(Design.Palette.canvas, in: RoundedRectangle(cornerRadius: Design.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.lg).strokeBorder(Design.Palette.hairline, lineWidth: 1)
            }

            problems
            footer
        }
        .padding(Design.Spacing.lg)
    }

    private func rowView(_ index: Int) -> some View {
        let included = row(index)?.include ?? false
        return HStack(spacing: Design.Spacing.xs) {
            Toggle("저장", isOn: includeBinding(index))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("끄면 이 줄은 저장하지 않습니다")
                .accessibilityIdentifier("timetableInclude-\(index)")
            TextField("과목 이름", text: nameBinding(index))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
                .accessibilityIdentifier("timetableName-\(index)")
            Picker("요일", selection: weekdayBinding(index)) {
                ForEach(Weekday.mondayFirst, id: \.self) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
            .labelsHidden()
            .frame(width: 64)
            TimePicker(label: "시작", time: startBinding(index))
            Text("–").designText(.caption).foregroundStyle(Design.Palette.inkMuted)
            TimePicker(label: "종료", time: endBinding(index))
            if row(index)?.hasRoom == false {
                Text("강의실 없음")
                    .designText(.finePrint)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            Spacer(minLength: 0)
            Button {
                model.editor?.deleteRow(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(index + 1)번째 줄 삭제")
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .opacity(included ? 1 : 0.5)
    }

    private var untimedSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("시간이 없는 과목 (폴더만 만듭니다)")
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.ink)
            ForEach(model.editor?.draft.untimedSubjects.indices ?? 0..<0, id: \.self) { index in
                HStack {
                    TextField("과목 이름", text: untimedBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button {
                        model.editor?.removeUntimedSubject(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("시간 없는 과목 \(index + 1) 삭제")
                    Spacer()
                }
            }
            Button("과목 추가") { model.editor?.addUntimedSubject() }
                .buttonStyle(.textLink)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var problems: some View {
        let issues = model.editor?.issues ?? []
        if !issues.isEmpty || model.errorMessage != nil {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                }
                if issues.isEmpty, let message = model.errorMessage {
                    Text(message)
                }
            }
            .designText(.caption)
            .foregroundStyle(Design.Palette.danger)
            .accessibilityIdentifier("timetableIssues")
        }
    }

    private var footer: some View {
        HStack(spacing: Design.Spacing.sm) {
            if model.existingSlotCount > 0 {
                Label("저장하면 지금 시간표 \(model.existingSlotCount)칸이 지워지고 이 시간표로 바뀝니다. 과목과 녹음은 그대로 남습니다.", systemImage: "info.circle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            Spacer()
            Button("다시 고르기") { model.reset() }
                .buttonStyle(.pillSecondary)
            Button("이 시간표로 저장") { Task { await model.confirm() } }
                .buttonStyle(.pill)
                .disabled(!(model.editor?.isValid ?? false))
                .accessibilityIdentifier("confirmTimetableImport")
        }
    }

    // MARK: 저장 완료

    private func saved(_ result: TimetableImportResult) -> some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .designText(.displayLg)
                .foregroundStyle(Design.Palette.primary)
            Text("시간표를 저장했습니다")
                .designText(.tagline)
                .foregroundStyle(Design.Palette.ink)
            Text("\(result.semester) · 과목 \(result.createdSubjects.count)개를 새로 만들고 \(result.reusedSubjects.count)개를 다시 썼습니다 · 시간표 \(result.slotCount)칸")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
            Text("이 학기 과목의 예전 녹음은 새 폴더(학기 / 과목)로 옮겨집니다.")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
            HStack(spacing: Design.Spacing.sm) {
                Button("다른 이미지 가져오기") { model.reset() }
                    .buttonStyle(.pillSecondary)
                Button("닫기") { dismiss() }
                    .buttonStyle(.pill)
            }
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("timetableImportSaved")
    }

    // MARK: 값 연결

    private func row(_ index: Int) -> TimetableRow? {
        guard let rows = model.editor?.draft.rows, rows.indices.contains(index) else { return nil }
        return rows[index]
    }

    private var semesterBinding: Binding<String> {
        Binding(get: { model.editor?.draft.semester ?? "" }, set: { model.editor?.setSemester($0) })
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(get: { row(index)?.name ?? "" }, set: { model.editor?.setName($0, at: index) })
    }

    private func includeBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { row(index)?.include ?? false }, set: { model.editor?.setInclude($0, at: index) })
    }

    private func weekdayBinding(_ index: Int) -> Binding<Weekday> {
        Binding(get: { row(index)?.weekday ?? .monday }, set: { model.editor?.setWeekday($0, at: index) })
    }

    private func startBinding(_ index: Int) -> Binding<TimeOfDay> {
        Binding(get: { row(index)?.start ?? .midnight }, set: { model.editor?.setStart($0, at: index) })
    }

    private func endBinding(_ index: Int) -> Binding<TimeOfDay> {
        Binding(get: { row(index)?.end ?? .midnight }, set: { model.editor?.setEnd($0, at: index) })
    }

    private func untimedBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let names = model.editor?.draft.untimedSubjects, names.indices.contains(index) else { return "" }
                return names[index]
            },
            set: { model.editor?.renameUntimedSubject(at: index, to: $0) }
        )
    }
}
