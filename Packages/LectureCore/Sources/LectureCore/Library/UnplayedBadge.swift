import Foundation

/// 사이드바 과목 옆의 안 들은 녹음 표시. 개수 대신 작은 점 하나로 보인다(2026-11-28 사용자 결정).
public enum UnplayedBadge {
    /// 안 들은 녹음이 하나라도 있으면 점을 보인다.
    public static func showsDot(count: Int) -> Bool {
        count > 0
    }

    /// 화면 읽기 프로그램용 라벨. 0개면 이름만 읽는다.
    public static func accessibilityLabel(name: String, count: Int) -> String {
        count > 0 ? "\(name), 안 들은 녹음 \(count)개" : name
    }
}
