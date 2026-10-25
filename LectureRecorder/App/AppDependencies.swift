import LectureCore
import SwiftData
import SwiftUI

/// 앱 전체에서 함께 쓰는 저장소와 뷰모델을 한곳에서 만든다.
@MainActor
final class AppDependencies {
    /// UI 테스트에서는 디스크에 남기지 않고, 마이크 대신 시뮬레이션 녹음기를 쓴다.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")

    let container: ModelContainer
    /// 저장소나 녹음 폴더를 열지 못해 임시로 대신 실행 중이면 그 이유.
    let startupError: String?
    let subjects: SubjectManager
    let schedule: ScheduleManager
    let recording: RecordingController
    let playback: PlaybackController

    init() {
        var problems: [String] = []
        let container = Self.makeContainer(problems: &problems)
        let storage = RecordingStorage(root: Self.makeRecordingsRoot(problems: &problems))

        self.container = container
        subjects = SubjectManager(context: container.mainContext)
        schedule = ScheduleManager(context: container.mainContext)
        if Self.isUITesting {
            recording = RecordingController(
                context: container.mainContext,
                recorder: SimulatedAudioRecorder(),
                storage: storage,
                permission: GrantedMicrophonePermission()
            )
        } else {
            recording = RecordingController(
                context: container.mainContext,
                recorder: SystemAudioRecorder(),
                storage: storage,
                permission: SystemMicrophonePermission()
            )
        }
        playback = PlaybackController(player: SystemAudioPlayer(), storage: storage)
        startupError = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    private static func makeContainer(problems: inout [String]) -> ModelContainer {
        do {
            return try LectureModelContainer.make(inMemory: isUITesting)
        } catch {
            Log.data.fault("저장소 열기 실패: \(error.localizedDescription, privacy: .public)")
        }
        do {
            problems.append("저장소를 열지 못해 임시로 실행 중입니다. 지금 입력한 내용은 앱을 끄면 사라집니다.")
            return try LectureModelContainer.make(inMemory: true)
        } catch {
            // 메모리 저장소조차 만들 수 없으면 앱을 계속할 방법이 없다.
            fatalError("메모리 저장소를 만들 수 없음: \(error)")
        }
    }

    private static func makeRecordingsRoot(problems: inout [String]) -> URL {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "LectureRecorder/Recordings", directoryHint: .isDirectory)
        if isUITesting { return temporary }
        do {
            return try RecordingStorage.defaultRoot()
        } catch {
            Log.storage.fault("녹음 폴더를 열지 못함: \(error.localizedDescription, privacy: .public)")
            problems.append("녹음 폴더를 열지 못해 임시 폴더에 저장합니다.")
            return temporary
        }
    }
}
