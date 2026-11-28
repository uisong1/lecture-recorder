import LectureCore
import SwiftUI

/// 사이드바에서 고를 수 있는 곳.
enum SidebarItem: Hashable {
    case recorder
    case transcription
    case library(LibrarySelection)
}

/// 시안 01·02의 사이드바. 시스템 목록은 고른 줄을 맥의 강조색(파랑)으로 칠해서,
/// 직접 그려 고른 줄은 검정 바탕 흰 글자, 개수는 오른쪽 회색 숫자, 안 들은 개수는 "새 2"로 보인다 (DESIGN.md 사이드바).
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let library: RecordingLibrary
    let transcriptionCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row("녹음", icon: "record.circle", item: .recorder, id: "sidebar-recorder")
                row("전사", icon: "doc.text", item: .transcription, count: transcriptionCount, id: "sidebar-transcription")
                row("모든 녹음", icon: "waveform", item: .library(.all), count: library.count(for: .all), id: "sidebar-all")
                subjects
                    .padding(.top, Design.Spacing.sm)
            }
            .padding(.horizontal, Design.Spacing.xs)
            .padding(.vertical, Design.Spacing.xs)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            badge: UnplayedBadge.text(count: unplayedCount),
            id: "sidebar-subject-\(subject.name)"
        )
        .accessibilityLabel(UnplayedBadge.accessibilityLabel(name: subject.name, count: unplayedCount))
    }

    private func row(_ title: String, icon: String, item: SidebarItem, count: Int? = nil, badge: String? = nil, id: String) -> some View {
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
                if let badge {
                    Text(badge)
                        .font(Design.font(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? Design.Palette.onPrimary : Design.Palette.ink)
                        .fixedSize()
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
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
