import Foundation
import LectureCore
import MediaPlayer

/// `MPRemoteCommandCenter`로 이어폰·키보드 재생 키를 받고, `MPNowPlayingInfoCenter`에 재생 중인 녹음을 올린다.
@MainActor
final class SystemRemoteCommands: RemoteCommandRegistering, NowPlayingPublishing {
    var handler: (@MainActor (RemoteCommand) -> Bool)?

    init(skipInterval: TimeInterval) {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        bind(center.playCommand, to: .play)
        bind(center.pauseCommand, to: .pause)
        bind(center.togglePlayPauseCommand, to: .togglePlayPause)
        bind(center.skipForwardCommand, to: .skipForward)
        bind(center.skipBackwardCommand, to: .skipBackward)
        bind(center.nextTrackCommand, to: .nextTrack)
        bind(center.previousTrackCommand, to: .previousTrack)
    }

    /// 시스템 재생 키의 건너뛰기 길이를 바꾼다.
    func setSkipInterval(_ skipInterval: TimeInterval) {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
    }

    private func bind(_ command: MPRemoteCommand, to remote: RemoteCommand) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            // 시스템이 어느 스레드에서든 부를 수 있어 메인 스레드로 옮겨 처리한다.
            let handled = Self.onMain { self?.handler?(remote) ?? false }
            return handled ? .success : .noActionableNowPlayingItem
        }
    }

    nonisolated private static func onMain(_ work: @MainActor () -> Bool) -> Bool {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    func update(_ info: NowPlayingInfo?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let info else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.subjectName,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? Double(info.rate) : 0.0,
        ]
        center.playbackState = info.isPlaying ? .playing : .paused
    }
}
