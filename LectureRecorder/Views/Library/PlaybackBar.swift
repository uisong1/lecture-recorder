import LectureCore
import SwiftUI

/// 불러온 녹음의 재생 위치 슬라이더와 배속 선택. 뷰는 컨트롤러 상태만 보여준다.
struct PlaybackBar: View {
    let playback: PlaybackController
    @State private var dragTime: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let _ = playback.refresh()
            VStack(spacing: Design.Spacing.xs) {
                Text(playback.current?.title ?? "")
                    .designText(.captionStrong)
                    .foregroundStyle(Design.Palette.ink)
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
                    .overlay { BookmarkMarkers(fractions: playback.bookmarkMarkers) }
                    .accessibilityIdentifier("playbackSlider")
                    Text(RecordingController.format(playback.duration))
                        .designText(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Design.Palette.inkMuted)
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
                                .accessibilityIdentifier("bookmarkChip")
                            }
                        }
                    }
                    .frame(maxWidth: 480)
                }
                Picker("배속", selection: Binding(get: { playback.rate }, set: { playback.setRate($0) })) {
                    ForEach(PlaybackRate.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityIdentifier("ratepicker")
            }
            .padding(Design.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .background(Design.Palette.parchment)
        .overlay(alignment: .top) { Divider() }
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
    }
}
