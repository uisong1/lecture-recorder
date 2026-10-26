import Foundation

/// 사이드바 과목 옆에 보이는 "안 들음 N" 표시의 글자.
public enum UnplayedBadge {
    /// 0개면 nil(표시하지 않음).
    public static func text(count: Int) -> String? {
        count > 0 ? "안 들음 \(count)" : nil
    }

    /// 화면 읽기 프로그램용 라벨. 0개면 이름만 읽는다.
    public static func accessibilityLabel(name: String, count: Int) -> String {
        count > 0 ? "\(name), 안 들은 녹음 \(count)개" : name
    }
}
