import Foundation

/// 시간표 이미지의 픽셀. 앱이 이미지를 RGBA(픽셀당 4바이트, 위에서 아래로, 왼쪽에서 오른쪽으로)로 풀어 넘긴다.
/// 이미지 파일 해석은 앱 쪽이 하고, 여기서는 해석 로직이 필요한 줄만 뽑는다 (그래서 Linux에서도 테스트한다).
public struct TimetablePixels: Sendable {
    public let width: Int
    public let height: Int
    private let rgba: [UInt8]

    /// 크기와 바이트 수가 맞지 않으면 nil.
    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    func color(x: Int, y: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(r: rgba[offset], g: rgba[offset + 1], b: rgba[offset + 2])
    }

    /// 세로 한 줄(위에서 아래로, 이미지 높이만큼)의 색. 이미지 밖의 x는 가장자리로 맞춘다.
    public func strip(atX x: Double) -> [RGB] {
        let column = min(max(Int(x.rounded()), 0), width - 1)
        return (0..<height).map { color(x: column, y: $0) }
    }

    /// 가로 눈금줄처럼 보이는 행. `left`~`right` 사이에서 옅은 회색 점이 `minimumFraction` 이상인 행이다.
    /// 색 칸이 줄을 가리는 요일이 있어도 보이도록 기준을 낮게 잡고, 엉뚱한 행은 `TimetableReader`가 간격으로 걸러 낸다.
    public func lineRows(left: Double, right: Double, minimumFraction: Double = 0.25) -> [Int] {
        let from = min(max(Int(left.rounded(.down)), 0), width)
        let to = min(max(Int(right.rounded(.up)), from), width)
        guard to > from else { return [] }
        let needed = Double(to - from) * minimumFraction
        return (0..<height).filter { y in
            var count = 0
            for x in from..<to where Self.isLineGray(color(x: x, y: y)) { count += 1 }
            return Double(count) >= needed
        }
    }

    /// 눈금줄의 옅은 회색: 색기가 거의 없고 흰색보다 약간 어둡다.
    static func isLineGray(_ color: RGB) -> Bool {
        let lowest = min(color.r, color.g, color.b)
        let highest = max(color.r, color.g, color.b)
        return color.saturation <= 10 && lowest >= 200 && highest <= 250
    }
}
