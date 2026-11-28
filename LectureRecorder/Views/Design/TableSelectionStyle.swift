import AppKit
import SwiftUI

/// macOS의 `List`는 고른 행을 맥 시스템 강조색(보통 파랑)으로 칠한다. DESIGN.md는 고른 행을 검정으로 그리므로,
/// 행 뒤에 이 뷰를 깔아 바깥 표(NSTableView)의 기본 선택 칠하기를 끄고, 선택 표시는 `listRowBackground`로 직접 그린다.
/// 선택 자체(클릭·⌘클릭·Shift클릭, 우클릭 메뉴)는 그대로 동작한다.
struct SystemSelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Probe()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Probe)?.apply()
    }

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            var view: NSView? = superview
            while let current = view {
                if let table = current as? NSTableView {
                    if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
                    return
                }
                view = current.superview
            }
        }
    }
}
