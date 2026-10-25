import LectureCore
import SwiftUI

struct SubjectSettingsView: View {
    @Bindable var manager: SubjectManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("새 과목 이름", text: $manager.draftName)
                    .onSubmit(manager.addDraft)
                    .accessibilityIdentifier("newSubjectName")
                ColorPicker(selection: $manager.draftColor)
                Button("추가", action: manager.addDraft)
                    .buttonStyle(.pill)
                    .accessibilityIdentifier("addSubject")
            }

            if let message = manager.errorMessage {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("subjectError")
            }

            // List 행 안의 텍스트 필드는 클릭해도 행 선택만 되고 포커스를 받지 않아 ScrollView를 쓴다.
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(manager.subjects) { subject in
                        SubjectRow(subject: subject, manager: manager)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if manager.subjects.isEmpty {
                    ContentUnavailableView("과목이 없습니다", systemImage: "books.vertical", description: Text("위에서 과목을 추가하세요."))
                }
            }
        }
        .padding()
        .designCanvas()
    }
}

private struct SubjectRow: View {
    let subject: Subject
    let manager: SubjectManager
    @State private var name = ""

    var body: some View {
        HStack {
            ColorPicker(selection: Binding(
                get: { subject.color },
                set: { color in manager.perform { try manager.setColor(color, for: subject) } }
            ))
            TextField("과목 이름", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { manager.perform { try manager.rename(subject, to: name) } }
                .accessibilityIdentifier("subjectName-\(subject.name)")
            Spacer()
            Button(role: .destructive) {
                manager.perform { try manager.delete(subject) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("과목 삭제 (녹음은 미분류로 남습니다)")
            .accessibilityLabel("\(subject.name) 삭제")
            .accessibilityIdentifier("deleteSubject-\(subject.name)")
        }
        .onAppear { name = subject.name }
        .onChange(of: subject.name) { _, newValue in name = newValue }
    }
}

/// 과목 색을 고르는 메뉴.
private struct ColorPicker: View {
    @Binding var selection: SubjectColor

    var body: some View {
        Picker("색상", selection: $selection) {
            ForEach(SubjectColor.allCases, id: \.self) { color in
                Label {
                    Text(color.displayName)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(color.color)
                }
                .tag(color)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}
