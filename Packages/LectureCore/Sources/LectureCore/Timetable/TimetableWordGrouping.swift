import Foundation

/// Vision이 한 줄로 읽은 글자를 낱말로 나눴다가, 같은 칸의 글자끼리만 다시 이어 붙인다.
///
/// 요일 머리글("월 화 수 목 금")처럼 멀리 떨어진 글자가 한 줄로 읽히면 요일 칸을 정할 수 없다.
/// 반대로 "정보과학관 212"처럼 한 칸 안의 낱말은 한 줄로 남아야 과목명과 강의실을 나눌 수 있다.
/// 낱말 사이가 글자 높이의 `gapRatio`배보다 좁으면 같은 글자 덩어리로 본다.
public enum TimetableWordGrouping {
    public static let defaultGapRatio = 0.6

    /// - Parameter words: 한 줄에서 나눈 낱말들 (순서 무관).
    public static func merge(_ words: [TextObservation], gapRatio: Double = defaultGapRatio) -> [TextObservation] {
        var result: [TextObservation] = []
        for word in words.sorted(by: { $0.x < $1.x }) {
            guard let last = result.last,
                  word.x - (last.x + last.width) < gapRatio * max(last.height, word.height)
            else {
                result.append(word)
                continue
            }
            let left = min(last.x, word.x)
            let right = max(last.x + last.width, word.x + word.width)
            let top = min(last.y, word.y)
            let bottom = max(last.y + last.height, word.y + word.height)
            result[result.count - 1] = TextObservation(text: "\(last.text) \(word.text)", x: left, y: top, width: right - left, height: bottom - top)
        }
        return result
    }

    /// 공백으로 나뉜 낱말들의 글자 범위. Vision이 낱말마다 위치를 돌려주게 할 때 쓴다.
    public static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var wordStart: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let start = wordStart {
                    ranges.append(start..<index)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = index
            }
        }
        if let start = wordStart { ranges.append(start..<text.endIndex) }
        return ranges
    }
}
