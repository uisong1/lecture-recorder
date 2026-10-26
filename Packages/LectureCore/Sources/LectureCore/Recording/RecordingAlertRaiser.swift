import Foundation

/// 녹음 중 문제를 시스템 알림으로 알린다. 같은 녹음 안에서는 종류마다 한 번만 보내고, 새 녹음을 시작하면 `reset()`으로 다시 보낼 수 있게 한다.
/// 이미 알림을 허용한 경우에만 보낸다 (권한은 알림 쪽에서 새로 묻지 않는다). 화면 경고는 따로 있으므로 알림이 없어도 알 수 있다.
@MainActor
final class RecordingAlertRaiser {
    private let notifier: (any NotificationScheduling)?
    private var sent: Set<RecordingAlert> = []

    init(notifier: (any NotificationScheduling)?) {
        self.notifier = notifier
    }

    /// 새 녹음이 시작될 때 불러, 지난 녹음에서 보낸 종류도 다시 보낼 수 있게 한다.
    func reset() {
        sent = []
    }

    /// 같은 녹음 안에서도 `alert`를 다시 보낼 수 있게 한다 (일시정지처럼 한 녹음에서 여러 번 생기는 상황용).
    func rearm(_ alert: RecordingAlert) {
        sent.remove(alert)
    }

    /// `alert`를 이 녹음에서 처음 알리는 것이면 알림을 보낸다. `body`로 기본 문구를 바꿀 수 있다.
    func raise(_ alert: RecordingAlert, body: String? = nil) {
        guard sent.insert(alert).inserted, let notifier else { return }
        let text = body ?? alert.body
        Task { await notifier.notify(title: alert.title, body: text, identifier: alert.identifier) }
    }
}
