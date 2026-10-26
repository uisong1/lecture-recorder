import Foundation

/// 재생 막대의 앞뒤 건너뛰기 길이. 설정에서 고르고, 재생 막대·이어폰 키가 같은 값을 쓴다.
public enum SkipInterval: Int, CaseIterable, Sendable {
    case seconds5 = 5
    case seconds10 = 10
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60

    /// 정해 둔 적이 없거나 잘못된 값일 때의 길이.
    public static let `default`: SkipInterval = .seconds15

    static let defaultsKey = "skipInterval"

    public var seconds: TimeInterval { TimeInterval(rawValue) }

    /// 설정 선택지와 도움말에 쓰는 글자 (예: "15초").
    public var label: String { "\(rawValue)초" }

    /// 버튼 아이콘 이름. 5·10·15·30·60초는 모두 SF Symbols에 있다.
    public func symbolName(forward: Bool) -> String {
        (forward ? "goforward." : "gobackward.") + String(rawValue)
    }

    /// 저장된 값을 읽는다. 없거나 선택지에 없는 값이면 기본값.
    public static func load(from defaults: UserDefaults) -> SkipInterval {
        guard let raw = defaults.object(forKey: defaultsKey) as? Int else { return .default }
        return SkipInterval(rawValue: raw) ?? .default
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
