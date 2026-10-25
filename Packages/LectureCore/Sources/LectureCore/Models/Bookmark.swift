#if canImport(SwiftData)
import Foundation
import SwiftData

/// 녹음의 중요 구간 표시. 시점(초)과 메모를 가진다.
@Model
public final class Bookmark {
    /// 녹음 안에서의 시점(초).
    public var time: TimeInterval
    public var note: String
    public var createdAt: Date
    public var recording: Recording?

    public init(time: TimeInterval, note: String = "", createdAt: Date, recording: Recording? = nil) {
        self.time = time
        self.note = note
        self.createdAt = createdAt
        self.recording = recording
    }
}
#endif
