import Foundation
import Testing
@testable import LectureCore

/// 실제 캡처(1170×2532)와 같은 크기·위치로 그린 RGBA 이미지.
private struct SyntheticTimetableImage {
    let width = 1170
    let height = EverytimeFixture.imageHeight
    var rgba: [UInt8]

    init(columns: [DayColumn], extraLines: Bool) {
        rgba = Array(repeating: 255, count: 1170 * EverytimeFixture.imageHeight * 4)
        let gridLeft = Int(columns.map(\.left).min() ?? 0)
        let gridRight = Int(columns.map(\.right).max() ?? 0)
        let gray = RGB(r: 237, g: 237, b: 237)
        for row in EverytimeFixture.lineRows { fill(x: gridLeft..<gridRight, y: row..<(row + 1), color: gray) }
        if extraLines {
            // 머리글 아래 선과 화면 아래의 회색 띠: 눈금줄이 아니다.
            fill(x: gridLeft..<gridRight, y: 357..<360, color: gray)
            fill(x: 0..<1170, y: 2003..<2030, color: gray)
        }
        for (weekday, top, bottom, color) in EverytimeFixture.blocks {
            guard let column = columns.first(where: { $0.weekday == weekday }) else { continue }
            fill(x: Int(column.left)..<Int(column.right), y: top..<bottom, color: color)
        }
    }

    mutating func fill(x: Range<Int>, y: Range<Int>, color: RGB) {
        for row in y {
            for column in x {
                let offset = (row * width + column) * 4
                rgba[offset] = color.r
                rgba[offset + 1] = color.g
                rgba[offset + 2] = color.b
                rgba[offset + 3] = 255
            }
        }
    }

    var pixels: TimetablePixels? { TimetablePixels(width: width, height: height, rgba: rgba) }
}

@Suite struct TimetablePixelsTests {
    func fixtureColumns() throws -> [DayColumn] {
        try TimetableReader.columns(from: EverytimeFixture.all)
    }

    @Test func 크기와_바이트_수가_맞지_않으면_만들지_않는다() {
        #expect(TimetablePixels(width: 2, height: 2, rgba: [UInt8](repeating: 0, count: 15)) == nil)
        #expect(TimetablePixels(width: 0, height: 2, rgba: []) == nil)
        #expect(TimetablePixels(width: 2, height: 2, rgba: [UInt8](repeating: 0, count: 16)) != nil)
    }

    @Test func 세로_한_줄의_색을_위에서_아래로_뽑는다() throws {
        // 2×3 이미지: 왼쪽 열은 위부터 빨강·초록·파랑.
        let bytes: [UInt8] = [
            255, 0, 0, 255, 9, 9, 9, 255,
            0, 255, 0, 255, 9, 9, 9, 255,
            0, 0, 255, 255, 9, 9, 9, 255,
        ]
        let pixels = try #require(TimetablePixels(width: 2, height: 3, rgba: bytes))
        #expect(pixels.strip(atX: 0) == [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 255, b: 0), RGB(r: 0, g: 0, b: 255)])
        // 이미지 밖은 가장자리 열을 쓴다.
        #expect(pixels.strip(atX: -5) == pixels.strip(atX: 0))
        #expect(pixels.strip(atX: 99).first == RGB(r: 9, g: 9, b: 9))
    }

    @Test func 옅은_회색_행만_눈금줄_후보로_본다() throws {
        let image = SyntheticTimetableImage(columns: try fixtureColumns(), extraLines: false)
        // 칸에 거의 가려진 눈금줄은 후보에서 빠질 수 있다 (1093행: 5칸 중 4칸이 색 칸). 읽을 때 간격에 맞춰 채운다.
        let pixels = try #require(image.pixels)
        let rows = pixels.lineRows(left: 85, right: 1144)
        #expect(rows.contains(418))
        #expect(rows.contains(1903))
        #expect(!rows.contains(1093))
        #expect(!rows.contains(700))
    }

    @Test func 이미지_전체로_읽어도_줄과_칸_방식과_같은_결과다() throws {
        let columns = try fixtureColumns()
        let expected = try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
        let pixels = try #require(SyntheticTimetableImage(columns: columns, extraLines: false).pixels)

        let draft = try TimetableReader.read(observations: EverytimeFixture.all, pixels: pixels)

        #expect(draft == expected)
        #expect(draft.rows.count == 14)
    }

    @Test func 머리글_아래_선과_아래_회색_띠가_있어도_같은_결과다() throws {
        let columns = try fixtureColumns()
        let expected = try TimetableReader.read(
            observations: EverytimeFixture.all,
            columns: columns,
            strips: EverytimeFixture.strips(for: columns),
            lineRows: EverytimeFixture.lineRows
        )
        let pixels = try #require(SyntheticTimetableImage(columns: columns, extraLines: true).pixels)

        let draft = try TimetableReader.read(observations: EverytimeFixture.all, pixels: pixels)

        #expect(draft == expected)
    }

    @Test func 눈금이_없는_이미지는_눈금을_찾지_못했다고_알린다() throws {
        let blank = try #require(TimetablePixels(width: 1170, height: 100, rgba: [UInt8](repeating: 255, count: 1170 * 100 * 4)))
        #expect(throws: TimetableReadError.noGrid) {
            try TimetableReader.read(observations: EverytimeFixture.all, pixels: blank)
        }
    }

    @Test func 요일_머리글이_없으면_요일을_찾지_못했다고_알린다() throws {
        let blank = try #require(TimetablePixels(width: 10, height: 10, rgba: [UInt8](repeating: 255, count: 400)))
        #expect(throws: TimetableReadError.noDayHeaders) {
            try TimetableReader.read(observations: [], pixels: blank)
        }
    }

    // MARK: 규칙적인 눈금줄 고르기

    @Test func 간격이_맞지_않는_뒤쪽_줄은_버린다() {
        #expect(TimetableReader.regularLines([100, 235, 370, 505, 800]) == [100, 235, 370, 505])
    }

    @Test func 간격이_맞지_않는_앞쪽_줄은_버린다() {
        #expect(TimetableReader.regularLines([40, 100, 235, 370]) == [100, 235, 370])
    }

    @Test func 가려진_줄은_간격에_맞춰_채운다() {
        #expect(TimetableReader.regularLines([100, 235, 505, 640]) == [100, 235, 370, 505, 640])
    }

    @Test func 줄이_둘_이하면_그대로_둔다() {
        #expect(TimetableReader.regularLines([100]) == [100])
        #expect(TimetableReader.regularLines([100, 300]) == [100, 300])
    }

    @Test func 간격이_너무_좁은_후보뿐이면_그대로_돌려준다() {
        #expect(TimetableReader.regularLines([100, 105, 108]) == [100, 105, 108])
    }
}
