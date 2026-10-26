import Foundation

/// 검색에 맞은 북마크 메모를 목록 행에서 몇 줄까지 보일지 정한다. 행 높이가 메모 개수만큼 커지지 않게 한다.
public struct BookmarkMatchSummary<Element> {
    /// 행에 보이는 메모 줄의 최대 개수.
    public static var visibleLimit: Int { 2 }

    /// 보일 북마크 (메모 있는 것만, 받은 순서 그대로 최대 `visibleLimit`개).
    public let shown: [Element]
    /// 접힌 개수.
    public let hiddenCount: Int

    public init(_ matches: [Element], note: (Element) -> String) {
        let withNotes = matches.filter { !note($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        shown = Array(withNotes.prefix(Self.visibleLimit))
        hiddenCount = withNotes.count - shown.count
    }

    /// 접힌 것이 있을 때만 "외 N개".
    public var hiddenText: String? {
        hiddenCount > 0 ? "외 \(hiddenCount)개" : nil
    }
}
