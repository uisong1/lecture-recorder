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

    public init(title: String, subject: Subject?, startedAt: Date, duration: TimeInterval, relativePath: String) {
        self.title = title
        self.subject = subject
        self.startedAt = startedAt
        self.duration = duration
        self.relativePath = relativePath
    }
}
#endif
