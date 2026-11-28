import LectureCore
import SwiftUI

/// 사이드바 "전사" 탭. 녹음이 끝난 뒤 맥 안에서 Qwen3-ASR로 녹음을 글로 바꾼다 (시안 06).
struct TranscriptionView: View {
    let center: TranscriptionCenter
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary

    /// 결과를 여는 녹음의 고정 id(`transcriptionKey`). 있으면 목록 대신 전사 결과를 보여 준다.
    @State private var openedID: String?
    /// 대기열 카드 폭. 넓으면 상태를 제목 아래 한 줄로(시안 B), 좁으면 세 칸 고정(시안 A)으로 보인다.
    @State private var queueWidth: CGFloat = 0

    var body: some View {
        Group {
            if let id = openedID, let recording = center.recording(for: id), let transcript = recording.transcript {
                TranscriptDetailView(recording: recording, transcript: transcript, subtitle: center.subtitle(for: recording), playback: playback) {
                    openedID = nil
                } onRetranscribe: {
                    openedID = nil
                    // 지금 결과는 새 결과를 저장할 때 바뀐다. 멈추거나 실패해도 남는다.
                    center.retranscribe(recording)
                }
            } else {
                overview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Palette.parchment)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.current != nil && !playback.isPanelHidden { PlaybackPanel(playback: playback, manager: manager, library: library) }
        }
        .task { center.reload() }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                header
                if center.toolStatus != .ready { toolNotice }
                if let message = center.errorMessage { notice(message, systemImage: "exclamationmark.triangle") }
                if let reason = center.queue.suspendReason { notice(reason, systemImage: "pause.circle") }
                if !center.queue.entries.isEmpty {
                    progressCard
                    section("진행 중 · 대기") { queueRows }
                }
                if !center.idleCandidates.isEmpty {
                    if center.isSelecting { selectionBar }
                    section("전사 안 됨") { candidateRows }
                }
                if !center.transcribed.isEmpty {
                    section("전사 완료") { transcribedRows }
                }
                if center.candidates.isEmpty && center.transcribed.isEmpty {
                    ContentUnavailableView("전사할 녹음이 없어요", systemImage: "doc.text", description: Text("녹음이 끝나면 여기서 글로 바꿀 수 있어요."))
                        .padding(.top, Design.Spacing.xxl)
                }
            }
            .screenColumn()
        }
    }

    // MARK: 머리

    private var header: some View {
        ScreenHeader(
            "전사",
            subtitle: "전사 안 된 녹음 \(center.candidates.count)개 · \(Self.approx(center.candidatesDuration)) · 맥에서 직접 글로 바꿔요"
        ) {
            if !center.idleCandidates.isEmpty {
                Button {
                    center.isSelecting.toggle()
                } label: {
                    Label(center.isSelecting ? "고르기 취소" : "골라서 전사", systemImage: "checkmark.circle")
                }
                .buttonStyle(.pillSecondaryCompact)
                .accessibilityIdentifier("transcribeSelectMode")
                Button {
                    center.transcribeAll()
                } label: {
                    Label("전체 전사 (\(center.idleCandidates.count))", systemImage: "doc.text")
                }
                .buttonStyle(.pillCompact)
                .accessibilityIdentifier("transcribeAll")
            }
        }
    }

    // MARK: 도구 안내

    @ViewBuilder
    private var toolNotice: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: toolIcon)
                .foregroundStyle(Design.Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(toolTitle)
                    .designText(.bodyStrong)
                    .foregroundStyle(Design.Palette.ink)
                Text(toolDetail)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch center.toolStatus {
            case .notInstalled, .failed:
                Button("설치") { Task { await center.installTool() } }
                    .buttonStyle(.pillCompact)
                    .accessibilityIdentifier("installTranscriptionTool")
            case .helperMissing:
                Button("다시 확인") { Task { await center.checkTool() } }
                    .buttonStyle(.pillSecondaryCompact)
            case .installing, .checking:
                ProgressView().controlSize(.small)
            case .ready:
                EmptyView()
            }
        }
        .designCard(padding: Design.Spacing.md, radius: Design.Radius.group)
        .accessibilityIdentifier("transcriptionToolNotice")
    }

    private var toolIcon: String {
        switch center.toolStatus {
        case .failed, .helperMissing: "exclamationmark.triangle"
        default: "arrow.down.circle"
        }
    }

    private var toolTitle: String {
        switch center.toolStatus {
        case .checking: "전사 도구를 확인하고 있어요"
        case .ready: ""
        case .notInstalled: "처음 한 번 전사 도구를 설치해야 해요"
        case .helperMissing: "전사 도우미가 없어요"
        case .installing: "전사 도구를 설치하고 있어요 (몇 분 걸려요)"
        case .failed: "전사 도구에 문제가 있어요"
        }
    }

    private var toolDetail: String {
        switch center.toolStatus {
        case .checking, .ready: ""
        case .notInstalled, .installing: "Python 가상환경에 mlx-audio를 설치해요. 첫 전사 때 Qwen3-ASR 모델(약 2GB)을 한 번 받아요."
        case .helperMissing: TranscriptionHelperScript.missingMessage
        case .failed(let message): message
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .designText(.captionStrong)
            .foregroundStyle(Design.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .designCard(padding: Design.Spacing.sm, radius: Design.Radius.md)
    }

    // MARK: 진행

    private var progressCard: some View {
        let queue = center.queue
        let total = queue.entries.count
        let remaining = Self.approx(queue.estimatedRemainingSeconds)
        let detail = queue.isPaused
            ? "멈췄어요 · 다시 시작을 누르면 이어서 해요"
            : "동시에 \(queue.maxConcurrent)개씩 전사하고 있어요 · 전체 \(remaining) 남음"
        return VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(total)개 중 \(queue.doneCount)개 완료")
                        .designText(.bodyStrong)
                        .foregroundStyle(Design.Palette.ink)
                    Text(detail)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
                Spacer()
                if queue.entries.contains(where: \.isFinished) {
                    Button("끝난 것 치우기") { queue.clearFinished() }
                        .buttonStyle(.pillSecondaryCompact)
                }
                if queue.isActive {
                    Button {
                        if queue.isPaused { queue.resumeAll() } else { queue.pauseAll() }
                    } label: {
                        Label(queue.isPaused ? "다시 시작" : "모두 멈춤", systemImage: queue.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.pillSecondaryCompact)
                    .accessibilityIdentifier("transcriptionPauseAll")
                }
            }
            HStack(spacing: Design.Spacing.sm) {
                DesignProgressBar(value: queue.overallProgress, height: 4)
                Text("\(Int((queue.overallProgress * 100).rounded()))%")
                    .designText(.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.ink)
            }
        }
        .designCard(padding: Design.Spacing.md, radius: Design.Radius.lg)
        .accessibilityIdentifier("transcriptionProgress")
    }

    private var queueRows: some View {
        let waiting = center.queue.entries.filter { $0.state == .waiting }.map(\.id)
        let isWide = queueWidth >= TranscriptionQueueRow.wideWidth
        return VStack(spacing: 0) {
            ForEach(center.queue.entries) { entry in
                TranscriptionQueueRow(
                    entry: entry,
                    waitingPosition: (waiting.firstIndex(of: entry.id) ?? 0) + 1,
                    isWide: isWide,
                    queue: center.queue,
                    onOpen: { openedID = entry.id }
                )
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { queueWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in queueWidth = width }
            }
        }
    }

    // MARK: 전사 안 됨

    private var selectionBar: some View {
        HStack(spacing: Design.Spacing.sm) {
            Text("\(center.selection.count)개 선택됨 · \(Self.approx(center.selectedDuration))")
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.onPrimary)
            Spacer()
            Button("모두 선택") { center.selectAll() }
                .buttonStyle(.pillDark)
            Button("취소") { center.isSelecting = false }
                .buttonStyle(.pillDark)
            Button {
                center.transcribeSelected()
            } label: {
                Label("선택한 \(center.selection.count)개 전사", systemImage: "doc.text")
            }
            .buttonStyle(.pillSecondaryCompact)
            .disabled(center.selection.isEmpty)
            .accessibilityIdentifier("transcribeSelected")
        }
        .padding(.vertical, Design.Spacing.xs)
        .padding(.horizontal, Design.Spacing.md)
        .background(Design.Palette.ink, in: RoundedRectangle(cornerRadius: Design.Radius.group))
    }

    private var candidateRows: some View {
        ForEach(center.idleCandidates) { recording in
            if center.isSelecting {
                Button {
                    center.toggleSelection(recording)
                } label: {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: center.selection.contains(recording.transcriptionKey) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Palette.ink)
                        rowFrame(title: recording.title, subtitle: center.subtitle(for: recording)) {
                            Text("전사 안 됨")
                                .designText(.caption)
                                .foregroundStyle(Design.Palette.inkMuted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                rowFrame(title: recording.title, subtitle: center.subtitle(for: recording)) {
                    Button {
                        center.transcribe(recording)
                    } label: {
                        Label("전사", systemImage: "doc.text")
                    }
                    .buttonStyle(.pillSecondaryCompact)
                }
            }
        }
    }

    private var transcribedRows: some View {
        ForEach(center.transcribed) { recording in
            rowFrame(title: recording.title, subtitle: center.subtitle(for: recording)) {
                Text("문장 \(recording.transcript?.segments.count ?? 0)개")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                Button("보기") { openedID = recording.transcriptionKey }
                    .buttonStyle(.pillSecondaryCompact)
                    .accessibilityIdentifier("openTranscript-\(recording.title)")
            }
        }
    }

    // MARK: 공통

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(title)
                .designText(.captionStrong)
                .foregroundStyle(Design.Palette.inkMuted)
                .padding(.leading, Design.Spacing.xxs)
            VStack(spacing: 0) {
                content()
            }
            .designCard(padding: 0, radius: Design.Radius.group)
        }
    }

    private func rowFrame<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .designText(.bodyStrong)
                        .foregroundStyle(Design.Palette.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: Design.Spacing.sm)
                trailing()
            }
            .padding(.vertical, Design.Spacing.sm)
            .padding(.horizontal, Design.Spacing.md)
            Rectangle().fill(Design.Palette.fill).frame(height: 1)
        }
    }

    /// "약 21분", "약 3시간 47분"
    static func approx(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "약 \(minutes)분" }
        let rest = minutes % 60
        return rest == 0 ? "약 \(minutes / 60)시간" : "약 \(minutes / 60)시간 \(rest)분"
    }
}

/// 회색 바탕 위 검정 막대 (DESIGN.md 진행 막대).
struct DesignProgressBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Design.Palette.fill)
                Capsule().fill(Design.Palette.ink)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}
