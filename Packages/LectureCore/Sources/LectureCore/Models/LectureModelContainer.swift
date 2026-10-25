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

    /// 지정한 파일에 저장하는 저장소. 테스트에서 "앱을 다시 켜도 유지되는지" 확인할 때 쓴다.
    public static func make(url: URL) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
