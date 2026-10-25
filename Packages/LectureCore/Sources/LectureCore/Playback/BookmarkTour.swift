#if canImport(SwiftData)
import Foundation

/// 북마크 이어 듣기의 한 구간: 녹음 하나의 `start`~`end`초.
public struct BookmarkTourStop: Equatable {
    public let recording: Recording
    public let start: TimeInterval
    public let end: TimeInterval

    public static func == (lhs: BookmarkTourStop, rhs: BookmarkTourStop) -> Bool {
        lhs.recording === rhs.recording && lhs.start == rhs.start && lhs.end == rhs.end
    }
}

/// 북마크만 차례로 이어 듣는 구간 계산. 시간·파일에 기대지 않는 순수 함수다.
@MainActor
public enum BookmarkTour {
    /// 북마크마다 재생하는 길이(초). 시작은 북마크 `PlaybackController.bookmarkLeadIn`초 앞이다.
    public static let segmentLength: TimeInterval = 30

    /// 한 녹음의 북마크 시점들을 재생 구간으로 바꾼다. 시점 순서로 정렬하고,
    /// 앞뒤 구간이 겹치거나 맞닿으면 하나로 잇는다. 구간은 `duration`(0 이하면 모르는 것으로 본다)을 넘지 않고,
    /// 녹음 끝 밖에 있는 북마크는 건너뛴다.
    public static func spans(bookmarkTimes: [TimeInterval], duration: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
        var result: [(start: TimeInterval, end: TimeInterval)] = []
        for time in bookmarkTimes.sorted() {
            let start = max(time - PlaybackController.bookmarkLeadIn, 0)
            var end = start + segmentLength
            if duration > 0 { end = min(end, duration) }
            guard start < end else { continue }
            if let last = result.last, start <= last.end {
                result[result.count - 1].end = max(last.end, end)
            } else {
                result.append((start, end))
            }
        }
        return result
    }

    /// 북마크 목록을 날짜순(오래된 녹음부터) 구간으로 바꾼다. 북마크가 없는 녹음은 나오지 않고,
    /// `isPlayable`이 false인(파일이 없는) 녹음은 건너뛴다.
    public static func stops(for entries: [BookmarkEntry], isPlayable: (Recording) -> Bool) -> [BookmarkTourStop] {
        var recordings: [Recording] = []
        var times: [ObjectIdentifier: [TimeInterval]] = [:]
        for entry in entries {
            let key = ObjectIdentifier(entry.recording)
            if times[key] == nil { recordings.append(entry.recording) }
            times[key, default: []].append(entry.bookmark.time)
        }
        return recordings
            .sorted { $0.startedAt < $1.startedAt }
            .filter(isPlayable)
            .flatMap { recording in
                spans(bookmarkTimes: times[ObjectIdentifier(recording)] ?? [], duration: recording.duration)
                    .map { BookmarkTourStop(recording: recording, start: $0.start, end: $0.end) }
            }
    }
}
#endif
