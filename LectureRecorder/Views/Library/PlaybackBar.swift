import LectureCore
import AppKit
import SwiftUI

/// 불러온 녹음의 재생 위치 슬라이더와 배속 선택. 뷰는 컨트롤러 상태만 보여준다.
struct PlaybackBar: View {
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary
    @State private var editingMemo = false
    @State private var memoText = ""
    @State private var dragTime: TimeInterval?
    /// 수업 메모 저장에 실패했을 때의 문구.
    @State private var memoError: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
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
        // 재생이 끝났는지·다음 녹음으로 넘길지는 화면을 그리는 도중이 아니라 별도 루프에서 확인한다.
        // 그리는 도중에 상태를 바꾸면 화면이 다시 그려지길 반복하거나, 다음 파일 불러오기가 그리기를 막을 수 있다.
        .task {
            while !Task.isCancelled {
                playback.refresh()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
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
    }

    private var shownTime: TimeInterval { dragTime ?? playback.currentTime }
}

/// 재생 바를 감싸는 아래 패널. 위쪽 손잡이를 끌어 높이를 바꾸고(더블클릭하면 자동 높이), 오른쪽 위 버튼으로 닫는다.
/// 닫으면 재생도 멈추고, 다시 재생하거나 녹음을 고르면 다시 나타난다. 녹음에는 영향이 없다.
struct PlaybackPanel: View {
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary

    /// 사용자가 정한 높이. 0이면 내용에 맞춘다.
    @AppStorage("playbackPanelHeight") private var storedHeight: Double = 0
    @State private var naturalHeight: Double = 0
    @State private var dragStart: Double?

    private let handleHeight: Double = 14

    private var currentHeight: Double { storedHeight > 0 ? storedHeight : max(naturalHeight, PlaybackPanelLayout.minHeight) }

    var body: some View {
        VStack(spacing: 0) {
            handle
            if storedHeight > 0 {
                ScrollView {
                    PlaybackBar(playback: playback, manager: manager, library: library)
                }
                .frame(height: PlaybackPanelLayout.clamp(storedHeight) - handleHeight)
            } else {
                PlaybackBar(playback: playback, manager: manager, library: library)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                        }
                    )
                    .onPreferenceChange(PanelHeightKey.self) { naturalHeight = Double($0) }
            }
        }
        .background(Design.Palette.parchment)
        .overlay(alignment: .topTrailing) {
            Button {
                playback.closePanel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            .buttonStyle(.plain)
            .padding(Design.Spacing.xs)
            .help("재생 패널 닫기 (재생도 멈춥니다)")
            .accessibilityLabel("재생 패널 닫기")
            .accessibilityIdentifier("closePlaybackPanel")
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Design.Palette.inkMuted.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: handleHeight)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? currentHeight
                        dragStart = start
                        storedHeight = PlaybackPanelLayout.height(start: start, dragUp: -value.translation.height)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { storedHeight = 0 }
            .help("끌어서 높이 조절, 더블클릭하면 자동 높이")
            .accessibilityLabel("재생 패널 높이 조절")
            .accessibilityIdentifier("playbackPanelHandle")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
