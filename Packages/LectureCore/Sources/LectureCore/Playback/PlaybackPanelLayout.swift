import Foundation

/// 아래 재생 패널의 높이 규칙. 사용자가 끌어서 정한 높이를 허용 범위로 맞춘다.
public enum PlaybackPanelLayout {
    public static let minHeight: Double = 110
    public static let maxHeight: Double = 600

    /// 끌어서 정한 높이를 범위 안으로 맞춘다. `available`은 창에서 쓸 수 있는 높이이고, 위 영역에 최소 `reservedAbove`는 남긴다.
    public static func clamp(_ height: Double, available: Double? = nil, reservedAbove: Double = 160) -> Double {
        var upper = maxHeight
        if let available { upper = min(upper, max(minHeight, available - reservedAbove)) }
        return min(max(height, minHeight), upper)
    }

    /// 끌기를 시작할 때의 높이와 위로 끈 만큼(위로 끌면 양수)으로 새 높이를 구한다.
    public static func height(start: Double, dragUp: Double, available: Double? = nil) -> Double {
        clamp(start + dragUp, available: available)
    }
}
