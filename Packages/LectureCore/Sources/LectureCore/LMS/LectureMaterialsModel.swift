#if canImport(SwiftData)
import Foundation
import Observation

/// 설정 > LMS의 "강의자료 PDF 가져오기" 버튼 뒤의 상태. 한 번에 하나만 돌린다.
@MainActor
@Observable
public final class LectureMaterialsModel {
    public enum Status: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    public private(set) var status: Status = .idle

    private let makeSyncer: @MainActor () throws -> LectureMaterialsSyncer
    private let subjects: @MainActor () -> [MaterialsSubject]
    private let onFinished: @MainActor () -> Void

    public init(
        makeSyncer: @escaping @MainActor () throws -> LectureMaterialsSyncer,
        subjects: @escaping @MainActor () -> [MaterialsSubject],
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.makeSyncer = makeSyncer
        self.subjects = subjects
        self.onFinished = onFinished
    }

    public var isBusy: Bool {
        if case .working = status { return true }
        return false
    }

    /// 수강 중인 모든 과목의 PDF를 받는다.
    public func start() async {
        guard !isBusy else { return }
        let list = subjects()
        guard !list.isEmpty else {
            status = .failed("앱에 과목이 없어요. 시간표를 먼저 넣어 주세요.")
            return
        }
        status = .working("LMS 강의 목록을 읽는 중")
        do {
            let syncer = try makeSyncer()
            let report = try await syncer.sync(subjects: list) { message in
                Task { @MainActor [weak self] in
                    guard let self, self.isBusy else { return }
                    self.status = .working(message)
                }
            }
            status = .done(report.summary)
            onFinished()
        } catch {
            Log.app.error("LMS 강의자료 가져오기 실패: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }
}
#endif
