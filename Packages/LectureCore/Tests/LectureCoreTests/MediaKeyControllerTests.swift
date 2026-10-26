#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
final class FakeRemoteCommands: RemoteCommandRegistering {
    var handler: (@MainActor (RemoteCommand) -> Bool)?
    func send(_ command: RemoteCommand) -> Bool { handler?(command) ?? false }
}

@MainActor
final class FakeNowPlaying: NowPlayingPublishing {
    private(set) var updates: [NowPlayingInfo?] = []
    func update(_ info: NowPlayingInfo?) { updates.append(info) }
}

@MainActor
@Suite struct MediaKeyControllerTests {
    final class Flag { var isRecording = false; var time = date(2026, 3, 2, 10, 0) }

    let player = FakeAudioPlayer()
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    let container: ModelContainer
    let flag = Flag()
    let commands = FakeRemoteCommands()
    let nowPlaying = FakeNowPlaying()

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        player.durationForNextLoad = 600
    }

    func make(output: AudioOutputKind = .builtInSpeaker) -> (PlaybackController, MediaKeyController) {
        let defaults = UserDefaults(suiteName: "MediaKeyControllerTests-\(UUID().uuidString)") ?? .standard
        let flag = flag
        let playback = PlaybackController(
            player: player,
            storage: RecordingStorage(root: root, files: FakeFileStore()),
            defaults: defaults,
            isRecording: { flag.isRecording },
            outputInspector: FakeAudioOutput(output)
        )
        let keys = MediaKeyController(playback: playback, commands: commands, nowPlaying: nowPlaying, now: { flag.time })
        return (playback, keys)
    }

    func makeRecording(_ path: String = "자료구조/2026-03-02_1000.m4a") -> Recording {
        Recording(title: "자료구조 3주차", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 60, relativePath: path)
    }

    @Test func 재생과_일시정지_키가_동작한다() {
        let (playback, _) = make()
        playback.select(makeRecording())
        #expect(commands.send(.play))
        #expect(playback.isPlaying)
        #expect(commands.send(.pause))
        #expect(!playback.isPlaying)
        #expect(commands.send(.togglePlayPause))
        #expect(playback.isPlaying)
        #expect(commands.send(.togglePlayPause))
        #expect(!playback.isPlaying)
    }

    @Test func 건너뛰기_키는_15초씩_움직인다() {
        let (playback, _) = make()
        playback.select(makeRecording())
        #expect(commands.send(.skipForward))
        #expect(player.currentTime == PlaybackController.skipInterval)
        #expect(commands.send(.skipBackward))
        #expect(player.currentTime == 0)
    }

    @Test func 녹음_중_스피커면_재생_키를_무시한다() {
        flag.isRecording = true
        let (playback, _) = make(output: .builtInSpeaker)
        playback.select(makeRecording())
        #expect(!commands.send(.play))
        #expect(!commands.send(.togglePlayPause))
        #expect(!playback.isPlaying)
        #expect(!playback.isConfirmingPlayback)
    }

    @Test func 녹음_중_이어폰이면_재생_키가_동작한다() {
        flag.isRecording = true
        let (playback, _) = make(output: .external)
        playback.select(makeRecording())
        #expect(commands.send(.play))
        #expect(playback.isPlaying)
    }

    @Test func 선택된_녹음이_없으면_모든_키를_무시한다() {
        let (playback, _) = make()
        for command in [RemoteCommand.play, .pause, .togglePlayPause, .skipForward, .skipBackward, .nextTrack, .previousTrack] {
            #expect(!commands.send(command))
        }
        #expect(!playback.isPlaying)
    }

    @Test func 이전_다음_키는_북마크_이어_듣기가_아니면_무시한다() {
        let (playback, _) = make()
        playback.select(makeRecording())
        #expect(!commands.send(.nextTrack))
        #expect(!commands.send(.previousTrack))
    }

    @Test func 이전_다음_키는_북마크_이어_듣기_중에_구간을_옮긴다() {
        let (playback, _) = make()
        // 북마크가 녹음 길이 안에 있어야 구간이 만들어진다.
        let recording = Recording(title: "녹음", subject: nil, startedAt: date(2026, 3, 2, 10, 0), duration: 600, relativePath: "자료구조/2026-03-02_1000.m4a")
        container.mainContext.insert(recording)
        let entries = [100.0, 300].map { time -> BookmarkEntry in
            let bookmark = Bookmark(time: time, createdAt: date(2026, 3, 2, 11, 0), recording: recording)
            container.mainContext.insert(bookmark)
            return BookmarkEntry(bookmark: bookmark, recording: recording)
        }
        playback.startBookmarkTour(entries: entries)
        #expect(playback.tourIndex == 0)
        #expect(commands.send(.nextTrack))
        #expect(playback.tourIndex == 1)
        #expect(commands.send(.previousTrack))
        #expect(playback.tourIndex == 0)
    }

    @Test func 재생_중인_녹음을_지금_재생_중에_올린다() {
        let (playback, keys) = make()
        let recording = makeRecording()
        playback.select(recording)
        playback.play()
        keys.publish()
        #expect(nowPlaying.updates.count == 1)
        let info = nowPlaying.updates.first ?? nil
        #expect(info?.title == "자료구조 3주차")
        #expect(info?.subjectName == SubjectManager.unclassifiedName)
        #expect(info?.duration == 600)
        #expect(info?.isPlaying == true)
    }

    @Test func 바뀐_것이_없으면_다시_올리지_않는다() {
        let (playback, keys) = make()
        playback.select(makeRecording())
        playback.play()
        keys.publish()
        // 1초 뒤, 재생 위치도 1초 흐름: 시스템이 이어 세므로 올리지 않는다.
        flag.time = flag.time.addingTimeInterval(1)
        player.currentTime = 1
        keys.publish()
        #expect(nowPlaying.updates.count == 1)
    }

    @Test func 위치를_옮기면_다시_올린다() {
        let (playback, keys) = make()
        playback.select(makeRecording())
        playback.play()
        keys.publish()
        player.currentTime = 30
        keys.publish()
        #expect(nowPlaying.updates.count == 2)
    }

    @Test func 녹음을_닫으면_지금_재생_중을_내린다() {
        let (playback, keys) = make()
        playback.select(makeRecording())
        keys.publish()
        playback.select(nil)
        keys.publish()
        #expect(nowPlaying.updates.last == .some(nil))
    }
}
#endif
