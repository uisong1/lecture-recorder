import AppKit
import LectureCore
import SwiftUI

/// 고른 과목의 녹음을 고른 순서(기본 최신순)로 보여주고, 눌러서 재생한다.
struct RecordingListView: View {
    let library: RecordingLibrary
    let playback: PlaybackController
    let manager: RecordingManager

    @State private var renaming: Recording?
    @State private var renameText = ""
    @State private var deleting: Recording?
    /// 녹음 목록 대신 북마크를 모아 본다.
    @State private var showsBookmarks = false

    var body: some View {
        Group {
            if showsBookmarks {
                BookmarkOverviewView(library: library, playback: playback)
            } else if library.recordings.isEmpty && library.filter.isActive {
                ContentUnavailableView("조건에 맞는 녹음이 없습니다", systemImage: "magnifyingglass", description: Text("검색어나 기간을 바꿔 보세요."))
                    .accessibilityIdentifier("noMatchingRecordings")
            } else if library.recordings.isEmpty {
                ContentUnavailableView("녹음이 없습니다", systemImage: "waveform", description: Text(library.selection == .all ? "녹음한 수업이 여기에 나타납니다." : "이 과목으로 녹음한 수업이 여기에 나타납니다."))
                    .accessibilityIdentifier("emptyRecordings")
            } else {
                List(library.recordings) { recording in
                    let status = library.rowStatus(for: recording, using: manager)
                    HStack {
                        if recording.isUnplayed {
                            Circle()
                                .fill(Design.Palette.primary)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("안 들음")
                                .accessibilityIdentifier("unplayedDot")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.title)
                                .designText(.bodyStrong)
                                .foregroundStyle(Design.Palette.ink)
                                .accessibilityIdentifier("recordingRow")
                            Text((library.showsSubjectName ? "\(library.subjectName(of: recording)) · " : "") + "\(recording.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(RecordingController.format(recording.duration))")
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                            let extras = (recording.isUnplayed ? ["안 들음"] : []) + (RecordingRowStatus.bookmarkLabel(count: recording.bookmarks.count).map { [$0] } ?? []) + status.labels
                            if !extras.isEmpty {
                                Text(extras.joined(separator: " · "))
                                    .designText(.caption)
                                    .foregroundStyle(status.isMissing ? Design.Palette.danger : Design.Palette.inkMuted)
                                    .accessibilityIdentifier("recordingStatus")
                            }
                        }
                        Spacer()
                        Button(playback.current === recording && playback.isPlaying ? "일시정지" : "듣기") { play(recording) }
                            .buttonStyle(.textLink)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { play(recording) }
                    .contextMenu {
                        Button("이름 변경…") {
                            renameText = recording.title
                            renaming = recording
                        }
                        Menu("과목 이동") {
                            ForEach(library.subjects) { subject in
                                Button(subject.name) { perform { try manager.move(recording, to: subject) } }
                            }
                            Button(RecordingStorage.unclassifiedFolder) { perform { try manager.move(recording, to: nil) } }
                        }
                        Divider()
                        Button("Finder에서 보기") {
                            NSWorkspace.shared.activateFileViewerSelecting([manager.fileURL(for: recording)])
                        }
                        Button("다른 곳에 저장…") { export(recording) }
                        if let url = manager.shareURL(for: recording) {
                            ShareLink("공유…", item: url)
                        }
                        Divider()
                        Button("휴지통으로 이동…", role: .destructive) { deleting = recording }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: Binding(get: { library.filter.query }, set: { library.filter.query = $0 }), prompt: showsBookmarks ? "메모·제목 검색" : "제목 검색")
        .toolbar {
            ToolbarItem {
                Picker("보기", selection: $showsBookmarks) {
                    Text("녹음").tag(false)
                    Text("북마크").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("listModePicker")
            }
            ToolbarItem {
                Picker("정렬", selection: Binding(get: { library.sortOrder }, set: { library.sortOrder = $0 })) {
                    ForEach(RecordingSortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(showsBookmarks)
                .accessibilityIdentifier("sortOrder")
            }
            ToolbarItem {
                Toggle("안 들은 것만", isOn: Binding(get: { library.filter.unplayedOnly }, set: { library.filter.unplayedOnly = $0 }))
                    .toggleStyle(.button)
                    .disabled(showsBookmarks)
                    .accessibilityIdentifier("unplayedOnly")
            }
            ToolbarItem {
                Picker("기간", selection: Binding(get: { library.filter.period }, set: { library.filter.period = $0 })) {
                    ForEach(RecordingPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("periodFilter")
            }
        }
        .scrollContentBackground(.hidden)
        .designCanvas()
        .alert("이름 변경", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("제목", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("변경") {
                if let recording = renaming { perform { try manager.rename(recording, to: renameText) } }
            }
        }
        .confirmationDialog(
            "‘\(deleting?.title ?? "")’을(를) 삭제할까요?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("휴지통으로 이동", role: .destructive) {
                if let recording = deleting {
                    if playback.current === recording { playback.select(nil) }
                    perform { try manager.trash(recording) }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("녹음 파일이 휴지통으로 이동합니다. 휴지통에서 되돌릴 수 있습니다.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.current != nil { PlaybackBar(playback: playback) }
        }
        .overlay(alignment: .bottom) {
            if let message = manager.errorMessage ?? library.errorMessage ?? playback.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .padding(8)
            }
        }
    }

    /// 파일이 있으면 재생·일시정지하고, 없으면 재생 대신 안내를 보인다.
    private func play(_ recording: Recording) {
        guard manager.canPlay(recording) else { return }
        playback.select(recording)
        playback.togglePlayPause()
    }

    /// 저장 위치를 고르는 대화상자를 열고 녹음 파일을 복사한다.
    private func export(_ recording: Recording) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = manager.suggestedExportName(for: recording)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        perform { try manager.export(recording, to: destination) }
    }

    /// 동작을 실행하고 목록을 다시 읽는다. 오류 문구는 `manager.errorMessage`에 남는다.
    private func perform(_ action: () throws -> Void) {
        try? action()
        library.reload()
    }
}
