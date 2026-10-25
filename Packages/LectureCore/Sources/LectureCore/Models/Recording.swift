#if canImport(SwiftData)
import Foundation
import SwiftData

/// 녹음 한 건의 메타데이터. 오디오 파일 자체는 `Storage`가 관리한다.
@Model
public final class Recording {
    public var title: String
    /// nil이면 미분류.
    public var subject: Subject?
    public var startedAt: Date
    /// 길이(초).
    public var duration: TimeInterval
    /// 녹음 폴더(`Recordings/`) 기준 상대 경로. 앱 폴더가 바뀌어도 깨지지 않게 상대 경로로 둔다.
    public var relativePath: String
    /// 녹음을 지우면 북마크도 함께 지운다.
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.recording)
    public var bookmarks: [Bookmark] = []
    /// 마지막으로 듣던 위치(초). 0이면 처음부터 듣는다.
    public var lastPlayedPosition: TimeInterval = 0
    /// 녹음 중 앱이 꺼져서 남은 파일로 되살린 녹음이면 true.
    public var wasRecovered: Bool = false

    public init(title: String, subject: Subject?, startedAt: Date, duration: TimeInterval, relativePath: String) {
        self.title = title
        self.subject = subject
        self.startedAt = startedAt
        self.duration = duration
        self.relativePath = relativePath
    }
}

extension Recording {
    /// 예전 버전은 되살린 녹음의 제목 끝에 이 표시를 붙였다.
    static let legacyRecoveredSuffix = " (복구됨)"

    /// 되살린 녹음인지. 표시가 제목에 붙은 예전 기록도 포함한다.
    public var isRecovered: Bool {
        wasRecovered || title.hasSuffix(Self.legacyRecoveredSuffix)
    }

    /// 시점 순서로 정렬한 북마크.
    public var sortedBookmarks: [Bookmark] {
        bookmarks.sorted { $0.time < $1.time }
    }
}
#endif
