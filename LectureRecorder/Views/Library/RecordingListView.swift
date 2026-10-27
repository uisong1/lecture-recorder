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
    @State private var memoing: Recording?
    @State private var memoText = ""
    @State private var deleting: Recording?
    /// 여러 건 삭제 확인 창.
    @State private var confirmsBulkTrash = false
    /// 여러 건 처리에서 실패한 건이 있을 때의 안내.
    @State private var batchNotice: String?
    /// 녹음 목록 대신 북마크를 모아 본다.
    @State private var showsBookmarks = false
    /// Claude용 묶음 내보내기 결과 안내.
    @State private var bundleNotice: String?

    var body: some View {
        withOverlays(withDialogs(withToolbar(content)))
    }

    private var content: some View {
        Group {
            if showsBookmarks {
                BookmarkOverviewView(library: library, playback: playback)
            } else if library.recordings.isEmpty && library.filter.isActive {
                ContentUnavailableView("조건에 맞는 녹음이 없습니다", systemImage: "magnifyingglass", description: Text("검색어나 기간을 바꿔 보세요."))
                    .accessibilityIdentifier("noMatchingRecordings")
            } else if library.recordings.isEmpty {
                ContentUnavailableView("녹음이 없습니다", systemImage: "waveform", description: Text(emptyDescription))
                    .accessibilityIdentifier("emptyRecordings")
            } else {
                recordingList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        library.selection == .all ? "녹음한 수업이 여기에 나타납니다." : "이 과목으로 녹음한 수업이 여기에 나타납니다."
    }

    private var recordingList: some View {
        List(library.recordings, selection: Bindable(library).selectedIDs) { recording in
            row(for: recording)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { play(recording) }
                .contextMenu { rowMenu(for: recording) }
        }
    }

    private func isPlaying(_ recording: Recording) -> Bool {
        playback.current === recording && playback.isPlaying
    }

    private func detailLine(for recording: Recording) -> String {
        let subject: String = library.showsSubjectName ? "\(library.subjectName(of: recording)) · " : ""
        let started: String = recording.startedAt.formatted(date: .abbreviated, time: .shortened)
        let length: String = RecordingController.format(recording.duration)
        return subject + started + " · " + length
    }

    private func extraLabels(for recording: Recording, status: RecordingRowStatus) -> [String] {
        var labels: [String] = []
        if recording.isUnplayed { labels.append("안 들음") }
        if let bookmarks = RecordingRowStatus.bookmarkLabel(count: recording.bookmarks.count) { labels.append(bookmarks) }
        labels.append(contentsOf: status.labels)
        return labels
    }

    private func row(for recording: Recording) -> some View {
        HStack {
            if recording.isUnplayed {
                Circle()
                    .fill(Design.Palette.primary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("unplayedDot")
            }
            rowText(for: recording)
            Spacer()
            Button(isPlaying(recording) ? "일시정지" : "듣기") { play(recording) }
                .buttonStyle(.textLink)
                .accessibilityLabel((isPlaying(recording) ? "일시정지: " : "듣기: ") + recording.title)
        }
    }

    private func rowText(for recording: Recording) -> some View {
        let status: RecordingRowStatus = library.rowStatus(for: recording, using: manager)
        let matches = BookmarkMatchSummary(library.matchingBookmarks(of: recording)) { $0.note }
        let extras: [String] = extraLabels(for: recording, status: status)
        return VStack(alignment: .leading, spacing: 2) {
            Text(recording.title)
                .designText(.bodyStrong)
                .foregroundStyle(Design.Palette.ink)
                .accessibilityIdentifier("recordingRow")
            Text(detailLine(for: recording))
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
            if !recording.memo.isEmpty {
                Text("수업 메모: \(recording.memo)")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("recordingMemo")
            }
            ForEach(matches.shown) { bookmark in
                matchedBookmarkButton(bookmark, in: recording)
            }
            if let hidden = matches.hiddenText {
                Button(hidden) { showsBookmarks = true }
                    .buttonStyle(.textLink)
                    .help("북마크 보기에서 맞은 메모를 모두 봅니다")
                    .accessibilityLabel("맞은 북마크 메모 \(matches.hiddenCount)개 더 보기")
                    .accessibilityIdentifier("hiddenBookmarkNotes")
            }
            if !extras.isEmpty {
                Text(extras.joined(separator: " · "))
                    .designText(.caption)
                    .foregroundStyle(status.isMissing ? Design.Palette.danger : Design.Palette.inkMuted)
                    .accessibilityIdentifier("recordingStatus")
            }
        }
    }

    private func matchedBookmarkButton(_ bookmark: Bookmark, in recording: Recording) -> some View {
        let time: String = RecordingController.format(bookmark.time)
        return Button {
            guard manager.canPlay(recording) else { return }
            playback.select(recording)
            playback.play(from: bookmark)
        } label: {
            Text("메모: \(bookmark.note)")
                .designText(.caption)
                .foregroundStyle(Design.Palette.primary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("\(time) 북마크 앞부분부터 듣기")
        .accessibilityLabel("북마크 메모 \(bookmark.note), \(time)부터 듣기")
        .accessibilityIdentifier("matchedBookmarkNote")
    }

    @ViewBuilder
    private func rowMenu(for recording: Recording) -> some View {
        if library.isMultiSelecting && library.selectedIDs.contains(recording.persistentModelID) {
            bulkActions
        } else {
            singleActions(for: recording)
        }
    }

    @ViewBuilder
    private func singleActions(for recording: Recording) -> some View {
        Button("이름 변경…") {
            renameText = recording.title
            renaming = recording
        }
        Button(recording.memo.isEmpty ? "메모 쓰기…" : "메모 고치기…") {
            memoText = recording.memo
            memoing = recording
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

    private var queryBinding: Binding<String> {
        Binding(get: { library.filter.query }, set: { library.filter.query = $0 })
    }

    private var unplayedBinding: Binding<Bool> {
        Binding(get: { library.filter.unplayedOnly }, set: { library.filter.unplayedOnly = $0 })
    }

    private func presence<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    private func withToolbar<V: View>(_ view: V) -> some View {
        view
            .searchable(text: queryBinding, prompt: "제목·북마크 메모 검색")
            .toolbar { toolbarContent }
            .scrollContentBackground(.hidden)
            .designCanvas()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("보기", selection: $showsBookmarks) {
                Text("녹음").tag(false)
                Text("북마크").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("listModePicker")
        }
        ToolbarItem {
            Toggle("안 들은 것만", isOn: unplayedBinding)
                .toggleStyle(.button)
                .disabled(showsBookmarks)
                .accessibilityIdentifier("unplayedOnly")
        }
        ToolbarItem {
            moreMenu
        }
    }

    private func withDialogs<V: View>(_ view: V) -> some View {
        let bulkTitle: String = "녹음 \(library.selectedRecordings.count)개를 삭제할까요?"
        let singleTitle: String = "‘\(deleting?.title ?? "")’을(를) 삭제할까요?"
        let trashMessage: String = "녹음 파일이 휴지통으로 이동합니다. 휴지통에서 되돌릴 수 있습니다."
        return view
            .alert("이름 변경", isPresented: presence($renaming)) {
                TextField("제목", text: $renameText)
                Button("취소", role: .cancel) {}
                Button("변경") {
                    if let recording = renaming { perform { try manager.rename(recording, to: renameText) } }
                }
            }
            .alert("수업 메모", isPresented: presence($memoing)) {
                TextField("예: 중간고사 범위 발표", text: $memoText)
                Button("취소", role: .cancel) {}
                Button("저장") {
                    if let recording = memoing { perform { try manager.setMemo(memoText, for: recording) } }
                }
            }
            .alert("처리 결과", isPresented: presence($batchNotice)) {
                Button("확인") {}
            } message: {
                Text(batchNotice ?? "")
            }
            .alert("내보내기", isPresented: presence($bundleNotice)) {
                Button("확인") {}
            } message: {
                Text(bundleNotice ?? "")
            }
            .confirmationDialog(bulkTitle, isPresented: $confirmsBulkTrash, titleVisibility: .visible) {
                Button("휴지통으로 이동", role: .destructive) { trashSelected() }
                Button("취소", role: .cancel) {}
            } message: {
                Text(trashMessage)
            }
            .confirmationDialog(singleTitle, isPresented: presence($deleting), titleVisibility: .visible) {
                Button("휴지통으로 이동", role: .destructive) {
                    if let recording = deleting {
                        if playback.current === recording { playback.select(nil) }
                        perform { try manager.trash(recording) }
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(trashMessage)
            }
    }

    private func withOverlays<V: View>(_ view: V) -> some View {
        view
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if library.isMultiSelecting && !showsBookmarks { selectionBar }
                    if library.filter.isActive { filterBar }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playback.current != nil { PlaybackBar(playback: playback, manager: manager, library: library) }
            }
            .overlay(alignment: .bottom) { errorOverlay }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let message = manager.errorMessage ?? library.errorMessage ?? playback.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.danger)
                .padding(Design.Spacing.xs)
        }
    }

    /// 자주 쓰지 않는 정렬·기간·내보내기를 한 메뉴로 모았다.
    private var moreMenu: some View {
        Menu {
            Picker("정렬", selection: Binding(get: { library.sortOrder }, set: { library.sortOrder = $0 })) {
                ForEach(RecordingSortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .disabled(showsBookmarks)
            .accessibilityIdentifier("sortOrder")
            Picker("기간", selection: Binding(get: { library.filter.period }, set: { selectPeriod($0) })) {
                ForEach(RecordingPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("periodFilter")
            Divider()
            Button("Claude용 내보내기…") { exportBundle() }
                .help("지금 목록의 녹음과 북마크·메모를 한 폴더로 묶어 내보냅니다.")
                .disabled(showsBookmarks || library.recordings.isEmpty)
                .accessibilityIdentifier("exportBundle")
        } label: {
            Label("더 보기", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("moreMenu")
    }

    /// 둘 이상 골랐을 때 목록 위에 보이는 줄.
    private var selectionBar: some View {
        HStack(spacing: Design.Spacing.sm) {
            Text("\(library.selectedRecordings.count)개 선택됨")
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.ink)
                .accessibilityIdentifier("selectionCount")
            Spacer()
            bulkActions
                .buttonStyle(.textLink)
            Button("선택 해제") { library.clearSelection() }
                .buttonStyle(.textLink)
                .accessibilityIdentifier("clearSelection")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .background(Design.Palette.parchment)
        .accessibilityIdentifier("selectionBar")
    }

    /// 선택한 녹음에 대한 동작. 막대와 우클릭 메뉴가 함께 쓴다.
    @ViewBuilder
    private var bulkActions: some View {
        Button("Claude용 내보내기…") { exportBundle() }
            .accessibilityIdentifier("exportSelected")
        Menu("과목 옮기기") {
            ForEach(library.subjects) { subject in
                Button(subject.name) { moveSelected(to: subject) }
            }
            Button(RecordingStorage.unclassifiedFolder) { moveSelected(to: nil) }
        }
        .accessibilityIdentifier("moveSelected")
        Button("휴지통으로 이동…", role: .destructive) { confirmsBulkTrash = true }
            .accessibilityIdentifier("trashSelected")
    }

    private func moveSelected(to subject: Subject?) {
        let result = manager.move(library.selectedRecordings, to: subject)
        library.reload()
        batchNotice = result.failureNotice(done: "옮겼고,")
    }

    private func trashSelected() {
        let targets = library.selectedRecordings
        if let current = playback.current, targets.contains(where: { $0 === current }) { playback.select(nil) }
        let result = manager.trash(targets)
        library.reload()
        batchNotice = result.failureNotice(done: "휴지통으로 이동했고,")
    }

    /// 걸러지는 조건이 있을 때 목록 위에 보이는 줄. 직접 지정 기간이면 날짜를 여기서 고르고, 한 번에 해제한다.
    private var filterBar: some View {
        HStack(spacing: Design.Spacing.sm) {
            Text("필터 적용 중")
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.ink)
            if library.filter.period == .custom {
                DatePicker("시작일", selection: customDate(\.customStart), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("customStartDate")
                Text("~").designText(.caption).foregroundStyle(Design.Palette.inkMuted)
                DatePicker("끝일", selection: customDate(\.customEnd), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("customEndDate")
            }
            Spacer()
            Button("필터 해제") { library.filter = RecordingFilter() }
                .buttonStyle(.textLink)
                .accessibilityIdentifier("clearFilter")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .background(Design.Palette.parchment)
        .accessibilityIdentifier("filterBar")
    }

    /// 기간을 바꾼다. "직접 지정…"을 처음 고르면 오늘 하루로 시작한다.
    private func selectPeriod(_ period: RecordingPeriod) {
        var filter = library.filter
        filter.period = period
        if period == .custom {
            let today = Date()
            filter.customStart = filter.customStart ?? today
            filter.customEnd = filter.customEnd ?? today
        }
        library.filter = filter
    }

    private func customDate(_ keyPath: WritableKeyPath<RecordingFilter, Date?>) -> Binding<Date> {
        Binding(
            get: { library.filter[keyPath: keyPath] ?? Date() },
            set: { library.filter[keyPath: keyPath] = $0 }
        )
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

    /// 지금 목록(고른 과목과 기간)의 녹음을 폴더를 골라 묶어 내보내고 Finder에서 보여 준다.
    private func exportBundle() {
        let recordings = library.exportRecordings
        guard !recordings.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "묶음을 만들 위치를 고르세요."
        panel.prompt = "여기에 내보내기"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let result = try manager.exportBundle(recordings, label: library.exportLabel, to: parent, now: Date())
            NSWorkspace.shared.activateFileViewerSelecting([result.folder])
            if !result.skippedTitles.isEmpty {
                bundleNotice = "녹음 \(result.exportedCount)개를 내보냈습니다. 파일이 없어 빠진 녹음: " + result.skippedTitles.joined(separator: ", ")
            }
        } catch {
            bundleNotice = manager.errorMessage ?? error.localizedDescription
        }
    }

    /// 동작을 실행하고 목록을 다시 읽는다. 오류 문구는 `manager.errorMessage`에 남는다.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            // 문구는 manager.errorMessage에 남아 목록 아래에 보인다.
        }
        library.reload()
    }
}
