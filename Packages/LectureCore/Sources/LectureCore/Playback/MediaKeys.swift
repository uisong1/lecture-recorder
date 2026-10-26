import Foundation

/// 이어폰·키보드 재생 키 같은 시스템 재생 명령.
public enum RemoteCommand: Equatable, Sendable {
    case play, pause, togglePlayPause
    case skipForward, skipBackward
    case nextTrack, previousTrack
}

/// 시스템 재생 명령을 받는 곳. 앱 쪽 구현은 `MPRemoteCommandCenter`를 쓰고, 테스트에서는 가짜 구현을 쓴다.
@MainActor
public protocol RemoteCommandRegistering: AnyObject {
    /// 명령을 처리했으면 true. false면 시스템에 "할 수 있는 재생이 없다"고 답한다.
    var handler: (@MainActor (RemoteCommand) -> Bool)? { get set }
}

/// 잠금 화면·제어 센터의 "지금 재생 중"에 보여줄 내용.
public struct NowPlayingInfo: Equatable, Sendable {
    public var title: String
    public var subjectName: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var rate: Float
    public var isPlaying: Bool

    public init(title: String, subjectName: String, duration: TimeInterval, elapsed: TimeInterval, rate: Float, isPlaying: Bool) {
        self.title = title
        self.subjectName = subjectName
        self.duration = duration
        self.elapsed = elapsed
        self.rate = rate
        self.isPlaying = isPlaying
    }
}

/// "지금 재생 중" 정보를 시스템에 올리는 곳. nil이면 내린다.
@MainActor
public protocol NowPlayingPublishing: AnyObject {
    func update(_ info: NowPlayingInfo?)
}

#if canImport(SwiftData)
/// 재생 키 명령을 `PlaybackController`에 연결하고, 재생 중인 녹음을 "지금 재생 중"에 올린다.
@MainActor
public final class MediaKeyController {
    private let playback: PlaybackController
    private let nowPlaying: any NowPlayingPublishing
    private let now: @MainActor () -> Date
    private var lastPublished: NowPlayingInfo?
    private var lastPublishedAt = Date.distantPast

    /// 올려 둔 위치가 이 시간(초) 넘게 어긋나면 사용자가 이동한 것으로 보고 다시 올린다.
    static let seekTolerance: TimeInterval = 1.5

    public init(
        playback: PlaybackController,
        commands: any RemoteCommandRegistering,
        nowPlaying: any NowPlayingPublishing,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.playback = playback
        self.nowPlaying = nowPlaying
        self.now = now
        // 등록한 곳이 이 객체를 붙들게 한다 (이쪽은 등록한 곳을 붙들지 않으므로 순환하지 않는다).
        commands.handler = { [self] command in handle(command) }
    }

    /// 명령을 처리했으면 true. 불러온 녹음이 없거나, 녹음 중 스피커로 재생될 상황이면 무시한다
    /// (이어폰 키를 누르려고 이어폰을 뺀 채라면 소리가 녹음에 섞이므로 확인 없이 틀지 않는다).
    /// 이전·다음은 북마크 이어 듣기 중일 때만 쓴다.
    @discardableResult
    public func handle(_ command: RemoteCommand) -> Bool {
        guard playback.current != nil else { return false }
        switch command {
        case .play:
            guard !playback.playbackNeedsConfirmation else { return false }
            playback.play()
        case .togglePlayPause:
            // 재생 중이면 멈추는 것이므로 언제든 된다. 틀 때만 녹음 중 판단을 거친다.
            guard playback.isPlaying || !playback.playbackNeedsConfirmation else { return false }
            playback.togglePlayPause()
        case .pause:
            playback.pause()
        case .skipForward:
            playback.skipForward()
        case .skipBackward:
            playback.skipBackward()
        case .nextTrack:
            guard playback.isTouring else { return false }
            playback.nextTourStop()
        case .previousTrack:
            guard playback.isTouring else { return false }
            playback.previousTourStop()
        }
        publish()
        return true
    }

    /// 재생 상태가 바뀌었으면 "지금 재생 중"을 갱신한다. 화면 갱신 주기마다 불러도 된다.
    public func publish() {
        let info = currentInfo()
        guard let info else {
            if lastPublished != nil { nowPlaying.update(nil) }
            lastPublished = nil
            return
        }
        if let last = lastPublished, !needsRepublish(last: last, new: info) { return }
        nowPlaying.update(info)
        lastPublished = info
        lastPublishedAt = now()
    }

    private func currentInfo() -> NowPlayingInfo? {
        guard let recording = playback.current else { return nil }
        return NowPlayingInfo(
            title: recording.title,
            subjectName: recording.subject?.name ?? SubjectManager.unclassifiedName,
            duration: playback.duration,
            elapsed: playback.currentTime,
            rate: playback.rate.rawValue,
            isPlaying: playback.isPlaying
        )
    }

    private func needsRepublish(last: NowPlayingInfo, new: NowPlayingInfo) -> Bool {
        if last.title != new.title || last.subjectName != new.subjectName || last.duration != new.duration
            || last.rate != new.rate || last.isPlaying != new.isPlaying { return true }
        // 시스템이 재생 속도로 위치를 이어 세므로, 예상 위치에서 벗어났을 때만(이동) 다시 올린다.
        let elapsedSince = now().timeIntervalSince(lastPublishedAt)
        let expected = last.elapsed + (last.isPlaying ? elapsedSince * Double(last.rate) : 0)
        return abs(new.elapsed - expected) > Self.seekTolerance
    }
}
#endif
