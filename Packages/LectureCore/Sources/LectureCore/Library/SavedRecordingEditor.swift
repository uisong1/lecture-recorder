#if canImport(SwiftData)
import Foundation
import Observation

/// 정지 직후 "저장됨" 줄에서 제목·메모·과목을 고치는 칸의 상태. 저장 호출을 여기 하나로 묶고, 실패하면 문구를 남긴다.
@MainActor
@Observable
public final class SavedRecordingEditor {
    public var title = ""
    public var memo = ""
    public private(set) var isEditing = false
    /// 마지막 저장(또는 과목 이동) 실패 문구. 성공하면 비운다.
    public private(set) var errorMessage: String?

    private let manager: RecordingManager
    private let onChange: () -> Void

    /// `onChange`는 저장에 성공했을 때 목록을 다시 읽는 데 쓴다.
    public init(manager: RecordingManager, onChange: @escaping () -> Void = {}) {
        self.manager = manager
        self.onChange = onChange
    }

    public func begin(_ recording: Recording) {
        title = recording.title
        memo = recording.memo
        errorMessage = nil
        isEditing = true
    }

    /// 칸을 닫는다. 저장하지 않고 닫을 때(다른 녹음으로 바뀜 등)도 쓴다.
    public func cancel() {
        isEditing = false
        errorMessage = nil
    }

    /// 제목과 메모를 저장한다. 하나라도 실패하면 칸을 열어 둔 채 false.
    @discardableResult
    public func save(_ recording: Recording) -> Bool {
        let succeeded = run {
            if title != recording.title { try manager.rename(recording, to: title) }
            try manager.setMemo(memo, for: recording)
        }
        if succeeded { isEditing = false }
        return succeeded
    }

    @discardableResult
    public func move(_ recording: Recording, to subject: Subject?) -> Bool {
        run { try manager.move(recording, to: subject) }
    }

    private func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            errorMessage = nil
            onChange()
            return true
        } catch {
            errorMessage = manager.errorMessage ?? error.localizedDescription
            return false
        }
    }
}
#endif
