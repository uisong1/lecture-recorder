import AppKit
import SwiftUI

/// DESIGN.md의 토큰을 SwiftUI로 옮긴 것. 화면에서는 hex를 직접 쓰지 않고 여기 값만 쓴다.
/// 어두운 모드에서는 DESIGN.md의 어두운 타일 색으로 바뀐다.
enum Design {
    enum Palette {
        /// Action Blue. 눌러야 하는 모든 것에 쓰는 유일한 강조색.
        static let primary = Color(light: 0x0066CC, dark: 0x2997FF)
        static let primaryFocus = Color(hex: 0x0071E3)
        static let ink = Color(light: 0x1D1D1F, dark: 0xFFFFFF)
        static let inkMuted = Color(light: 0x7A7A7A, dark: 0xCCCCCC)
        static let canvas = Color(light: 0xFFFFFF, dark: 0x272729)
        static let parchment = Color(light: 0xF5F5F7, dark: 0x252527)
        static let pearl = Color(light: 0xFAFAFC, dark: 0x2A2A2C)
        static let hairline = Color(light: 0xE0E0E0, dark: 0x3A3A3C)
        static let onPrimary = Color.white
    }

    enum Radius {
        static let sm: CGFloat = 8
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

    /// 글자 크기·굵기·자간. 굵기는 300 / 400 / 600만 쓴다(500 금지).
    enum Text {
        case displayLg, tagline, body, bodyStrong, caption, captionStrong, finePrint

        var font: Font {
            switch self {
            case .displayLg: .system(size: 40, weight: .semibold)
            case .tagline: .system(size: 21, weight: .semibold)
            case .body: .system(size: 17, weight: .regular)
            case .bodyStrong: .system(size: 17, weight: .semibold)
            case .caption: .system(size: 14, weight: .regular)
            case .captionStrong: .system(size: 14, weight: .semibold)
            case .finePrint: .system(size: 12, weight: .regular)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .displayLg: 0
            case .tagline: 0.231
            case .body, .bodyStrong: -0.374
            case .caption, .captionStrong: -0.224
            case .finePrint: -0.12
            }
        }
    }
}

extension View {
    func designText(_ style: Design.Text) -> some View {
        font(style.font).tracking(style.tracking)
    }

    /// 화면 바탕. 흰색과 파치먼트를 번갈아 써서 구역을 나눈다.
    func designCanvas(_ color: Color = Design.Palette.canvas) -> some View {
        background(color)
    }
}

/// 누르면 0.95배로 줄어드는 알약 버튼. DESIGN.md의 `button-primary` / `button-secondary-pill`.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, dark }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .designText(.body)
            .foregroundStyle(foreground)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .background(background, in: Capsule())
            .overlay {
                if kind == .secondary { Capsule().strokeBorder(Design.Palette.primary, lineWidth: 1) }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .dark: Design.Palette.onPrimary
        case .secondary: Design.Palette.primary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Design.Palette.primary
        case .secondary: .clear
        case .dark: Design.Palette.ink.opacity(0.9)
        }
    }
}

/// 목록 행 안의 작은 글자 링크(`text-link`).
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .designText(.caption)
            .foregroundStyle(Design.Palette.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillDark: PillButtonStyle { PillButtonStyle(kind: .dark) }
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
