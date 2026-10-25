import LectureCore
import SwiftUI

/// 고른 분류의 북마크를 모아 보여준다. 누르면 그 녹음의 그 시점부터 재생한다.
struct BookmarkOverviewView: View {
    let library: RecordingLibrary
    let playback: PlaybackController

    var body: some View {
        let entries = library.bookmarkEntries
        if entries.isEmpty {
            if library.filter.isActive {
                ContentUnavailableView("조건에 맞는 북마크가 없습니다", systemImage: "magnifyingglass", description: Text("검색어나 기간을 바꿔 보세요. 메모와 녹음 제목을 찾습니다."))
                    .accessibilityIdentifier("noMatchingBookmarks")
            } else {
                ContentUnavailableView("북마크가 없습니다", systemImage: "bookmark", description: Text("녹음 중이나 재생 중에 북마크를 찍으면 여기에 모입니다."))
                    .accessibilityIdentifier("emptyBookmarks")
            }
        } else {
            VStack(spacing: 0) {
            HStack {
                Button {
                    playback.startBookmarkTour(entries: entries)
                } label: {
                    Label("북마크만 이어 듣기", systemImage: "play.circle")
                }
                .buttonStyle(.pillSecondary)
                .accessibilityIdentifier("startBookmarkTour")
                Spacer()
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.xs)
            List(entries) { entry in
                Button {
                    playback.select(entry.recording)
                    playback.play(from: entry.bookmark)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.md) {
                        Text(RecordingController.format(entry.bookmark.time))
                            .designText(.captionStrong)
                            .foregroundStyle(Design.Palette.primary)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.bookmark.note.isEmpty ? "메모 없음" : entry.bookmark.note)
                                .designText(.bodyStrong)
                                .foregroundStyle(entry.bookmark.note.isEmpty ? Design.Palette.inkMuted : Design.Palette.ink)
                            Text(subtitle(for: entry))
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("이 시점부터 재생합니다")
                .accessibilityIdentifier("bookmarkOverviewRow")
            }
            }
        }
    }

    private func subtitle(for entry: BookmarkEntry) -> String {
        let date = entry.recording.startedAt.formatted(date: .abbreviated, time: .shortened)
        return library.showsSubjectName ? "\(entry.recording.title) · \(library.subjectName(of: entry.recording)) · \(date)" : "\(entry.recording.title) · \(date)"
    }
}
