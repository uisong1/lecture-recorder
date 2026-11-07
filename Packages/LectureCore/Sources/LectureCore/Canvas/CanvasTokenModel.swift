#if canImport(os)
import Foundation
import Observation

/// 설정 화면의 Canvas 토큰 입력 상태. 토큰은 Keychain에만 저장하고, 화면에는 저장 여부만 보여 준다(값은 다시 보여 주지 않는다).
@MainActor
@Observable
public final class CanvasTokenModel {
    public private(set) var hasToken = false
    public private(set) var message: String?
    public var input = ""

    private let store: any CanvasTokenStoring

    public init(store: any CanvasTokenStoring) {
        self.store = store
        refresh()
    }

    public func refresh() {
        do {
            hasToken = try store.loadToken() != nil
        } catch {
            hasToken = false
            message = "토큰을 읽지 못했습니다: \(error.localizedDescription)"
            Log.app.error("Canvas 토큰 읽기 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    public var canSave: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func save() {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try store.saveToken(token)
            input = ""
            hasToken = true
            message = nil
        } catch {
            message = "토큰을 저장하지 못했습니다: \(error.localizedDescription)"
            Log.app.error("Canvas 토큰 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func delete() {
        do {
            try store.deleteToken()
            hasToken = false
            input = ""
            message = nil
        } catch {
            message = "토큰을 지우지 못했습니다: \(error.localizedDescription)"
            Log.app.error("Canvas 토큰 삭제 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
