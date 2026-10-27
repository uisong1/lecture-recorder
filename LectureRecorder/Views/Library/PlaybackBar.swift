import LectureCore
import SwiftUI

/// 불러온 녹음의 재생 위치 슬라이더와 배속 선택. 뷰는 컨트롤러 상태만 보여준다.
struct PlaybackBar: View {
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary
    @State private var editingMemo = false
    @State private var memoText = ""
    @State private var dragTime: TimeInterval?
    @State private var editingNote: Bookmark?
    @State private var noteText = ""
    @State private var deleting: Bookmark?
    /// 수업 메모 저장에 실패했을 때의 문구.
    @State private var memoError: String?

    var body: some View {
        // 재생 중이 아닐 때는 갱신을 멈춘다. 끝 도달 감지는 재생 중에만 필요하다.
        TimelineView(.animation(minimumInterval: 0.25, paused: !playback.isPlaying)) { _ in
            let _ = playback.refresh()
            VStack(spacing: Design.Spacing.xs) {
                Text(playback.current?.title ?? "")
                    .designText(.captionStrong)
                    .foregroundStyle(Design.Palette.ink)
                if let recording = playback.current {
                    Button {
                        memoText = recording.memo
                        editingMemo = true
                    } label: {
                        Text(recording.memo.isEmpty ? "수업 메모 쓰기" : "수업 메모: \(recording.memo)")
                            .designText(.caption)
                            .foregroundStyle(recording.memo.isEmpty ? Design.Palette.primary : Design.Palette.inkMuted)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("이 수업에 대한 한 줄 메모를 쓰거나 고칩니다")
                    .accessibilityIdentifier("playbackMemo")
                    if let memoError {
                        Text(memoError)
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.danger)
                            .accessibilityIdentifier("playbackMemoError")
                    }
                }
                HStack(spacing: Design.Spacing.sm) {
                    Text(RecordingController.format(shownTime))
                        .designText(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Design.Palette.inkMuted)
                    Slider(
                        value: Binding(get: { shownTime }, set: { dragTime = $0 }),
                        in: 0...max(playback.duration, 1)
                    ) { editing in
                        if !editing, let time = dragTime {
                            playback.seek(to: time)
                            dragTime = nil
                        }
                    }
                    .tint(Design.Palette.primary)
                    .accessibilityLabel("재생 위치")
                    .accessibilityValue("\(RecordingController.format(shownTime)) / \(RecordingController.format(playback.duration))")
                    .overlay { BookmarkMarkers(fractions: playback.bookmarkMarkers) }
                    .accessibilityIdentifier("playbackSlider")
                    Text(RecordingController.format(playback.duration))
                        .designText(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                HStack(spacing: Design.Spacing.sm) {
                    Button {
                        playback.skipBackward()
                    } label: {
                        Label("\(playback.skipInterval.label) 뒤로", systemImage: playback.skipInterval.symbolName(forward: false))
                    }
                    .buttonStyle(.pillSecondary)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("\(playback.skipInterval.label) 뒤로 (←)")
                    .accessibilityIdentifier("skipBackward")
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Label(playback.isPlaying ? "일시정지" : "재생", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.space, modifiers: [])
                    .help("재생 / 일시정지 (스페이스)")
                    .accessibilityIdentifier("playPause")
                    Button {
                        playback.skipForward()
                    } label: {
                        Label("\(playback.skipInterval.label) 앞으로", systemImage: playback.skipInterval.symbolName(forward: true))
                    }
                    .buttonStyle(.pillSecondary)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("\(playback.skipInterval.label) 앞으로 (→)")
                    .accessibilityIdentifier("skipForward")
                }
                HStack(spacing: Design.Spacing.sm) {
                    Button {
                        playback.addBookmarkAtCurrentTime()
                    } label: {
                        Label("지금 위치에 북마크", systemImage: "bookmark")
                    }
                    .buttonStyle(.pillSecondary)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .help("지금 위치에 북마크 추가 (⇧⌘B)")
                    .accessibilityIdentifier("addPlaybackBookmark")
                }
                if let position = playback.tourPositionText {
                    HStack(spacing: Design.Spacing.sm) {
                        Button {
                            playback.previousTourStop()
                        } label: {
                            Label("이전 북마크", systemImage: "backward.end")
                        }
                        .buttonStyle(.pillSecondary)
                        .accessibilityIdentifier("previousTourStop")
                        Text(position)
                            .designText(.captionStrong)
                            .foregroundStyle(Design.Palette.primary)
                            .monospacedDigit()
                            .accessibilityIdentifier("tourPosition")
                        Button {
                            playback.nextTourStop()
                        } label: {
                            Label("다음 북마크", systemImage: "forward.end")
                        }
                        .buttonStyle(.pillSecondary)
                        .accessibilityIdentifier("nextTourStop")
                        Button("이어 듣기 끝내기") { playback.stopBookmarkTour() }
                            .buttonStyle(.textLink)
                            .accessibilityIdentifier("stopBookmarkTour")
                    }
                } else if let current = playback.current, !current.bookmarks.isEmpty {
                    Button {
                        playback.startBookmarkTour(entries: current.sortedBookmarks.map { BookmarkEntry(bookmark: $0, recording: current) })
                    } label: {
                        Label("이 녹음 북마크만 이어 듣기", systemImage: "play.circle")
                    }
                    .buttonStyle(.pillSecondary)
                    .accessibilityIdentifier("startRecordingBookmarkTour")
                }
                if !playback.bookmarks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Design.Spacing.xs) {
                            ForEach(playback.bookmarks) { bookmark in
                                Button {
                                    playback.play(from: bookmark)
                                } label: {
                                    Label(label(for: bookmark), systemImage: "bookmark.fill")
                                }
                                .buttonStyle(.pillSecondary)
                                .accessibilityHint("이 북마크 위치부터 재생합니다")
                                .contextMenu {
                                    Button("메모 수정…") {
                                        noteText = bookmark.note
                                        editingNote = bookmark
                                    }
                                    Button("삭제…", role: .destructive) { deleting = bookmark }
                                }
                                .accessibilityIdentifier("bookmarkChip")
                            }
                        }
                    }
                    .frame(maxWidth: 480)
                }
                Picker("배속", selection: Binding(get: { playback.rate }, set: { playback.setRate($0) })) {
                    ForEach(PlaybackRate.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("ratepicker")
                Toggle("다음 녹음으로 이어서 재생", isOn: Binding(get: { playback.continuousPlayback }, set: { playback.continuousPlayback = $0 }))
                    .toggleStyle(.checkbox)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("continuousPlayback")
            }
            .padding(Design.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .background(Design.Palette.parchment)
        .overlay(alignment: .top) { Divider() }
        .alert("수업 메모", isPresented: $editingMemo) {
            TextField("예: 중간고사 범위 발표", text: $memoText)
            Button("취소", role: .cancel) {}
            Button("저장") {
                if let recording = playback.current {
                    do {
                        try manager.setMemo(memoText, for: recording)
                        memoError = nil
                    } catch {
                        memoError = manager.errorMessage ?? error.localizedDescription
                    }
                    library.reload()
                }
            }
        }
        .alert("북마크 메모", isPresented: Binding(get: { editingNote != nil }, set: { if !$0 { editingNote = nil } })) {
            TextField("메모", text: $noteText)
            Button("취소", role: .cancel) {}
            Button("저장") {
                if let bookmark = editingNote { playback.updateNote(of: bookmark, to: noteText) }
            }
        }
        .confirmationDialog(
            RecordingPlaybackGuard.confirmationTitle,
            isPresented: Binding(get: { playback.isConfirmingPlayback }, set: { if !$0 { playback.cancelPlaybackConfirmation() } }),
            titleVisibility: .visible
        ) {
            Button(RecordingPlaybackGuard.confirmButton) { playback.confirmPlaybackDuringRecording() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(RecordingPlaybackGuard.confirmationMessage)
        }
        .confirmationDialog(
            "이 북마크를 삭제할까요?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let bookmark = deleting { playback.delete(bookmark) }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var shownTime: TimeInterval { dragTime ?? playback.currentTime }

    private func label(for bookmark: Bookmark) -> String {
        let time = RecordingController.format(bookmark.time)
        return bookmark.note.isEmpty ? time : "\(time) \(bookmark.note)"
    }
}

/// 슬라이더 위에 북마크 위치를 가는 선으로 표시한다. 눌림은 받지 않는다.
private struct BookmarkMarkers: View {
    let fractions: [Double]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                Rectangle()
                    .fill(Design.Palette.primary)
                    .frame(width: 2, height: 10)
                    .position(x: proxy.size.width * fraction, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
