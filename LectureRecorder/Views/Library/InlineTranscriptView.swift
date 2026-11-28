import AppKit
import LectureCore
import SwiftUI

/// 녹음 줄 오른쪽 ⌄로 펼치는 전사본 (시안 transcript-expand B, 2026-11-29 사용자 선택).
/// 칸 안에서 전체를 스크롤해 읽고, 찾기·복사, 문장을 누르면 그 부분부터 재생한다. 재생 중인 문장은 굵게 따라간다.
struct InlineTranscriptView: View {
    let recording: Recording
    let transcript: Transcript
    let playback: PlaybackController
    /// "크게 보기": 지금의 전사 화면(텍스트로 저장 등)을 연다.
    let onOpenFull: () -> Void

    @State private var query = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            toolbar
            segmentList
            HStack {
                Text(copied ? "전사 내용을 복사했어요." : "문장을 누르면 그 부분부터 재생돼요 · \(transcript.segments.count)문장")
                    .designText(.finePrint)
                    .foregroundStyle(Design.Palette.inkMuted)
                Spacer()
                Button(action: onOpenFull) {
                    HStack(spacing: 2) {
                        Text("크게 보기")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .designText(.captionStrong)
                    .foregroundStyle(Design.Palette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openFullTranscript")
            }
        }
        .padding(Design.Spacing.sm)
        .background(Design.Palette.parchment, in: RoundedRectangle(cornerRadius: Design.Radius.md))
        .accessibilityIdentifier("inlineTranscript")
    }

    private var toolbar: some View {
        HStack(spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Palette.inkFaint)
                TextField("전사본에서 찾기", text: $query)
                    .textFieldStyle(.plain)
                    .designText(.caption)
                    .accessibilityIdentifier("inlineTranscriptSearch")
                if !query.isEmpty {
                    Text("\(matches.count)개")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, Design.Spacing.sm)
            .background(Design.Palette.canvas, in: Capsule())
            .overlay(Capsule().strokeBorder(Design.Palette.border, lineWidth: 1))
            Button("복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript.plainText, forType: .string)
                copied = true
            }
            .buttonStyle(.pillSecondaryCompact)
            .accessibilityIdentifier("inlineTranscriptCopy")
        }
    }

    private var matches: [Int] { transcript.matches(query) }

    private var visibleIndices: [Int] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? Array(transcript.segments.indices) : matches
    }

    private var segmentList: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let current = playback.current === recording ? transcript.segmentIndex(at: playback.currentTime) : nil
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleIndices, id: \.self) { index in
                            segmentRow(index, isCurrent: index == current)
                                .id(index)
                        }
                        if visibleIndices.isEmpty {
                            Text(query.isEmpty ? "전사된 문장이 없어요." : "찾는 말이 없어요.")
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                                .padding(.vertical, Design.Spacing.xs)
                        }
                    }
                }
                .frame(height: 220)
                .onChange(of: current) { _, index in
                    guard let index, playback.isPlaying, query.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
    }

    private func segmentRow(_ index: Int, isCurrent: Bool) -> some View {
        let segment = transcript.segments[index]
        return Button {
            if playback.current !== recording { playback.select(recording) }
            playback.seek(to: segment.start)
            if !playback.isPlaying { playback.play() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.sm) {
                Text(Transcript.timestamp(segment.start))
                    .designText(isCurrent ? .captionStrong : .caption)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Design.Palette.ink : Design.Palette.inkMuted)
                    .frame(width: 48, alignment: .leading)
                Text(segment.text)
                    .designText(isCurrent ? .captionStrong : .caption)
                    .foregroundStyle(Design.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Transcript.timestamp(segment.start)) \(segment.text)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
