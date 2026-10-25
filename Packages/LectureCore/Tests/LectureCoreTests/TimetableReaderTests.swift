import Foundation
import Testing
@testable import LectureCore

/// 에브리타임 시간표 캡처(1170×2532, 2026년 2학기) 한 장에서 잰 값.
/// 글자 위치와 색 칸은 실제 이미지의 픽셀을 재서 얻었고, 글자 내용은 이미지를 보고 옮겨 적었다
/// (Vision이 실제로 돌려준 값은 Mac에서만 얻을 수 있다).
enum EverytimeFixture {
    static let imageHeight = 2532

    /// 가로 눈금줄: 9시부터 20시까지 12개, 135px 간격, 줄 하나가 3행.
    static let lineRows: [Int] = (0..<12).flatMap { i -> [Int] in
        let y = 418 + 135 * i
        return [y - 1, y, y + 1]
    }

    /// (요일, 위 y, 아래 y, 색)
    static let blocks: [(Weekday, Int, Int, RGB)] = [
        (.tuesday, 621, 789, RGB(r: 226, g: 139, b: 123)),
        (.tuesday, 960, 1026, RGB(r: 229, g: 197, b: 118)),
        (.tuesday, 1026, 1194, RGB(r: 174, g: 200, b: 123)),
        (.tuesday, 1230, 1475, RGB(r: 144, g: 207, b: 193)),
        (.wednesday, 891, 1026, RGB(r: 229, g: 197, b: 118)),
        (.wednesday, 1026, 1194, RGB(r: 131, g: 164, b: 228)),
        (.wednesday, 1230, 1340, RGB(r: 240, g: 174, b: 114)),
        (.wednesday, 1431, 1803, RGB(r: 154, g: 135, b: 219)),
        (.thursday, 1026, 1194, RGB(r: 174, g: 200, b: 123)),
        (.thursday, 1230, 1475, RGB(r: 144, g: 207, b: 193)),
        (.friday, 621, 789, RGB(r: 226, g: 139, b: 123)),
        (.friday, 960, 1205, RGB(r: 139, g: 200, b: 142)),
        (.friday, 1230, 1398, RGB(r: 131, g: 164, b: 228)),
        (.friday, 1431, 1497, RGB(r: 203, g: 154, b: 233)),
    ]

    static func strips(for columns: [DayColumn], blocks: [(Weekday, Int, Int, RGB)] = EverytimeFixture.blocks) -> [Weekday: [RGB]] {
        var result: [Weekday: [RGB]] = [:]
        for column in columns {
            var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: imageHeight)
            for row in lineRows { strip[row] = RGB(r: 237, g: 237, b: 237) }
            for (weekday, top, bottom, color) in blocks where weekday == column.weekday {
                for y in top..<bottom { strip[y] = color }
            }
            result[column.weekday] = strip
        }
        return result
    }

    static func obs(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> TextObservation {
        TextObservation(text: text, x: x, y: y, width: width, height: height)
    }

    static let header: [TextObservation] = [
        obs("2026년 2학기", 75, 180, 223, 33),
        obs("월", 180, 374, 22, 26), obs("화", 393, 374, 24, 26), obs("수", 606, 375, 24, 25),
        obs("목", 819, 375, 24, 25), obs("금", 1032, 376, 24, 23),
    ]

    static let hourLabels: [TextObservation] = [
        obs("9", 67, 428, 14, 21), obs("10", 52, 563, 29, 21), obs("11", 57, 698, 22, 21), obs("12", 53, 833, 28, 21),
        obs("1", 72, 968, 7, 21), obs("2", 68, 1103, 13, 21), obs("3", 67, 1238, 14, 21), obs("4", 66, 1373, 15, 21),
        obs("5", 68, 1508, 13, 21), obs("6", 67, 1643, 14, 21), obs("7", 68, 1778, 14, 21),
    ]

    static let body: [TextObservation] = [
        obs("사용자인터페", 307, 632, 182, 31), obs("이스", 308, 675, 59, 31),
        obs("정보과학관 212", 308, 718, 185, 26), obs("05 (실습실)", 308, 753, 142, 29),
        obs("탐테", 309, 977, 56, 31),
        obs("알고리즘", 308, 1038, 121, 32), obs("정보과학관 212", 308, 1080, 185, 26),
        obs("03 (김재상강의", 308, 1116, 183, 29), obs("실)", 308, 1151, 31, 29),
        obs("AI데이터분석", 308, 1241, 185, 32), obs("및실습", 309, 1284, 89, 32),
        obs("정보과학관 212", 308, 1327, 185, 26), obs("05 (실습실)", 308, 1362, 142, 29),
        obs("탐테", 522, 903, 56, 31),
        obs("컴퓨터구조", 521, 1038, 152, 31), obs("정보과학관 212", 521, 1080, 185, 26),
        obs("04 (김선행강의", 521, 1116, 183, 29), obs("실)", 521, 1151, 31, 29),
        obs("비전채플", 522, 1242, 120, 31), obs("한경직기념관 0", 521, 1284, 178, 26),
        obs("컴퓨터네트워", 521, 1443, 181, 32), obs("크", 523, 1490, 22, 18),
        obs("정보과학관 212", 521, 1528, 185, 26), obs("02 (이준호강의", 521, 1564, 182, 29), obs("실)", 521, 1599, 31, 29),
        obs("알고리즘", 734, 1038, 121, 32), obs("정보과학관 212", 734, 1080, 185, 26),
        obs("03 (김재상강의", 734, 1116, 183, 29), obs("실)", 734, 1151, 31, 29),
        obs("AI데이터분석", 734, 1241, 185, 32), obs("및실습", 735, 1284, 89, 32),
        obs("정보과학관 212", 734, 1327, 185, 26), obs("05 (실습실)", 734, 1362, 142, 29),
        obs("사용자인터페", 946, 632, 182, 31), obs("이스", 947, 675, 59, 31),
        obs("정보과학관 212", 947, 718, 185, 26), obs("05 (실습실)", 947, 753, 142, 29),
        obs("[글로벌시민", 950, 971, 162, 35), obs("의식]세계화", 946, 1014, 169, 35),
        obs("와글로벌이슈", 946, 1057, 184, 32), obs("전산관 19327", 946, 1099, 172, 25),
        obs("컴퓨터구조", 947, 1242, 152, 31), obs("정보과학관 212", 947, 1284, 185, 26),
        obs("02 (이준호강의", 947, 1320, 182, 29), obs("실)", 947, 1355, 31, 29),
        obs("복지일", 946, 1448, 89, 32),
    ]

    static let footer: [TextObservation] = [
        obs("AI기술산업응용및설계(숭실사이버대)", 73, 1943, 528, 35),
    ]

    /// 시간표와 상관없는 화면 요소: 상태 표시줄, 친구 검색, 아래 탭.
    static let noise: [TextObservation] = [
        obs("5:43", 110, 50, 95, 50), obs("57", 1040, 60, 40, 30),
        obs("이름으로 친구를 검색하세요", 170, 2150, 520, 50),
        obs("홈", 100, 2390, 40, 35), obs("시간표", 310, 2390, 75, 35), obs("게시판", 540, 2390, 75, 35),
    ]

    static var all: [TextObservation] { header + hourLabels + body + footer + noise }
}

@Suite struct TimetableReaderTests {
    func hm(_ hour: Int, _ minute: Int) -> TimeOfDay {
        guard let time = try? TimeOfDay(hour: hour, minute: minute) else { fatalError("잘못된 테스트 시각") }
        return time
    }

    func row(_ name: String, _ weekday: Weekday, _ start: (Int, Int), _ end: (Int, Int), room: Bool, include: Bool) -> TimetableRow {
        TimetableRow(name: name, weekday: weekday, start: hm(start.0, start.1), end: hm(end.0, end.1), hasRoom: room, include: include)
    }

    func readFixture() throws -> TimetableDraft {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        return try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
    }

    // MARK: 요일 칸

    @Test func 요일_머리글로_다섯_칸을_정한다() throws {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        #expect(columns.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(abs(columns[0].width - 213) < 2)
        #expect(abs(columns[0].left - 85) < 3)
        #expect(abs(columns[4].right - 1144) < 3)
    }

    @Test func 본문에_같은_글자가_있어도_맨_위_머리글을_쓴다() throws {
        let extra = EverytimeFixture.all + [EverytimeFixture.obs("화", 400, 1500, 24, 30)]
        let columns = try TimetableReader.columns(from: extra)
        #expect(columns.count == 5)
        #expect(abs(columns[1].left + columns[1].width / 2 - 405) < 3)
    }

    @Test func 토요일이_있으면_여섯_칸이다() throws {
        let saturday = EverytimeFixture.obs("토", 1245, 374, 24, 26)
        let columns = try TimetableReader.columns(from: EverytimeFixture.all + [saturday])
        #expect(columns.map(\.weekday).last == .saturday)
        #expect(columns.count == 6)
    }

    @Test func 머리글이_한_개뿐이면_오류다() {
        let only = [EverytimeFixture.obs("월", 180, 374, 22, 26)]
        #expect(throws: TimetableReadError.noDayHeaders) { try TimetableReader.columns(from: only) }
        #expect(throws: TimetableReadError.noDayHeaders) { try TimetableReader.columns(from: []) }
    }

    // MARK: 전체 읽기

    @Test func 학기_이름을_읽는다() throws {
        #expect(try readFixture().semester == "2026년 2학기")
    }

    @Test func 사진의_시간표를_열네_칸으로_읽는다() throws {
        let expected = [
            row("사용자인터페이스", .tuesday, (10, 30), (11, 45), room: true, include: true),
            row("탐테", .tuesday, (13, 0), (13, 30), room: false, include: false),
            row("알고리즘", .tuesday, (13, 30), (14, 45), room: true, include: true),
            row("AI데이터분석및실습", .tuesday, (15, 0), (16, 50), room: true, include: true),
            row("탐테", .wednesday, (12, 30), (13, 30), room: false, include: false),
            row("컴퓨터구조", .wednesday, (13, 30), (14, 45), room: true, include: true),
            row("비전채플", .wednesday, (15, 0), (15, 50), room: true, include: false),
            row("컴퓨터네트워크", .wednesday, (16, 30), (19, 15), room: true, include: true),
            row("알고리즘", .thursday, (13, 30), (14, 45), room: true, include: true),
            row("AI데이터분석및실습", .thursday, (15, 0), (16, 50), room: true, include: true),
            row("사용자인터페이스", .friday, (10, 30), (11, 45), room: true, include: true),
            row("글로벌시민의식", .friday, (13, 0), (14, 50), room: true, include: true),
            row("컴퓨터구조", .friday, (15, 0), (16, 15), room: true, include: true),
            row("복지일", .friday, (16, 30), (17, 0), room: false, include: false),
        ]
        #expect(try readFixture().rows == expected)
    }

    @Test func 시간_없는_과목은_따로_모은다() throws {
        #expect(try readFixture().untimedSubjects == ["AI기술산업응용및설계(숭실사이버대)"])
    }

    @Test func 상태표시줄과_탭_글자는_과목으로_읽지_않는다() throws {
        let draft = try readFixture()
        #expect(!draft.rows.contains { ["홈", "시간표", "게시판", "5:43", "57"].contains($0.name) })
        #expect(!draft.untimedSubjects.contains { $0.contains("친구") })
    }

    @Test func 월요일에_수업이_없어도_읽는다() throws {
        #expect(try readFixture().rows.allSatisfy { $0.weekday != .monday })
    }

    @Test func 글자를_못_읽은_칸은_이름이_비고_저장_대상에서_빠진다() throws {
        // 월요일 칸에 색만 있고 글자는 없다.
        var blocks = EverytimeFixture.blocks
        blocks.append((.monday, 621, 789, RGB(r: 10, g: 120, b: 200)))
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        let draft = try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns, blocks: blocks),
            lineRows: EverytimeFixture.lineRows
        )
        let monday = draft.rows.filter { $0.weekday == .monday }
        #expect(monday.count == 1)
        #expect(monday[0].name.isEmpty)
        #expect(!monday[0].include)
        #expect(monday[0].start == hm(10, 30))
    }

    // MARK: 기본 제외

    @Test func 강의실_없는_칸과_채플만_처음에_제외한다() throws {
        let excluded = try readFixture().rows.filter { !$0.include }.map(\.name)
        #expect(excluded == ["탐테", "탐테", "비전채플", "복지일"])
    }

    @Test func 강의실이_있는_50분_수업은_포함한다() throws {
        // 수요일 15:00~15:50 칸에 채플 대신 일반 과목 이름이 있어도 시간이 짧다는 이유로 빠지지 않는다.
        let renamed = EverytimeFixture.all.map { $0.text == "비전채플" ? EverytimeFixture.obs("글쓰기", $0.x, $0.y, $0.width, $0.height) : $0 }
        let columns = try TimetableReader.columns(from: renamed)
        let draft = try TimetableReader.read(
            observations: renamed,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
        let writing = try #require(draft.rows.first { $0.name == "글쓰기" })
        #expect(writing.end.minutesSinceMidnight - writing.start.minutesSinceMidnight == 50)
        #expect(writing.include)
    }

    @Test func 이름에_채플이_들어가면_강의실이_있어도_제외한다() {
        #expect(TimetableReader.excludedNameKeywords == ["채플"])
    }

    // MARK: 오류

    @Test func 눈금줄이_없으면_오류다() throws {
        let columns = try TimetableReader.columns(from: EverytimeFixture.all)
        #expect(throws: TimetableReadError.noGrid) {
            try TimetableReader.read(observations: EverytimeFixture.all, columns: columns, strips: [:], lineRows: [418])
        }
    }

    @Test func 시간_숫자를_못_읽으면_오류다() throws {
        let withoutLabels = EverytimeFixture.header + EverytimeFixture.body
        let columns = try TimetableReader.columns(from: withoutLabels)
        #expect(throws: TimetableReadError.noHourLabels) {
            try TimetableReader.read(observations: withoutLabels, columns: columns, strips: [:], lineRows: EverytimeFixture.lineRows)
        }
    }

    @Test func 시간표가_오후부터_시작해도_시각을_맞춘다() throws {
        // 1시부터 보이는 화면: 첫 눈금줄이 13시.
        let lines = (0..<4).flatMap { i -> [Int] in [100 + 100 * i - 1, 100 + 100 * i, 100 + 100 * i + 1] }
        let labels = [("1", 0), ("2", 1), ("3", 2), ("4", 3)].map { EverytimeFixture.obs($0.0, 60, 100 + 100 * Double($0.1) + 10, 14, 20) }
        let days = [EverytimeFixture.obs("월", 250, 40, 22, 26), EverytimeFixture.obs("화", 450, 40, 24, 26)]
        let observations = days + labels
        let columns = try TimetableReader.columns(from: observations)
        var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: 600)
        for y in 150..<250 { strip[y] = RGB(r: 100, g: 150, b: 220) }
        let draft = try TimetableReader.read(observations: observations, columns: columns, strips: [.monday: strip], lineRows: lines)
        #expect(draft.rows.map(\.start) == [hm(13, 30)])
        #expect(draft.rows.map(\.end) == [hm(14, 30)])
    }

    // MARK: 부분 동작

    @Test func 눈금줄은_이어진_행을_한_줄로_묶는다() {
        #expect(TimetableReader.clusterLines([100, 101, 102, 200, 201, 202, 203]) == [101, 201.5])
        #expect(TimetableReader.clusterLines([]) == [])
        #expect(TimetableReader.clusterLines([50, 50, 51]) == [50.5])
    }

    @Test func 색이_달라지는_곳에서_칸을_나눈다() {
        var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: 300)
        for y in 50..<100 { strip[y] = RGB(r: 229, g: 197, b: 118) }
        for y in 100..<200 { strip[y] = RGB(r: 131, g: 164, b: 228) }
        let blocks = TimetableReader.detectBlocks(in: strip, from: 0, to: 300, minHeight: 20)
        #expect(blocks == [.init(start: 50, end: 100), .init(start: 100, end: 200)])
    }

    @Test func 너무_낮은_색_조각은_칸으로_보지_않는다() {
        var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: 100)
        for y in 10..<15 { strip[y] = RGB(r: 200, g: 100, b: 100) }
        #expect(TimetableReader.detectBlocks(in: strip, from: 0, to: 100, minHeight: 20).isEmpty)
    }

    @Test func 흰색과_회색_눈금은_칸이_아니다() {
        var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: 100)
        for y in 30..<60 { strip[y] = RGB(r: 237, g: 237, b: 237) }
        #expect(TimetableReader.detectBlocks(in: strip, from: 0, to: 100, minHeight: 5).isEmpty)
    }

    @Test func 격자_끝까지_이어진_칸도_닫는다() {
        var strip = Array(repeating: RGB(r: 255, g: 255, b: 255), count: 100)
        for y in 40..<100 { strip[y] = RGB(r: 154, g: 135, b: 219) }
        #expect(TimetableReader.detectBlocks(in: strip, from: 0, to: 100, minHeight: 20) == [.init(start: 40, end: 100)])
    }

    @Test func 과목명과_강의실을_나눈다() {
        #expect(TimetableReader.nameAndRoom(from: ["알고리즘", "정보과학관 212", "03 (김재상강의", "실)"]) == ("알고리즘", true))
        #expect(TimetableReader.nameAndRoom(from: ["사용자인터페", "이스", "정보과학관 212", "05 (실습실)"]) == ("사용자인터페이스", true))
        #expect(TimetableReader.nameAndRoom(from: ["탐테"]) == ("탐테", false))
        #expect(TimetableReader.nameAndRoom(from: ["컴퓨터네트워", "크"]) == ("컴퓨터네트워크", false))
    }

    @Test func 첫_줄에_숫자가_있어도_과목명이다() {
        #expect(TimetableReader.nameAndRoom(from: ["3D프린팅", "공학관 101"]) == ("3D프린팅", true))
    }

    @Test func 대괄호_과목명은_괄호_안만_쓴다() {
        let result = TimetableReader.nameAndRoom(from: ["[글로벌시민", "의식]세계화", "와글로벌이슈", "전산관 19327"])
        #expect(result == ("글로벌시민의식", true))
    }

    @Test func 글자가_없으면_빈_이름이다() {
        #expect(TimetableReader.nameAndRoom(from: []) == ("", false))
        #expect(TimetableReader.nameAndRoom(from: ["  ", ""]) == ("", false))
    }
}
