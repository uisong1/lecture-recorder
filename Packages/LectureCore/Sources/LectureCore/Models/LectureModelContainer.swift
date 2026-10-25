#if canImport(SwiftData)
import Foundation
import SwiftData

/// 앱에서 쓰는 SwiftData 저장소를 만든다.
public enum LectureModelContainer {
    public static let modelTypes: [any PersistentModel.Type] = [Subject.self, TimeSlot.self, Recording.self, Bookmark.self]

    /// - Parameter inMemory: 테스트와 미리보기용. true면 디스크에 남기지 않는다.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// `make(inMemory: false)`가 쓰는 저장소 파일 위치 (샌드박스에서는 컨테이너 안의 Application Support).
    /// 저장소를 열기 전에 백업할 파일을 찾는 데 쓴다.
    public static func defaultStoreURL() -> URL {
        ModelConfiguration(schema: Schema(modelTypes)).url
    }

    /// 저장소를 열지 못했을 때 화면에 보이는 안내.
    public static let openFailureNotice = "저장소를 열지 못해 임시로 실행 중입니다. 지금 입력한 내용은 앱을 끄면 사라집니다. 녹음 파일은 그대로 있습니다. 앱을 다시 열거나 새 버전을 설치하면 돌아올 수 있고, 어제까지의 백업은 Application Support/LectureRecorder/Backups에 있습니다."

    /// 지정한 파일에 저장하는 저장소. 테스트에서 "앱을 다시 켜도 유지되는지" 확인할 때 쓴다.
    public static func make(url: URL) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
