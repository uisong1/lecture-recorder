import AppKit
import CoreText
import LectureCore
import SwiftUI

/// DESIGN.md(D1: 흑백 + Pretendard)의 토큰을 SwiftUI로 옮긴 것. 화면에서는 hex를 직접 쓰지 않고 여기 값만 쓴다.
/// 색은 흑백뿐이고, 빨강은 녹음 중 표시(`recording`)에만 쓴다. 어두운 모드에서는 흑백이 뒤집힌다.
enum Design {
    enum Palette {
        /// 주 버튼·선택·스위치·진행 막대에 쓰는 검정(어두운 모드에서는 흰색). 따로 강조색은 없다.
        static let primary = Color(light: 0x1D1D1F, dark: 0xFFFFFF)
        /// 키보드 포커스 링. 주 색과 같다.
        static let primaryFocus = primary
        static let ink = Color(light: 0x1D1D1F, dark: 0xFFFFFF)
        static let inkMuted = Color(light: 0x7A7A7A, dark: 0xA1A1A6)
        /// 비활성, 입력칸 안내 글자.
        static let inkFaint = Color(light: 0xA1A1A6, dark: 0x6E6E73)
        /// 카드·입력칸·목록 묶음 바탕.
        static let canvas = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
        /// 창 바탕.
        static let parchment = Color(light: 0xF5F5F7, dark: 0x000000)
        static let pearl = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
        /// 행 구분선, 옅은 칸, 고른 탭 바탕.
        static let fill = Color(light: 0xF0F0F2, dark: 0x2C2C2E)
        /// 사이드바 바탕.
        static let sidebar = Color(light: 0xECECEE, dark: 0x161618)
        /// 카드 테두리 1px.
        static let hairline = Color(light: 0xE5E5E7, dark: 0x38383A)
        /// 보조 버튼·입력칸 테두리.
        static let border = Color(light: 0xD2D2D7, dark: 0x48484A)
        /// `primary` 위의 글자·아이콘.
        static let onPrimary = Color(light: 0xFFFFFF, dark: 0x1D1D1F)
        /// 녹음 중 표시에만 쓰는 빨강(빨간 점, 노치 막대, 메뉴 막대 녹음 아이콘). 버튼·삭제·오류에는 쓰지 않는다.
        static let recording = Color(light: 0xFF3B30, dark: 0xFF453A)
        /// 경고·오류 문구. D1에서는 빨강을 쓰지 않고 글자색과 같다. 경고 아이콘과 굵기로 구분한다.
        static let danger = ink
        /// 노치처럼 모드와 상관없이 늘 검정·흰색인 곳.
        static let alwaysBlack = Color.black
        static let alwaysWhite = Color.white
        /// 노치 안의 마이크 칸(검정 위의 짙은 회색).
        static let notchTile = Color(hex: 0x2A2A2C)
        /// 노치 일시정지 막대(멈춘 회색).
        static let notchIdleBar = Color(hex: 0x8E8E93)
    }

    enum Radius {
        static let sm: CGFloat = 8
        /// 안내 줄·입력칸.
        static let md: CGFloat = 11
        /// 목록 묶음·설정 묶음.
        static let group: CGFloat = 14
        /// 카드.
        static let lg: CGFloat = 18
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 17
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    /// 글자 크기·굵기. 글꼴은 Pretendard(400/600/700)이고, 불러오지 못하면 시스템 글꼴로 돌아간다.
    enum Text {
        case hero, displayLg, tagline, body, bodyStrong, caption, captionStrong, finePrint

        var font: Font {
            switch self {
            case .hero: Design.font(size: 64, weight: .semibold).monospacedDigit()
            case .displayLg: Design.font(size: 26, weight: .bold)
            case .tagline: Design.font(size: 19, weight: .semibold)
            case .body: Design.font(size: 15, weight: .regular)
            case .bodyStrong: Design.font(size: 15, weight: .semibold)
            case .caption: Design.font(size: 13, weight: .regular)
            case .captionStrong: Design.font(size: 13, weight: .semibold)
            case .finePrint: Design.font(size: 12, weight: .regular)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .hero: -1.6
            case .displayLg: -0.6
            case .tagline: -0.3
            case .body, .bodyStrong, .caption, .captionStrong, .finePrint: 0
            }
        }
    }

    /// Pretendard 글꼴. 굵기는 regular/semibold/bold만 쓴다. 앱이 글꼴을 등록하지 못했으면 시스템 글꼴이다.
    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        guard DesignFonts.isRegistered else { return .system(size: size, weight: weight) }
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Pretendard-Bold"
        case .semibold, .medium: name = "Pretendard-SemiBold"
        default: name = "Pretendard-Regular"
        }
        return .custom(name, size: size)
    }
}

/// 앱 번들에 넣은 Pretendard를 앱 시작 때 한 번 등록한다.
enum DesignFonts {
    nonisolated(unsafe) private(set) static var isRegistered = false
    static let fileNames = ["Pretendard-Regular", "Pretendard-SemiBold", "Pretendard-Bold"]

    /// 등록하지 못한 글꼴이 하나라도 있으면 시스템 글꼴을 쓴다(로그를 남긴다).
    static func register(bundle: Bundle = .main) {
        var allRegistered = true
        for name in fileNames {
            guard let url = bundle.url(forResource: name, withExtension: "otf") else {
                Log.app.error("글꼴 파일을 찾지 못했습니다: \(name, privacy: .public)")
                allRegistered = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // 이미 등록된 경우도 실패로 오지만, 글꼴은 쓸 수 있다.
                let description = error?.takeRetainedValue().localizedDescription ?? "알 수 없음"
                if NSFont(name: name, size: 12) == nil {
                    Log.app.error("글꼴 등록 실패: \(name, privacy: .public) \(description, privacy: .public)")
                    allRegistered = false
                }
            }
        }
        isRegistered = allRegistered
    }
}

extension View {
    func designText(_ style: Design.Text) -> some View {
        font(style.font).tracking(style.tracking)
    }

    /// 화면 바탕. 창 바탕은 옅은 회색(parchment), 카드는 흰색(canvas).
    func designCanvas(_ color: Color = Design.Palette.canvas) -> some View {
        background(color)
    }

    /// 흰 카드: 1px 테두리, 모서리 18, 그림자 없음 (DESIGN.md "카드").
    func designCard(padding: CGFloat = Design.Spacing.lg, radius: CGFloat = Design.Radius.lg) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(Design.Palette.canvas, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Design.Palette.hairline, lineWidth: 1))
    }
}

/// 누르면 0.95배로 줄어드는 알약 버튼. DESIGN.md의 `button-primary` / `button-secondary-pill`.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, dark }
    var kind: Kind = .primary
    /// 좁은 곳(메뉴 막대 창)용. 글자와 여백을 줄인다.
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, kind: kind, isCompact: isCompact, isPressed: configuration.isPressed, foreground: foreground, background: background)
    }

    /// 키보드 포커스는 `Environment`로만 알 수 있어서 뷰로 한 번 감싼다.
    private struct PillLabel<Label: View>: View {
        let label: Label
        let kind: Kind
        let isCompact: Bool
        let isPressed: Bool
        let foreground: Color
        let background: Color
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .designText(isCompact ? .captionStrong : .bodyStrong)
                .foregroundStyle(foreground)
                .padding(.vertical, isCompact ? 6 : 11)
                .padding(.horizontal, isCompact ? 12 : 22)
                .background(background, in: Capsule())
                .overlay {
                    if kind == .secondary { Capsule().strokeBorder(Design.Palette.border, lineWidth: 1) }
                }
                .overlay {
                    // 포커스 링: 2px primaryFocus (DESIGN.md)
                    if isFocused { Capsule().inset(by: -4).strokeBorder(Design.Palette.primaryFocus, lineWidth: 2) }
                }
                .focusEffectDisabled()
                .scaleEffect(isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .dark: Design.Palette.onPrimary
        case .secondary: Design.Palette.ink
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Design.Palette.primary
        case .secondary: Design.Palette.canvas
        case .dark: Design.Palette.ink
        }
    }
}

/// 목록 행 안의 작은 글자 링크. 검정 굵은 글자에 밑줄.
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .designText(.captionStrong)
            .underline()
            .foregroundStyle(Design.Palette.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// 위젯 줄 오른쪽의 아이콘만 있는 버튼. 회색 아이콘, 눌리면 0.95배.
struct IconPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconLabel(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct IconLabel<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.system(size: 16))
                .foregroundStyle(Design.Palette.inkMuted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// 위젯 줄의 주 동작(정지·시작) 버튼. 검정 동그라미 안에 흰 아이콘.
struct IconFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconLabel(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct IconLabel<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.system(size: 14))
                .foregroundStyle(Design.Palette.onPrimary)
                .frame(width: 32, height: 32)
                .background(Design.Palette.primary, in: Circle())
                .contentShape(Circle())
                .scaleEffect(isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

extension ButtonStyle where Self == IconPlainButtonStyle {
    static var iconPlain: IconPlainButtonStyle { IconPlainButtonStyle() }
}

extension ButtonStyle where Self == IconFilledButtonStyle {
    static var iconFilled: IconFilledButtonStyle { IconFilledButtonStyle() }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillDark: PillButtonStyle { PillButtonStyle(kind: .dark) }
    static var pillCompact: PillButtonStyle { PillButtonStyle(kind: .primary, isCompact: true) }
    static var pillSecondaryCompact: PillButtonStyle { PillButtonStyle(kind: .secondary, isCompact: true) }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    static var textLink: TextLinkButtonStyle { TextLinkButtonStyle() }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 밝은 모드와 어두운 모드에서 다른 색을 낸다.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// 녹음·전사·모든 녹음 화면이 함께 쓰는 틀 (2026-11-28 정렬 시안 A).
/// 같은 왼쪽 여백에서 큰 제목 → 회색 요약 → 오른쪽 버튼, 그 아래 내용. 탭을 바꿔도 제목과 카드 왼쪽 끝이 같다.
enum ScreenLayout {
    /// 화면 안 좌우 여백.
    static let horizontalPadding: CGFloat = 28
    static let topPadding: CGFloat = 24
    /// 내용 최대 폭. 창을 넓히면 내용도 함께 넓어지고(오른쪽이 비어 보이지 않게, 2026-11-28 사용자 피드백),
    /// 아주 넓은 창에서만 줄이 너무 길어지지 않게 여기서 멈춘다. 왼쪽 정렬.
    static let maxContentWidth: CGFloat = 1200
}

/// 화면 맨 위 머리: 큰 제목, 회색 요약 한 줄, 오른쪽 버튼들.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    var titleID: String?

    init(_ title: String, subtitle: String? = nil, titleID: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleID = titleID
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title)
                    .designText(.displayLg)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(2)
                    .accessibilityIdentifier(titleID ?? "screenTitle")
                if let subtitle {
                    Text(subtitle)
                        .designText(.caption)
                        .foregroundStyle(Design.Palette.inkMuted)
                }
            }
            Spacer(minLength: Design.Spacing.sm)
            HStack(spacing: Design.Spacing.xs) { trailing }
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleID: String? = nil) {
        self.init(title, subtitle: subtitle, titleID: titleID) { EmptyView() }
    }
}

extension View {
    /// 화면 내용을 공통 틀(왼쪽 정렬, 같은 여백, 최대 폭)에 놓는다.
    func screenColumn() -> some View {
        frame(maxWidth: ScreenLayout.maxContentWidth, alignment: .topLeading)
            .padding(.horizontal, ScreenLayout.horizontalPadding)
            .padding(.top, ScreenLayout.topPadding)
            .padding(.bottom, Design.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
