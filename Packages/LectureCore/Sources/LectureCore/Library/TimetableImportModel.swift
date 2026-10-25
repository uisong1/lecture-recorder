#if canImport(SwiftData)
import Foundation
import Observation

/// 이미지 한 장에서 시간표 초안을 읽는다. 실제 구현(Vision 글자 인식)은 앱에 있고, 테스트에서는 가짜를 쓴다.
public protocol TimetableImageReading: Sendable {
    func readTimetable(from imageData: Data) async throws -> TimetableDraft
}

/// 시간표 가져오기 화면의 상태: 이미지 고르기 → 읽기 → 미리보기에서 고치기 → 저장.
/// 미리보기에서 확인하기 전에는 아무것도 저장하지 않는다.
@MainActor
@Observable
public final class TimetableImportModel {
    public enum Phase: Equatable {
        case waiting
        case reading
        case preview
        case saved(TimetableImportResult)
    }

    public private(set) var phase: Phase = .waiting
    /// 미리보기에서 고치는 초안. `phase`가 `.preview`일 때만 있다.
    public var editor: TimetableDraftEditor?
    public private(set) var errorMessage: String?
    /// 저장하면 지워질 기존 시간표 칸 수.
    public private(set) var existingSlotCount = 0

    private let reader: any TimetableImageReading
    private let importer: TimetableImporter
    private let onImported: @MainActor () async -> Void
    /// 이미지를 연달아 놓았을 때 늦게 끝난 앞 이미지의 결과를 버리기 위한 번호.
    private var generation = 0

    /// - Parameter onImported: 저장이 끝난 뒤 화면 목록·알림·녹음 폴더 정리를 다시 하는 일.
    public init(reader: any TimetableImageReading, importer: TimetableImporter, onImported: @escaping @MainActor () async -> Void = {}) {
        self.reader = reader
        self.importer = importer
        self.onImported = onImported
    }

    /// 이미지 파일을 읽어 미리보기까지 만든다.
    public func load(fileAt url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Log.data.error("시간표 이미지 열기 실패: \(error.localizedDescription, privacy: .public)")
            errorMessage = "이미지 파일을 열지 못했습니다: \(error.localizedDescription)"
            return
        }
        await load(imageData: data)
    }

    public func load(imageData: Data) async {
        generation += 1
        let mine = generation
        phase = .reading
        errorMessage = nil
        editor = nil
        do {
            let draft = try await reader.readTimetable(from: imageData)
            guard mine == generation else { return }
            guard !draft.rows.isEmpty || !draft.untimedSubjects.isEmpty else {
                phase = .waiting
                errorMessage = "시간표 칸을 찾지 못했습니다. 에브리타임 시간표 화면 전체가 나온 캡처인지 확인해 주세요."
                return
            }
            editor = TimetableDraftEditor(draft: draft)
            existingSlotCount = importer.existingSlotCount()
            phase = .preview
        } catch {
            guard mine == generation else { return }
            Log.data.error("시간표 이미지 읽기 실패: \(error.localizedDescription, privacy: .public)")
            phase = .waiting
            errorMessage = (error as? TimetableReadError)?.errorDescription ?? "이미지를 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 미리보기를 확인하고 저장한다. 고칠 곳이 남았거나 저장에 실패하면 미리보기에 남아 이유를 보인다.
    public func confirm() async {
        guard phase == .preview, let editor else { return }
        do {
            let result = try importer.apply(editor)
            errorMessage = nil
            self.editor = nil
            phase = .saved(result)
        } catch let error as TimetableImportError {
            errorMessage = error.errorDescription
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await onImported()
    }

    /// 처음 화면으로 돌아간다. 저장하지 않은 초안은 버린다.
    public func reset() {
        generation += 1
        phase = .waiting
        editor = nil
        errorMessage = nil
    }
}
#endif
