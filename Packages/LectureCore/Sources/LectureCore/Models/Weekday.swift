/// 요일. 원시값은 `Calendar`의 weekday 값(일=1 … 토=7)과 같다.
public enum Weekday: Int, CaseIterable, Comparable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// 월요일부터 시작하는 순서. 시간표 화면에 쓴다.
    public static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    /// 한 글자 한국어 이름 ("월").
    public var shortName: String {
        switch self {
        case .sunday: "일"
        case .monday: "월"
        case .tuesday: "화"
        case .wednesday: "수"
        case .thursday: "목"
        case .friday: "금"
        case .saturday: "토"
        }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.mondayIndex < rhs.mondayIndex
    }

    /// 전날. 월요일의 전날은 일요일.
    public var previous: Weekday {
        Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1) ?? .sunday
    }

    private var mondayIndex: Int { (rawValue + 5) % 7 }
}
