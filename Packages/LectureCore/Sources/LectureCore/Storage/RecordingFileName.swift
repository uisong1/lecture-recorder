import Foundation

/// 녹음 파일 이름에서 시작 시각을 읽는다. 지금 규칙(`10-28 수 13-30`)과 예전 규칙(`2026-03-02_1000`)을 모두 읽고,
/// 같은 이름이 있을 때 붙는 `_2` 같은 번호는 무시한다.
public enum RecordingFileName {
    /// "2026년 2학기" → 2026. 읽지 못하면 nil.
    public static func year(fromSemester semester: String) -> Int? {
        guard let range = semester.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(semester[range])
    }

    /// 확장자와 번호를 뗀 이름.
    static func stem(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 파일 이름(확장자 포함 가능)에서 시작 시각을 읽는다. 지금 규칙은 연도가 이름에 없어 `yearHint`가 필요하다.
    public static func startedAt(fromFileName fileName: String, yearHint: Int?, calendar: Calendar) -> Date? {
        let base = stem(fileName)
        if let date = parse(base, yearHint: yearHint, calendar: calendar) { return date }
        // 같은 이름 뒤에 붙은 `_2`, `_3` …을 떼고 한 번 더 읽는다.
        if let underscore = base.lastIndex(of: "_") {
            let number = base[base.index(after: underscore)...]
            if !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return parse(String(base[..<underscore]), yearHint: yearHint, calendar: calendar)
            }
        }
        return nil
    }

    private static func parse(_ base: String, yearHint: Int?, calendar: Calendar) -> Date? {
        // 예전 규칙: 2026-03-02_1000
        let legacy = base.split(separator: "_", omittingEmptySubsequences: false)
        if legacy.count == 2 {
            let date = legacy[0].split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
            let time = legacy[1]
            if date.count == 3, legacy[0].count == 10, time.count == 4, let hhmm = Int(time) {
                return makeDate(year: date[0], month: date[1], day: date[2], hour: hhmm / 100, minute: hhmm % 100, calendar: calendar)
            }
        }
        // 지금 규칙: 10-28 수 13-30
        let parts = base.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = yearHint else { return nil }
        let day = parts[0].split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        let time = parts[2].split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard day.count == 2, time.count == 2, parts[0].count == 5, parts[2].count == 5,
              Weekday.allCases.contains(where: { $0.shortName == parts[1] })
        else { return nil }
        return makeDate(year: year, month: day[0], day: day[1], hour: time[0], minute: time[1], calendar: calendar)
    }

    /// 달력에 없는 날짜(2월 30일 등)와 범위 밖 시각은 nil.
    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard check.year == year, check.month == month, check.day == day, check.hour == hour, check.minute == minute else { return nil }
        return date
    }
}
