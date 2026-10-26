import Foundation
import Testing
@testable import LectureCore

@Suite struct SkipIntervalTests {
    func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SkipIntervalTests-\(UUID().uuidString)") ?? .standard
    }

    @Test func 선택지는_5_10_15_30_60초이고_기본은_15초다() {
        #expect(SkipInterval.allCases.map(\.seconds) == [5, 10, 15, 30, 60])
        #expect(SkipInterval.default == .seconds15)
        #expect(SkipInterval.load(from: makeDefaults()) == .seconds15)
    }

    @Test func 저장한_길이를_다시_읽는다() {
        let defaults = makeDefaults()
        for interval in SkipInterval.allCases {
            interval.save(to: defaults)
            #expect(SkipInterval.load(from: defaults) == interval)
        }
    }

    @Test func 잘못된_저장값이면_15초로_돌아간다() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: SkipInterval.defaultsKey)
        #expect(SkipInterval.load(from: defaults) == .seconds15)
        defaults.set("abc", forKey: SkipInterval.defaultsKey)
        #expect(SkipInterval.load(from: defaults) == .seconds15)
        defaults.set(-15, forKey: SkipInterval.defaultsKey)
        #expect(SkipInterval.load(from: defaults) == .seconds15)
    }

    @Test func 글자와_아이콘_이름은_길이를_따른다() {
        #expect(SkipInterval.seconds30.label == "30초")
        #expect(SkipInterval.seconds5.symbolName(forward: true) == "goforward.5")
        #expect(SkipInterval.seconds60.symbolName(forward: false) == "gobackward.60")
    }
}
