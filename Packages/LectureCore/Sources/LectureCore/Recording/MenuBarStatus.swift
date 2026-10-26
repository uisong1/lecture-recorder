import Foundation

/// 메뉴 막대 창에 보일 녹음 상태. 값만 보고 문구와 동작 가능 여부를 정하는 순수한 로직이라 테스트하기 쉽다.
/// 실제 시작·정지·북마크는 부르는 쪽이 `RecordingController`로 한다.
public struct MenuBarStatus: Equatable, Sendable {
    public let isRecording: Bool
    public let isPaused: Bool
    public let isPermissionDenied: Bool
    public let subjectName: String
    public let elapsedText: String
    public let bookmarkCount: Int
    /// 시작하기 전에 알리는 "지금 녹음하면" 과목 이름.
    public let expectedSubjectName: String
    /// 일시정지가 오래 이어질 때 보일 안내. 일시정지 중이 아니면 항상 nil.
    public let pausedNotice: String?

    public init(
        isRecording: Bool,
        isPaused: Bool = false,
        isPermissionDenied: Bool = false,
        subjectName: String = "",
        elapsedText: String = "00:00",
        bookmarkCount: Int = 0,
        expectedSubjectName: String = "",
        pausedNotice: String? = nil
    ) {
        self.isRecording = isRecording
        self.isPaused = isPaused && isRecording
        self.isPermissionDenied = isPermissionDenied
        self.subjectName = subjectName
        self.elapsedText = elapsedText
        self.bookmarkCount = bookmarkCount
        self.expectedSubjectName = expectedSubjectName
        self.pausedNotice = isPaused && isRecording ? pausedNotice : nil
    }

    /// 메뉴 막대 아이콘 모양.
    public enum Icon: Equatable, Sendable {
        case idle, recording, paused
    }

    public var icon: Icon {
        if !isRecording { return .idle }
        return isPaused ? .paused : .recording
    }

    /// 창 맨 위 한 줄. 예: "녹음 중", "일시정지 중", "녹음 대기".
    public var headline: String {
        if !isRecording { return "녹음 대기" }
        return isPaused ? "일시정지 중" : "녹음 중"
    }

    /// 과목과 경과 시간. 녹음 중이 아니면 "지금 녹음하면" 안내.
    public var detail: String {
        if isRecording { return "\(subjectName) · \(elapsedText)" }
        return expectedSubjectName.isEmpty ? "" : "지금 녹음하면: \(expectedSubjectName)"
    }

    public var toggleTitle: String { isRecording ? "녹음 정지" : "녹음 시작" }

    /// 권한이 없으면 시작할 수 없다. 정지는 언제나 할 수 있다.
    public var canToggle: Bool { isRecording || !isPermissionDenied }

    public var canBookmark: Bool { isRecording && !isPaused }
    public var canPause: Bool { isRecording }
    public var pauseTitle: String { isPaused ? "재개" : "일시정지" }

    public var bookmarkTitle: String { "북마크 \(bookmarkCount)" }

    /// 권한이 꺼져 있을 때 시작 버튼 대신 보일 안내. 아니면 nil.
    public var permissionNotice: String? {
        guard isPermissionDenied, !isRecording else { return nil }
        return "마이크 권한이 꺼져 있어 녹음할 수 없습니다. 시스템 설정에서 켜 주세요."
    }
}

#if canImport(SwiftData)
extension RecordingController {
    /// 지금 컨트롤러 상태를 메뉴 막대용 값으로 옮긴다.
    public var menuBarStatus: MenuBarStatus {
        MenuBarStatus(
            isRecording: isRecording,
            isPaused: isPaused,
            isPermissionDenied: isPermissionDenied,
            subjectName: currentSubjectName,
            elapsedText: elapsedText,
            bookmarkCount: bookmarkTimes.count,
            expectedSubjectName: expectedSubjectName,
            pausedNotice: pausedNotice
        )
    }
}
#endif
