#if canImport(os)
import Foundation
import Testing
@testable import LectureCore

final class MemoryTokenStore: CanvasTokenStoring, @unchecked Sendable {
    var token: String?
    var failure: Error?
    func loadToken() throws -> String? { if let failure { throw failure }; return token }
    func saveToken(_ token: String) throws { if let failure { throw failure }; self.token = token }
    func deleteToken() throws { if let failure { throw failure }; token = nil }
}

@MainActor
@Suite struct CanvasTokenModelTests {
    struct Boom: Error, LocalizedError { var errorDescription: String? { "실패" } }

    @Test func 저장하면_공백을_떼어_저장하고_입력칸을_비운다() {
        let store = MemoryTokenStore()
        let model = CanvasTokenModel(store: store)
        #expect(!model.hasToken)
        model.input = "  abc123\n"
        #expect(model.canSave)
        model.save()
        #expect(store.token == "abc123")
        #expect(model.hasToken)
        #expect(model.input.isEmpty)
    }

    @Test func 빈_입력은_저장하지_않는다() {
        let store = MemoryTokenStore()
        let model = CanvasTokenModel(store: store)
        model.input = "   "
        #expect(!model.canSave)
        model.save()
        #expect(store.token == nil)
    }

    @Test func 이미_저장된_토큰이_있으면_있다고_보여_주고_지울_수_있다() {
        let store = MemoryTokenStore()
        store.token = "old"
        let model = CanvasTokenModel(store: store)
        #expect(model.hasToken)
        model.delete()
        #expect(store.token == nil)
        #expect(!model.hasToken)
    }

    @Test func 저장에_실패하면_알리고_토큰을_저장했다고_하지_않는다() {
        let store = MemoryTokenStore()
        store.failure = Boom()
        let model = CanvasTokenModel(store: store)
        model.input = "abc"
        model.save()
        #expect(!model.hasToken)
        #expect(model.message?.contains("저장하지 못했습니다") == true)
    }
}
#endif
