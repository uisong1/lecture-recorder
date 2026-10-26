import LectureCore
import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    private enum SidebarItem: Hashable {
        case recorder
        case library(LibrarySelection)
    }

    @State private var sidebar: SidebarItem? = .recorder

    private func subjectRow(_ subject: Subject) -> some View {
        Label(subject.name, systemImage: "book.closed")
            .badge(dependencies.library.count(for: .subject(subject.persistentModelID)))
            .tag(SidebarItem.library(.subject(subject.persistentModelID)))
            .accessibilityIdentifier("sidebar-subject-\(subject.name)")
    }

    var body: some View {
        NavigationSplitView {
            // 접힌 묶음 안의 과목을 고른 채로도 선택이 풀리지 않게, 목록이 보내는 "선택 없음"은 받지 않는다.
            List(selection: Binding(get: { sidebar }, set: { if let item = $0 { sidebar = item } })) {
                Label("녹음", systemImage: "record.circle")
                    .tag(SidebarItem.recorder)
                    .accessibilityIdentifier("sidebar-recorder")
                Label("모든 녹음", systemImage: "waveform")
                    .badge(dependencies.library.count(for: .all))
                    .tag(SidebarItem.library(.all))
                    .accessibilityIdentifier("sidebar-all")
                Section("과목") {
                    let library = dependencies.library
                    if SemesterGrouping.showsHeaders(library.semesterSections) {
                        ForEach(library.semesterSections) { section in
                            DisclosureGroup(isExpanded: Binding(
                                get: { library.isExpanded(section) },
                                set: { library.setExpanded($0, for: section) }
                            )) {
                                ForEach(library.subjects(in: section)) { subject in subjectRow(subject) }
                            } label: {
                                Text(section.title)
                                    .designText(.captionStrong)
                                    .foregroundStyle(Design.Palette.inkMuted)
                                    .accessibilityIdentifier("sidebar-semester-\(section.title)")
                            }
                        }
                    } else {
                        ForEach(library.subjects) { subject in subjectRow(subject) }
                    }
                    Label("미분류", systemImage: "tray")
                        .badge(dependencies.library.count(for: .unclassified))
                        .tag(SidebarItem.library(.unclassified))
                        .accessibilityIdentifier("sidebar-unclassified")
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if let startupError = dependencies.startupError {
                    Label(startupError, systemImage: "exclamationmark.triangle")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.danger)
                        .padding(Design.Spacing.xs)
                }
                if let notice = dependencies.recoveryNotice {
                    Label(notice, systemImage: "arrow.counterclockwise")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.primary)
                        .padding(Design.Spacing.xs)
                        .accessibilityIdentifier("recoveryNotice")
                }
                switch sidebar {
                case .library:
                    RecordingListView(library: dependencies.library, playback: dependencies.playback, manager: dependencies.manager)
                default:
                    RecordingView(recording: dependencies.recording, playback: dependencies.playback, manager: dependencies.manager, library: dependencies.library, showsFirstRunGuide: dependencies.subjects.needsFirstRunGuide)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 440)
        .onChange(of: sidebar) { _, item in
            dependencies.library.reload()
            if case .library(let selection) = item {
                dependencies.library.select(selection)
            }
        }
        .onChange(of: dependencies.recording.lastSaved) {
            dependencies.library.reload()
        }
        .toolbar {
            SettingsLink {
                Label("과목과 시간표 설정", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")
        }
    }
}
