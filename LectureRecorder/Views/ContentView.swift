import LectureCore
import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    private enum SidebarItem: Hashable {
        case recorder
        case library(LibrarySelection)
    }

    @State private var sidebar: SidebarItem? = .recorder

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Label("녹음", systemImage: "record.circle")
                    .tag(SidebarItem.recorder)
                    .accessibilityIdentifier("sidebar-recorder")
                Section("과목") {
                    ForEach(dependencies.library.subjects) { subject in
                        Label(subject.name, systemImage: "book.closed")
                            .badge(dependencies.library.count(for: .subject(subject.persistentModelID)))
                            .tag(SidebarItem.library(.subject(subject.persistentModelID)))
                            .accessibilityIdentifier("sidebar-subject-\(subject.name)")
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
                        .padding(8)
                }
                if let notice = dependencies.recoveryNotice {
                    Label(notice, systemImage: "arrow.counterclockwise")
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.primary)
                        .padding(8)
                        .accessibilityIdentifier("recoveryNotice")
                }
                switch sidebar {
                case .library:
                    RecordingListView(library: dependencies.library, playback: dependencies.playback, manager: dependencies.manager)
                default:
                    RecordingView(recording: dependencies.recording, playback: dependencies.playback, manager: dependencies.manager, showsFirstRunGuide: dependencies.subjects.needsFirstRunGuide)
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
