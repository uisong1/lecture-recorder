import LectureCore
import SwiftUI

/// 사이드바에서 고를 수 있는 곳.
enum SidebarItem: Hashable {
    case recorder
    case transcription
    case library(LibrarySelection)
}

/// 시안 01·02의 사이드바. 시스템 목록은 고른 줄을 맥의 강조색(파랑)으로 칠해서,
/// 직접 그려 고른 줄은 검정 바탕 흰 글자, 개수는 오른쪽 회색 숫자, 안 들은 녹음이 있으면 이름 옆에 작은 점이 보인다 (DESIGN.md 사이드바).
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let library: RecordingLibrary
    let transcriptionCount: Int

    var body: some View {
        // 시스템 사이드바 목록을 그대로 써서 창 위 막대 아래 위치·스크롤·클릭 영역을 맥 기본대로 맞춘다.
        // selection을 주지 않아 맥이 파랗게 칠하지 않고, 고른 줄은 직접 검정으로 그린다.
        List {
            row("녹음", icon: "record.circle", item: .recorder, id: "sidebar-recorder")
            row("전사", icon: "doc.text", item: .transcription, count: transcriptionCount, id: "sidebar-transcription")
            row("모든 녹음", icon: "waveform", item: .library(.all), count: library.count(for: .all), id: "sidebar-all")
            Color.clear.frame(height: Design.Spacing.xs).sidebarRowLayout()
            subjects
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Design.Palette.sidebar.ignoresSafeArea())
    }

    @ViewBuilder
    private var subjects: some View {
        let unplayed = library.unplayedCounts
        if SemesterGrouping.showsHeaders(library.semesterSections) {
            ForEach(library.semesterSections) { section in
                let expanded = library.isExpanded(section)
                Button {
                    library.setExpanded(!expanded, for: section)
                } label: {
                    HStack(spacing: Design.Spacing.xxs) {
                        Text(section.title)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .padding(.horizontal, Design.Spacing.xs)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sidebarRowLayout()
                .accessibilityIdentifier("sidebar-semester-\(section.title)")
                if expanded {
                    ForEach(library.subjects(in: section)) { subjectRow($0, unplayed: unplayed) }
                }
            }
        } else {
            Text("과목")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .padding(.horizontal, Design.Spacing.xs)
                .padding(.vertical, 6)
                .sidebarRowLayout()
            ForEach(library.subjects) { subjectRow($0, unplayed: unplayed) }
        }
        row("미분류", icon: "tray", item: .library(.unclassified), count: library.count(for: .unclassified), id: "sidebar-unclassified")
    }

    private func subjectRow(_ subject: Subject, unplayed: UnplayedCounts) -> some View {
        let selection = LibrarySelection.subject(subject.persistentModelID)
        let unplayedCount = unplayed.count(for: selection)
        return row(
            subject.name,
            icon: "book.closed",
            item: .library(selection),
            count: library.count(for: selection),
            showsUnplayedDot: UnplayedBadge.showsDot(count: unplayedCount),
            id: "sidebar-subject-\(subject.name)"
        )
        .accessibilityLabel(UnplayedBadge.accessibilityLabel(name: subject.name, count: unplayedCount))
    }

    private func row(_ title: String, icon: String, item: SidebarItem, count: Int? = nil, showsUnplayedDot: Bool = false, id: String) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Design.Palette.onPrimary : Design.Palette.ink)
                Text(title)
                    .designText(isSelected ? .captionStrong : .caption)
                    .foregroundStyle(isSelected ? Design.Palette.onPrimary : Design.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsUnplayedDot {
                    // 녹음 목록의 안 들음 점과 같은 크기·색(검정, 고른 줄에서는 흰색).
                    Circle()
                        .fill(isSelected ? Design.Palette.onPrimary : Design.Palette.ink)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: Design.Spacing.xxs)
                if let count, count > 0 {
                    Text("\(count)")
                        .designText(.finePrint)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Design.Palette.onPrimary.opacity(0.7) : Design.Palette.inkMuted)
                }
            }
            .padding(.horizontal, Design.Spacing.xs)
            .frame(height: 32)
            .background(isSelected ? Design.Palette.ink : Color.clear, in: RoundedRectangle(cornerRadius: Design.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRowLayout()
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// 사이드바 목록의 한 줄: 기본 여백·구분선·바탕을 없애고 줄 높이는 내용대로.
    func sidebarRowLayout() -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
