import AppKit
import LectureCore
import SwiftUI
import UniformTypeIdentifiers

/// 녹음 하나의 전사 결과. 문장을 누르면 그 부분부터 재생하고, 지금 재생 중인 문장은 검정으로 따라가요 (시안 06-4).
struct TranscriptDetailView: View {
    let recording: Recording
    let transcript: Transcript
    let subtitle: String
    let playback: PlaybackController
    let onClose: () -> Void
    /// 없으면 "다시 전사" 메뉴를 숨긴다.
    let onRetranscribe: (() -> Void)?

    @State private var query = ""
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            header
            toolbar
            if let notice {
                Text(notice)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            segmentList
            Text("문장을 누르면 그 부분부터 재생돼요. 지금 재생 중인 문장은 검정으로 따라가요.")
                .designText(.finePrint)
                .foregroundStyle(Design.Palette.inkMuted)
        }
        .padding(28)
        .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.iconPlain)
            .help("전사 목록으로")
            .accessibilityIdentifier("closeTranscript")
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(recording.title)
                    .designText(.displayLg)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(2)
                Text("\(subtitle) · 문장 \(transcript.segments.count)개")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            Spacer()
            if let onRetranscribe {
                Menu {
                    Button("다시 전사", action: onRetranscribe)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Design.Palette.inkFaint)
                TextField("전사 내용에서 찾기", text: $query)
                    .textFieldStyle(.plain)
                    .designText(.caption)
                    .accessibilityIdentifier("transcriptSearch")
                if !query.isEmpty {
                    Text("\(matches.count)개")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Design.Spacing.sm)
            .background(Design.Palette.canvas, in: Capsule())
            .overlay(Capsule().strokeBorder(Design.Palette.border, lineWidth: 1))
            Button {
                saveText()
            } label: {
                Label("텍스트로 저장", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.pillSecondaryCompact)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript.plainText, forType: .string)
                notice = "전사 내용을 복사했어요."
            } label: {
                Label("복사", systemImage: "doc.on.doc")
            }
            .buttonStyle(.pillSecondaryCompact)
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
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleIndices, id: \.self) { index in
                            segmentRow(index, isCurrent: index == current)
                                .id(index)
                        }
                        if visibleIndices.isEmpty {
                            Text(query.isEmpty ? "전사된 문장이 없어요." : "찾는 말이 없어요.")
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                                .padding(Design.Spacing.md)
                        }
                    }
                    .padding(Design.Spacing.xs)
                }
                .onChange(of: current) { _, index in
                    guard let index, playback.isPlaying, query.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
        .designCard(padding: 0, radius: Design.Radius.lg)
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
                    .designText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Design.Palette.onPrimary : Design.Palette.inkMuted)
                    .frame(width: 56, alignment: .leading)
                Text(segment.text)
                    .designText(.body)
                    .foregroundStyle(isCurrent ? Design.Palette.onPrimary : Design.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Design.Spacing.sm)
            .background(isCurrent ? Design.Palette.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Transcript.timestamp(segment.start)) \(segment.text)")
    }

    private func saveText() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(recording.title) 전사.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(transcript.plainText.utf8).write(to: url, options: .atomic)
            notice = "텍스트로 저장했어요."
        } catch {
            Log.storage.error("전사 텍스트 저장 실패: \(error.localizedDescription, privacy: .public)")
            notice = "저장하지 못했어요: \(error.localizedDescription)"
        }
    }
}
