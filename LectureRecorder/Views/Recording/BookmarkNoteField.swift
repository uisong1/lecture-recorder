import LectureCore
import SwiftUI

/// ⌘B로 북마크를 찍으면 잠깐 나타나는 "방금 북마크" 메모 입력칸.
/// 포커스를 가져가지 않는다. 칸을 누르거나 ⌘⇧N을 눌러야 입력할 수 있고, 아무것도 안 하면 8초 뒤 사라진다.
struct BookmarkNoteField: View {
    let recording: RecordingController

    private static let visibleSeconds: Double = 8

    @State private var targetIndex: Int?
    @State private var note = ""
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if targetIndex != nil {
                TextField("방금 북마크 메모", text: $note)
                    .textFieldStyle(.plain)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.ink)
                    .focused($isFocused)
                    .padding(.horizontal, Design.Spacing.sm)
                    .padding(.vertical, Design.Spacing.xs)
                    .frame(maxWidth: 280)
                    .background(Design.Palette.parchment, in: RoundedRectangle(cornerRadius: Design.Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.sm).stroke(Design.Palette.hairline))
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        // 입력 중에는 사라지지 않게 타이머를 멈추고, 입력이 끝나면 다시 시작한다.
                        if focused { hideTask?.cancel() } else if targetIndex != nil { scheduleHide() }
                    }
                    .accessibilityIdentifier("bookmarkNoteField")
            }
            // 입력칸이 없어도 ⌘⇧N이 먹도록 보이지 않는 버튼으로 둔다.
            Button("") { isFocused = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: recording.bookmarkTimes.count) { _, count in
            guard count > 0 else { return hide() }
            // 새 북마크를 찍으면 입력칸은 그 북마크를 가리킨다.
            targetIndex = count - 1
            note = ""
            scheduleHide()
        }
    }

    private func commit() {
        if let targetIndex {
            recording.setBookmarkNote(note, at: targetIndex)
        }
        hide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        targetIndex = nil
        note = ""
        isFocused = false
    }
}
