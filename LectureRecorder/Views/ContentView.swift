import LectureCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let dependencies: AppDependencies

    @State private var sidebar: SidebarItem? = .recorder
    @State private var isPickingMedia = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $sidebar,
                library: dependencies.library,
                transcriptionCount: dependencies.transcription.candidates.count
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
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
                if let release = dependencies.appUpdate.availableRelease {
                    HStack(spacing: Design.Spacing.xs) {
                        Label("새 버전이 있습니다 (빌드 \(release.build))", systemImage: "arrow.down.circle")
                            .designText(.caption)
                            .foregroundStyle(Design.Palette.primary)
                        Button {
                openWindow(id: LMSBackfillWindow.windowID)
            } label: {
                Label("녹음 없는 수업일", systemImage: "calendar.badge.exclamationmark")
            }
            .help("녹음이 빠진 수업일을 LMS 강의 영상의 소리로 채웁니다 (개인 복습용)")
            .accessibilityIdentifier("openBackfill")
            SettingsLink { Text("설정에서 업데이트") }
                            .buttonStyle(.textLink)
                    }
                    .padding(Design.Spacing.xs)
                    .accessibilityIdentifier("updateNotice")
                }
                switch sidebar {
                case .transcription:
                    TranscriptionView(center: dependencies.transcription, playback: dependencies.playback, manager: dependencies.manager, library: dependencies.library)
                case .library:
                    RecordingListView(library: dependencies.library, playback: dependencies.playback, manager: dependencies.manager, storageHealth: dependencies.storageHealth)
                default:
                    RecordingView(recording: dependencies.recording, playback: dependencies.playback, manager: dependencies.manager, library: dependencies.library, showsFirstRunGuide: dependencies.subjects.needsFirstRunGuide)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 440)
        // 시안처럼 창 위 막대에는 제목 없이 아이콘만 둔다. 화면 제목은 각 화면 안에 크게 보인다.
        .navigationTitle("")
        .onChange(of: sidebar) { _, item in
            dependencies.library.reload()
            if case .library(let selection) = item {
                dependencies.library.select(selection)
            }
        }
        .onChange(of: dependencies.recording.lastSaved) {
            dependencies.library.reload()
            dependencies.transcription.reload()
        }
        .dropDestination(for: URL.self) { urls, _ in
            dependencies.mediaImport.begin(urls: urls.filter(\.isFileURL))
            return true
        }
        .fileImporter(isPresented: $isPickingMedia, allowedContentTypes: [.mpeg4Movie, .mpeg4Audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): dependencies.mediaImport.begin(urls: urls)
            case .failure(let error): Log.storage.error("가져올 파일 선택 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        .sheet(isPresented: Binding(get: { dependencies.mediaImport.isPresented }, set: { if !$0 { dependencies.mediaImport.close() } })) {
            MediaImportSheet(model: dependencies.mediaImport, subjects: dependencies.subjects)
        }
        .toolbar {
            Button {
                isPickingMedia = true
            } label: {
                Label("mp4·m4a 가져오기", systemImage: "square.and.arrow.down")
            }
            .help("mp4 영상이나 m4a 소리 파일을 끌어다 놓거나 골라서 녹음 목록에 넣습니다")
            .accessibilityIdentifier("importMedia")
            Button {
                openWindow(id: LMSBrowserWindow.windowID)
            } label: {
                Label("LMS 영상 가져오기", systemImage: "graduationcap")
            }
            .help("LMS에 올라온 보강·대체 수업 영상을 가져옵니다 (개인 복습용)")
            .accessibilityIdentifier("openLMS")
            SettingsLink {
                Label("과목과 시간표 설정", systemImage: "gearshape")
            }
            .accessibilityIdentifier("openSettings")
        }
    }
}
