import Foundation

/// 일시정지를 오래 두었을 때의 안내. 수업은 계속되는데 녹음이 멈춰 있는 채로 잊히는 것을 막는다.
public enum PausedAdvice {
    /// 일시정지가 이 시간(초) 넘게 이어지면 알린다. 정각부터 알린다.
    public static let pausedReminderDelay: TimeInterval = 10 * 60

    public static let notice = "일시정지 중입니다. 수업이 이어지면 다시 시작하세요"

    /// `pausedAt`부터 `delay`가 지났으면 안내 문구, 일시정지 중이 아니거나 아직이면 nil.
    public static func notice(pausedAt: Date?, now: Date, delay: TimeInterval = pausedReminderDelay) -> String? {
        guard let pausedAt, now.timeIntervalSince(pausedAt) >= delay else { return nil }
        return notice
    }
}
