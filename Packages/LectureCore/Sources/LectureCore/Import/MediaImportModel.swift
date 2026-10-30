#if canImport(SwiftData)
import Foundation
import Observation

/// 끌어다 놓거나 골라서 가져올 파일들의 확인 창 상태. 과목과 날짜를 고친 뒤 "가져오기"를 눌러야 파일이 저장된다.
@MainActor
@Observable
public final class MediaImportModel {
    public enum Status: Equatable, Sendable {
        case pending
        case importing
        case done
        case failed(String)
    }

    public struct Item: Identifiable, Equatable {
        public let id = UUID()
        public let url: URL
        /// 수업 날짜·시각. 파일을 만든 시각으로 시작하고 사용자가 고칠 수 있다.
        public var startedAt: Date
        public var status: Status = .pending

        public var name: String { url.lastPathComponent }
    }

    public var isPresented = false
    public private(set) var items: [Item] = []
    /// 모든 파일에 쓸 과목. nil이면 미분류.
    public var subject: Subject?
    public private(set) var isImporting = false
    /// 건너뛴 파일이나 실패를 알리는 문구.
    public private(set) var message: String?

    private let importer: MediaImporter
    private let suggestSubject: @MainActor (Date) -> Subject?
    private let suggestDate: (URL) -> Date?
    private let now: () -> Date
    private let onFinished: @MainActor () -> Void

    /// - Parameters:
    ///   - suggestSubject: 날짜로 시간표의 과목을 추천한다.
    ///   - suggestDate: 파일에서 추천할 날짜 (보통 파일을 만든 시각).
    ///   - onFinished: 하나라도 가져왔으면 목록을 다시 읽는 데 쓴다.
    public init(
        importer: MediaImporter,
        suggestSubject: @escaping @MainActor (Date) -> Subject? = { _ in nil },
        suggestDate: @escaping (URL) -> Date? = MediaImportModel.fileCreationDate,
        now: @escaping () -> Date = { Date() },
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.importer = importer
        self.suggestSubject = suggestSubject
        self.suggestDate = suggestDate
        self.now = now
        self.onFinished = onFinished
    }

    /// 파일을 만든 시각. 알 수 없으면 nil.
    nonisolated public static func fileCreationDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    public var canImport: Bool { !isImporting && items.contains { $0.status != .done } }

    /// 놓거나 고른 파일들로 확인 창을 연다. mp4/m4a가 아닌 파일은 빼고 문구로 알린다.
    public func begin(urls: [URL]) {
        guard !isImporting, !urls.isEmpty else { return }
        let accepted = urls.filter { MediaFileKind(fileName: $0.lastPathComponent) != nil }
        let rejected = urls.filter { MediaFileKind(fileName: $0.lastPathComponent) == nil }
        items = accepted.map { Item(url: $0, startedAt: suggestDate($0) ?? now()) }
        message = rejected.isEmpty ? nil : "mp4, m4a 파일만 가져올 수 있습니다: " + rejected.map(\.lastPathComponent).joined(separator: ", ")
        subject = items.first.flatMap { suggestSubject($0.startedAt) }
        isPresented = true
    }

    public func setDate(_ date: Date, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].startedAt = date
    }

    /// 아직 가져오지 못한 파일을 차례로 가져온다. 한 파일이 실패해도 나머지는 계속한다.
    public func run() async {
        guard canImport else { return }
        isImporting = true
        defer { isImporting = false }
        var result = RecordingBatchResult()
        for index in items.indices where items[index].status != .done {
            items[index].status = .importing
            let item = items[index]
            // 끌어다 놓거나 고른 파일은 이 접근을 열어야 샌드박스 안에서 읽힌다. 일반 파일이면 false를 돌려줄 뿐 해롭지 않다.
            let scoped = item.url.startAccessingSecurityScopedResource()
            defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }
            do {
                try await importer.importFile(at: item.url, subject: subject, startedAt: item.startedAt)
                items[index].status = .done
                result.succeededCount += 1
            } catch {
                items[index].status = .failed(error.localizedDescription)
                result.failedTitles.append(item.name)
            }
        }
        if result.succeededCount > 0 { onFinished() }
        if let notice = result.failureNotice(done: "가져왔고") {
            message = notice
        } else {
            reset()
        }
    }

    public func close() {
        guard !isImporting else { return }
        reset()
    }

    private func reset() {
        isPresented = false
        items = []
        message = nil
    }
}
#endif
