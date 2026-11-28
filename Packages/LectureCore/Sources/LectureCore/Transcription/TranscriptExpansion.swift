import Foundation

/// 녹음 목록에서 ⌄를 눌러 전사본을 펼친 줄. 한 번에 한 줄만 펼친다(시안 transcript-expand B, 2026-11-29).
public struct TranscriptExpansion<ID: Hashable>: Equatable {
    public private(set) var expanded: ID?

    public init(expanded: ID? = nil) {
        self.expanded = expanded
    }

    public func isExpanded(_ id: ID) -> Bool {
        expanded == id
    }

    /// 펼친 줄을 다시 누르면 접고, 다른 줄을 누르면 앞의 줄은 접고 그 줄을 펼친다.
    public mutating func toggle(_ id: ID) {
        expanded = expanded == id ? nil : id
    }

    /// 목록에서 사라진 줄(삭제·검색으로 걸러짐)이 펼쳐져 있으면 접는다.
    public mutating func keepOnly(_ visible: some Sequence<ID>) {
        guard let current = expanded else { return }
        if !visible.contains(current) { expanded = nil }
    }
}
