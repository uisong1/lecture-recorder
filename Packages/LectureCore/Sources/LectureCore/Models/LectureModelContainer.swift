#if canImport(SwiftData)
import SwiftData

/// 앱에서 쓰는 SwiftData 저장소를 만든다.
public enum LectureModelContainer {
    public static let modelTypes: [any PersistentModel.Type] = [Subject.self, TimeSlot.self, Recording.self]

    /// - Parameter inMemory: 테스트와 미리보기용. true면 디스크에 남기지 않는다.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
