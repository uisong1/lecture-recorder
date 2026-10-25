import LectureCore
import SwiftUI

/// 사이드바의 과목 목록과 선택한 과목의 녹음 목록.
struct LibraryView: View {
    let library: RecordingLibrary
    let subjects: SubjectManager

    var body: some View {
        List(selection: selectionBinding) {
            Section("과목") {
                ForEach(subjects.subjects) { subject in
                    row(subject.name, count: library.count(for: subject), color: subject.color.color)
                        .tag(LibrarySelection.subject(subject.persistentModelID))
                        .accessibilityIdentifier("sidebar-\(subject.name)")
                }
                row(SubjectManager.unclassifiedName, count: library.unclassifiedCount, color: .gray)
                    .tag(LibrarySelection.unclassified)
                    .accessibilityIdentifier("sidebar-미분류")
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200)
    }

    private var selectionBinding: Binding<LibrarySelection?> {
        Binding(get: { library.selection }, set: { if let value = $0 { library.select(value) } })
    }

    private func row(_ name: String, count: Int, color: Color) -> some View {
        HStack {
            Image(systemName: "circle.fill").foregroundStyle(color).font(.caption)
            Text(name)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// 고른 분류의 녹음을 최신순으로 보여준다.
struct RecordingListView: View {
    let library: RecordingLibrary

    var body: some View {
        if library.recordings.isEmpty {
            ContentUnavailableView("녹음이 없습니다", systemImage: "waveform", description: Text("이 분류에 저장된 녹음이 없습니다."))
                .accessibilityIdentifier("emptyRecordingList")
        } else {
            List(library.recordings) { recording in
                HStack {
                    VStack(alignment: .leading) {
                        Text(recording.title).font(.headline)
                        Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(RecordingController.format(recording.duration))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("recordingRow-\(recording.title)")
            }
            .accessibilityIdentifier("recordingList")
        }
    }
}
