/// 과목 색상. 화면에서 SwiftUI 색으로 바꿔 쓴다 (LectureCore는 SwiftUI를 모른다).
public enum SubjectColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    public var displayName: String {
        switch self {
        case .red: "빨강"
        case .orange: "주황"
        case .yellow: "노랑"
        case .green: "초록"
        case .mint: "민트"
        case .teal: "청록"
        case .blue: "파랑"
        case .indigo: "남색"
        case .purple: "보라"
        case .pink: "분홍"
        case .gray: "회색"
        }
    }
}
