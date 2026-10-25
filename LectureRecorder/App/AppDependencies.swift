import LectureCore
import SwiftData
import SwiftUI

/// 앱 전체에서 함께 쓰는 저장소와 뷰모델을 한곳에서 만든다.
@MainActor
final class AppDependencies {
    /// UI 테스트에서는 디스크에 남기지 않고 권한도 묻지 않는다.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")

    let container: ModelContainer
    /// 디스크 저장소를 열지 못해 임시 저장소로 대신 실행 중이면 그 이유.
    let startupError: String?
    let subjects: SubjectManager
    let schedule: ScheduleManager

    init() {
        let (container, startupError) = Self.makeContainer()
        self.container = container
        self.startupError = startupError
        subjects = SubjectManager(context: container.mainContext)
        schedule = ScheduleManager(context: container.mainContext)
    }

    private static func makeContainer() -> (ModelContainer, String?) {
        do {
            return (try LectureModelContainer.make(inMemory: isUITesting), nil)
        } catch {
            Log.data.fault("저장소 열기 실패: \(error.localizedDescription, privacy: .public)")
        }
        do {
            return (try LectureModelContainer.make(inMemory: true), "저장소를 열지 못해 임시로 실행 중입니다. 지금 입력한 내용은 앱을 끄면 사라집니다.")
        } catch {
            // 메모리 저장소조차 만들 수 없으면 앱을 계속할 방법이 없다.
            fatalError("메모리 저장소를 만들 수 없음: \(error)")
        }
    }
}
