import AppKit
import LectureCore
import SwiftUI

/// 화면 맨 위 가운데(노치 자리)에 투명한 작은 창을 띄워 수업 시작 불빛을 보여 주고, 누르면 녹음 창을 연다.
/// 앱을 활성화하지 않는 패널이라 지금 하던 일을 방해하지 않는다. 노치가 없는 Mac에서도 같은 자리에 뜬다.
@MainActor
final class NotchAlertPresenter {
    private let reminders: ClassReminderController
    private let onOpen: (NotchAlertInfo) -> Void
    private var panel: NSPanel?
    private var shown: NotchAlertInfo?
    private var timer: Timer?

    init(reminders: ClassReminderController, onOpen: @escaping (NotchAlertInfo) -> Void) {
        self.reminders = reminders
        self.onOpen = onOpen
    }

    /// 몇 초마다 불빛을 켤지 다시 정한다. 한 번만 부른다.
    func start() {
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    func update() {
        reminders.refreshNotchAlert()
        guard let info = reminders.notchAlert else {
            hide()
            return
        }
        if info != shown { show(info) }
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        shown = nil
    }

    private func show(_ info: NotchAlertInfo) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NotchAlertView.size
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let view = NotchAlertView(
            info: info,
            notchWidth: Self.notchWidth(of: screen),
            onOpen: { [weak self] in self?.open(info) },
            onDismiss: { [weak self] in
                self?.reminders.dismissNotchAlert()
                self?.hide()
            }
        )
        let panel = self.panel ?? Self.makePanel()
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        shown = info
    }

    private func open(_ info: NotchAlertInfo) {
        reminders.dismissNotchAlert()
        hide()
        onOpen(info)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// 노치 폭. 두 보조 영역 사이의 빈 곳이다. 노치가 없으면 기본값을 쓴다.
    private static func notchWidth(of screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            if width > 0 { return width }
        }
        return 200
    }
}
