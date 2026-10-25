import Foundation

/// 화면 글자 인식(Vision)이 돌려준 글자 한 덩어리. 좌표는 이미지 픽셀이고 원점은 왼쪽 위다.
public struct TextObservation: Equatable, Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }
}

/// 앱에서 Vision을 함께 import하면 `TextObservation`이 Vision의 같은 이름과 겹친다 (모듈 이름 `LectureCore`는 같은 이름의 enum에 가려져 붙일 수 없다).
/// 그럴 때 쓰는 다른 이름.
public typealias TimetableTextObservation = TextObservation

/// 이미지 한 점의 색.
public struct RGB: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// 가장 센 색과 가장 약한 색의 차이. 흰색·회색은 0에 가깝다.
    var saturation: Int { Int(max(r, g, b)) - Int(min(r, g, b)) }

    func distance(to other: RGB) -> Int {
        abs(Int(r) - Int(other.r)) + abs(Int(g) - Int(other.g)) + abs(Int(b) - Int(other.b))
    }
}

/// 시간표 이미지의 요일 한 칸(세로 줄). 요일 머리글 글자 위치로 정한다.
public struct DayColumn: Equatable, Sendable {
    public let weekday: Weekday
    public let left: Double
    public let right: Double

    /// 색 칸의 위아래를 읽기 위해 이미지에서 한 줄(세로)을 뽑을 x 좌표.
    /// 칸 오른쪽 가장자리 근처라 과목 글자와 겹치지 않는다.
    public var stripX: Double { right - (right - left) * 0.05 }

    public var width: Double { right - left }
}

/// 시간표 한 줄. 같은 과목이 요일마다 따로 나오고, 미리보기에서 줄마다 고친다.
public struct TimetableRow: Equatable, Sendable {
    public var name: String
    public var weekday: Weekday
    public var start: TimeOfDay
    public var end: TimeOfDay
    /// 칸 안에 강의실 글자가 있었는지.
    public var hasRoom: Bool
    /// 저장할지 여부. 강의실이 없거나 채플 같은 칸은 처음에 꺼 둔다.
    public var include: Bool

    public init(name: String, weekday: Weekday, start: TimeOfDay, end: TimeOfDay, hasRoom: Bool, include: Bool) {
        self.name = name
        self.weekday = weekday
        self.start = start
        self.end = end
        self.hasRoom = hasRoom
        self.include = include
    }
}

/// 이미지에서 읽어 낸 시간표 초안. 사용자가 확인하기 전에는 어디에도 저장하지 않는다.
public struct TimetableDraft: Equatable, Sendable {
    /// "2026년 2학기". 읽지 못하면 nil.
    public var semester: String?
    public var rows: [TimetableRow]
    /// 시간이 없어 칸에 그려지지 않은 과목 (사이버 강의 등). 폴더만 만든다.
    public var untimedSubjects: [String]

    public init(semester: String?, rows: [TimetableRow], untimedSubjects: [String]) {
        self.semester = semester
        self.rows = rows
        self.untimedSubjects = untimedSubjects
    }
}

public enum TimetableReadError: Error, Equatable, LocalizedError {
    /// 월·화·수… 머리글을 두 개 이상 찾지 못함.
    case noDayHeaders
    /// 시간 눈금(가로줄)을 두 개 이상 찾지 못함.
    case noGrid
    /// 시간 숫자(9, 10, 11…)를 읽지 못해 어느 줄이 몇 시인지 알 수 없음.
    case noHourLabels

    public var errorDescription: String? {
        switch self {
        case .noDayHeaders: "요일(월·화·수…)을 찾지 못했습니다. 시간표 화면 전체가 나온 이미지인지 확인해 주세요."
        case .noGrid: "시간 눈금을 찾지 못했습니다. 시간표 화면 전체가 나온 이미지인지 확인해 주세요."
        case .noHourLabels: "시간 숫자를 읽지 못했습니다. 시간표 화면 전체가 나온 이미지인지 확인해 주세요."
        }
    }
}

/// 에브리타임 시간표 화면 캡처에서 과목과 시간을 읽어 내는 순수 로직.
/// 글자 인식과 픽셀 읽기는 앱 쪽이 하고, 여기서는 그 결과를 해석한다 (그래서 Linux에서도 테스트한다).
///
/// 순서: `columns(from:)`로 요일 칸 위치를 정하고, 앱이 각 칸에서 세로 한 줄의 색을 뽑아
/// 가로 눈금 줄 후보와 함께 `read(...)`에 넘긴다.
public enum TimetableReader {
    /// 시간 눈금 간격 안에서 칸 시각을 맞출 단위(분).
    public static let snapMinutes = 5
    /// 이 글자가 이름에 들어간 칸은 녹음할 수업이 아니라고 보고 처음에 저장 대상에서 뺀다 (강의실이 없는 칸도 뺀다).
    public static let excludedNameKeywords = ["채플"]

    // MARK: 1단계: 요일 칸

    /// 요일 머리글(월~일 한 글자)의 위치로 요일 칸을 정한다. 같은 글자가 여러 번 읽히면 가장 위의 것을 쓴다.
    public static func columns(from observations: [TextObservation]) throws(TimetableReadError) -> [DayColumn] {
        var headers: [Weekday: TextObservation] = [:]
        for observation in observations {
            guard let weekday = Weekday.allCases.first(where: { $0.shortName == observation.text }) else { continue }
            if let existing = headers[weekday], existing.y <= observation.y { continue }
            headers[weekday] = observation
        }
        // 머리글은 한 줄에 나란히 있다. 가장 많은 머리글이 몰린 높이에서 벗어난 글자는 본문 속 한 글자다.
        let centers = headers.values.map(\.centerY).sorted()
        guard let median = centers.isEmpty ? nil : centers[centers.count / 2] else { throw .noDayHeaders }
        let row = headers.filter { abs($0.value.centerY - median) <= max($0.value.height, 10) }
        let ordered = Weekday.mondayFirst.compactMap { weekday in row[weekday].map { (weekday, $0.centerX) } }
        guard ordered.count >= 2 else { throw .noDayHeaders }

        // 요일 사이 간격(요일 번호 차이로 나눈 값)의 중앙값이 칸 너비다.
        let indices = Dictionary(uniqueKeysWithValues: Weekday.mondayFirst.enumerated().map { ($1, $0) })
        var steps: [Double] = []
        for (first, second) in zip(ordered, ordered.dropFirst()) {
            guard let a = indices[first.0], let b = indices[second.0], b > a else { continue }
            steps.append((second.1 - first.1) / Double(b - a))
        }
        guard let width = steps.isEmpty ? nil : steps.sorted()[steps.count / 2], width > 0 else { throw .noDayHeaders }
        return ordered.map { DayColumn(weekday: $0.0, left: $0.1 - width / 2, right: $0.1 + width / 2) }
    }

    // MARK: 2단계: 읽기

    /// 글자 인식 결과와 이미지 픽셀로 바로 읽는다. 요일 칸을 정하고, 칸마다 세로 한 줄의 색과 가로 눈금줄 후보를 뽑아 아래 `read`에 넘긴다.
    public static func read(observations: [TextObservation], pixels: TimetablePixels) throws(TimetableReadError) -> TimetableDraft {
        let dayColumns = try columns(from: observations)
        var strips: [Weekday: [RGB]] = [:]
        for column in dayColumns {
            strips[column.weekday] = pixels.strip(atX: column.stripX)
        }
        let left = dayColumns.map(\.left).min() ?? 0
        let right = dayColumns.map(\.right).max() ?? 0
        return try read(observations: observations, columns: dayColumns, strips: strips, lineRows: pixels.lineRows(left: left, right: right))
    }

    /// - Parameters:
    ///   - observations: 이미지에서 읽은 모든 글자.
    ///   - columns: `columns(from:)`의 결과.
    ///   - strips: 요일별로 `stripX`에서 위에서 아래로 뽑은 색 (이미지 높이만큼).
    ///   - lineRows: 가로 눈금줄처럼 보이는 행(y) 번호. 줄 하나가 여러 행에 걸쳐 있어도 된다.
    public static func read(
        observations: [TextObservation],
        columns: [DayColumn],
        strips: [Weekday: [RGB]],
        lineRows: [Int]
    ) throws(TimetableReadError) -> TimetableDraft {
        guard let gridLeft = columns.map(\.left).min(), let gridRight = columns.map(\.right).max() else { throw .noDayHeaders }
        let lines = regularLines(clusterLines(lineRows))
        guard lines.count >= 2 else { throw .noGrid }
        let spacing = median(zip(lines, lines.dropFirst()).map { $1 - $0 })
        guard spacing > 0 else { throw .noGrid }
        let firstHour = try inferFirstHour(observations: observations, gridLeft: gridLeft, lines: lines, spacing: spacing)

        func minutes(at y: Double) -> Int {
            let raw = Double(firstHour * 60) + (y - lines[0]) / spacing * 60
            let snapped = Int((raw / Double(snapMinutes)).rounded()) * snapMinutes
            return min(max(snapped, 0), 24 * 60 - 1)
        }

        let used = observations.filter { isBodyText($0, columns: columns, gridTop: lines[0]) }

        var rows: [TimetableRow] = []
        for column in columns {
            guard let strip = strips[column.weekday] else { continue }
            let blocks = detectBlocks(in: strip, from: Int(lines[0]), to: Int(lines[lines.count - 1]) + 1, minHeight: spacing * 0.2)
            for block in blocks {
                guard let start = TimeOfDay(minutesSinceMidnight: minutes(at: Double(block.start))),
                      let end = TimeOfDay(minutesSinceMidnight: minutes(at: Double(block.end))),
                      start < end
                else { continue }
                let inside = used
                    .filter { $0.centerX >= column.left && $0.centerX < column.right && $0.centerY >= Double(block.start) && $0.centerY < Double(block.end) }
                    .sorted { $0.y < $1.y }
                let (name, hasRoom) = nameAndRoom(from: inside.map(\.text))
                rows.append(TimetableRow(
                    name: name,
                    weekday: column.weekday,
                    start: start,
                    end: end,
                    hasRoom: hasRoom,
                    include: !name.isEmpty && hasRoom && !excludedNameKeywords.contains { name.contains($0) }
                ))
            }
        }
        rows.sort { ($0.weekday, $0.start) < ($1.weekday, $1.start) }

        return TimetableDraft(
            semester: semester(in: observations, above: lines[0]),
            rows: rows,
            untimedSubjects: untimedSubjects(in: observations, below: lines[lines.count - 1], spacing: spacing, left: gridLeft, right: gridRight)
        )
    }

    // MARK: 눈금

    /// 이어진 행들을 한 줄로 묶어 가운데 y를 돌려준다.
    static func clusterLines(_ rows: [Int]) -> [Double] {
        let sorted = Set(rows).sorted()
        var result: [Double] = []
        var group: [Int] = []
        for row in sorted {
            if let last = group.last, row - last > 2 {
                result.append(Double(group.reduce(0, +)) / Double(group.count))
                group = []
            }
            group.append(row)
        }
        if !group.isEmpty { result.append(Double(group.reduce(0, +)) / Double(group.count)) }
        return result
    }

    /// 눈금줄 후보 중 같은 간격으로 늘어선 줄만 남긴다. 머리글 아래 선이나 화면 아래의 회색 띠처럼
    /// 간격이 맞지 않는 줄은 버리고, 색 칸에 가려 보이지 않는 줄은 간격에 맞춰 채운다.
    /// 규칙적인 줄을 두 개 이상 찾지 못하면 후보를 그대로 돌려준다.
    static func regularLines(_ lines: [Double]) -> [Double] {
        guard lines.count >= 3 else { return lines }
        // 가장 흔한 간격(5px 단위로 묶는다)이 눈금 간격이다.
        var buckets: [Int: [Double]] = [:]
        for (first, second) in zip(lines, lines.dropFirst()) where second - first >= 10 {
            buckets[Int(((second - first) / 5).rounded()), default: []].append(second - first)
        }
        guard let best = buckets.max(by: { ($0.value.count, $0.key) < ($1.value.count, $1.key) }) else { return lines }
        let step = best.value.reduce(0, +) / Double(best.value.count)
        let tolerance = max(3, step * 0.08)

        var bestReal = 0
        var bestFilled: [Double] = []
        for start in lines.indices {
            var real = 1
            var filled = [lines[start]]
            var index = start
            while true {
                var next: (index: Int, multiple: Int)?
                for multiple in 1...3 where next == nil {
                    let expected = lines[index] + step * Double(multiple)
                    if let found = lines.indices.dropFirst(index + 1).first(where: { abs(lines[$0] - expected) <= tolerance }) {
                        next = (found, multiple)
                    }
                }
                guard let next else { break }
                for missing in 1..<next.multiple { filled.append(lines[index] + step * Double(missing)) }
                filled.append(lines[next.index])
                real += 1
                index = next.index
            }
            if real > bestReal {
                bestReal = real
                bestFilled = filled
            }
        }
        return bestReal >= 2 ? bestFilled : lines
    }

    /// 첫 눈금줄이 몇 시인지. 시간 숫자마다 "이 줄이 몇 시여야 하는지"를 추정해 가장 많이 나온 값을 쓴다.
    private static func inferFirstHour(observations: [TextObservation], gridLeft: Double, lines: [Double], spacing: Double) throws(TimetableReadError) -> Int {
        var votes: [Int: Int] = [:]
        for observation in observations where observation.centerX < gridLeft {
            guard let value = Int(observation.text), (1...12).contains(value),
                  observation.centerY >= lines[0] - spacing * 0.5, observation.centerY <= lines[lines.count - 1] + spacing
            else { continue }
            // 글자는 자기 눈금줄 바로 아래(또는 같은 높이)에 있다.
            let index = Int(((observation.centerY - lines[0]) / spacing + 0.1).rounded(.down))
            guard index >= 0 else { continue }
            // 1~7은 오후(13~19시)일 수 있다.
            let hours = value == 12 ? [12] : [value, value + 12]
            for hour in hours where hour - index >= 0 && hour - index < 24 {
                votes[hour - index, default: 0] += 1
            }
        }
        // 표가 같으면 낮 시간에 가까운 쪽 (1시와 13시가 같은 표면 13시).
        guard let best = votes.max(by: { ($0.value, -abs($0.key - 12)) < ($1.value, -abs($1.key - 12)) }) else { throw .noHourLabels }
        return best.key
    }

    // MARK: 칸 찾기

    struct Block: Equatable {
        let start: Int
        let end: Int
    }

    /// 세로 한 줄의 색에서 색이 칠해진 구간을 찾는다. 색이 달라지면 다른 칸이다.
    static func detectBlocks(in strip: [RGB], from top: Int, to bottom: Int, minHeight: Double) -> [Block] {
        var blocks: [Block] = []
        var current: (start: Int, color: RGB)?
        func close(at end: Int) {
            if let current, Double(end - current.start) >= minHeight { blocks.append(Block(start: current.start, end: end)) }
            current = nil
        }
        let upper = min(bottom, strip.count)
        var y = max(top, 0)
        while y < upper {
            let pixel = strip[y]
            if pixel.saturation > 40 {
                if let active = current, active.color.distance(to: pixel) < 30 {
                    // 같은 칸이 이어진다
                } else {
                    close(at: y)
                    current = (y, pixel)
                }
            } else {
                close(at: y)
            }
            y += 1
        }
        close(at: upper)
        return blocks
    }

    // MARK: 글자 해석

    /// 요일 머리글·시간 숫자·위아래 여백의 글자를 뺀, 격자 안의 글자인지.
    private static func isBodyText(_ observation: TextObservation, columns: [DayColumn], gridTop: Double) -> Bool {
        guard observation.centerY >= gridTop,
              let left = columns.map(\.left).min(), let right = columns.map(\.right).max()
        else { return false }
        return observation.centerX >= left && observation.centerX < right
    }

    /// 칸 안의 글자 줄들에서 과목명과 강의실을 나눈다.
    /// 첫 줄은 항상 과목명이고, 그다음 줄부터 숫자가 들어간 첫 줄이 강의실의 시작이다 ("정보과학관 212").
    /// 과목명이 줄바꿈된 것은 이어 붙이고, 대괄호로 시작하면 괄호 안만 과목명으로 쓴다.
    static func nameAndRoom(from lines: [String]) -> (name: String, hasRoom: Bool) {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return ("", false) }
        let roomStart = cleaned.indices.dropFirst().first { cleaned[$0].contains(where: \.isNumber) }
        let nameLines = roomStart.map { Array(cleaned[..<$0]) } ?? cleaned
        var name = nameLines.joined()
        if name.hasPrefix("["), let close = name.firstIndex(of: "]") {
            let inner = String(name[name.index(after: name.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { name = inner }
        }
        return (name, roomStart != nil)
    }

    /// 격자 위쪽 글자에서 "2026년 2학기"를 찾는다.
    private static func semester(in observations: [TextObservation], above gridTop: Double) -> String? {
        for observation in observations where observation.centerY < gridTop {
            let text = observation.text
            guard let range = text.range(of: #"\d{4}\s*년\s*\d\s*학기"#, options: .regularExpression) else { continue }
            let digits = text[range].split(whereSeparator: { !$0.isNumber }).map(String.init)
            guard digits.count == 2 else { continue }
            return "\(digits[0])년 \(digits[1])학기"
        }
        return nil
    }

    /// 격자 맨 아래 눈금 바로 아래 한 칸 높이 안의 글자는 시간이 없는 과목이다.
    private static func untimedSubjects(in observations: [TextObservation], below bottom: Double, spacing: Double, left: Double, right: Double) -> [String] {
        let footer = observations
            .filter { $0.y > bottom && $0.y < bottom + spacing && $0.centerX >= left && $0.centerX < right }
            .sorted { $0.y < $1.y }
        // 줄바꿈된 이름은 이어 붙인다: 앞 줄 바로 아래(글자 높이의 절반 안)에 붙은 줄.
        var names: [String] = []
        var lastBottom: Double?
        for observation in footer {
            if let lastBottom, observation.y - lastBottom < observation.height * 0.5, !names.isEmpty {
                names[names.count - 1] += observation.text
            } else {
                names.append(observation.text)
            }
            lastBottom = observation.y + observation.height
        }
        return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
