#if canImport(SwiftData)
import Foundation

/// "이어서 듣기" 바로가기: 지난번에 듣다 만 녹음을 고르고 한 줄 안내 글을 만든다.
public enum ResumeListening {
    /// 이어 들을 녹음. 가장 최근에 재생한 것부터 보며 아래에 걸리면 건너뛴다.
    /// - 들던 위치가 없는 것 (한 번도 안 들었거나 처음 위치로 돌아간 것)
    /// - 끝까지 들은 것 (남은 시간이 `PlaybackController.finishedMargin` 이하)
    /// - 파일이 없어 재생할 수 없는 것
    /// 휴지통으로 보낸 녹음은 목록에서 이미 지워져 후보에 없다.
    /// 재생 시각을 기록하기 전의 녹음(`lastPlayedAt == nil`)은 가장 오래된 것으로 본다.
    public static func pick(from recordings: [Recording], isPlayable: (Recording) -> Bool) -> Recording? {
        recordings
            .filter(isUnfinished)
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .first(where: isPlayable)
    }

    /// 들던 위치가 있고 끝까지 듣지 않은 녹음인지.
    static func isUnfinished(_ recording: Recording) -> Bool {
        let position = recording.lastPlayedPosition
        return position > 0 && position < recording.duration - PlaybackController.finishedMargin
    }

    /// 남은 시간(초). 0 밑으로 내려가지 않는다.
    public static func remaining(of recording: Recording) -> TimeInterval {
        max(recording.duration - recording.lastPlayedPosition, 0)
    }

    /// "23분", "1시간 5분". 올림해서 세고 1분 밑으로는 "1분"으로 보인다.
    public static func remainingText(seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded(.up)), 1)
        guard minutes >= 60 else { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    /// "이어서 듣기: 자료구조 · 10월 26일 (남은 23분)". 과목이 없으면 "미분류".
    public static func lineText(for recording: Recording, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.month, .day], from: recording.startedAt)
        let date = "\(day.month ?? 0)월 \(day.day ?? 0)일"
        let subject = recording.subject?.name ?? SubjectManager.unclassifiedName
        return "이어서 듣기: \(subject) · \(date) (남은 \(remainingText(seconds: remaining(of: recording))))"
    }
}
#endif
