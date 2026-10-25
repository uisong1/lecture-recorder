#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

/// 테스트에서 시간을 마음대로 흘리는 시계.
@MainActor
final class TestClock {
    private(set) var now: Date
    init(_ now: Date) { self.now = now }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
@Suite struct RecordingControllerTests {
    let container: ModelContainer
    let recorder = FakeAudioRecorder()
    let files = FakeFileStore()
    let permission = FakeMicrophonePermission(status: .granted)
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    var clock = date(2026, 3, 2, 10, 0)

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        converter = FakeAudioConverter(files: files)
    }

    let journal = InMemoryRecordingJournal()
    let sleep = FakeSleepPreventer()
    let lifecycle = FakeLifecycleEvents()

    let converter: FakeAudioConverter

    let overrunNotifier = FakeNotificationScheduler()

    func makeController(at time: Date, compressing: Bool = false, clock: TestClock? = nil) -> RecordingController {
        let storage = RecordingStorage(root: root, files: files)
        return RecordingController(
            context: container.mainContext,
            recorder: recorder,
            storage: storage,
            files: files,
            permission: permission,
            journal: journal,
            sleepPreventer: sleep,
            overrunNotifier: overrunNotifier,
            lifecycle: lifecycle,
            compressor: compressing
                ? RecordingCompressor(context: container.mainContext, storage: storage, files: files, converter: converter)
                : nil,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { clock?.now ?? time }
        )
    }

    func addSubjectWithSlot() throws -> Subject {
        let subjects = SubjectManager(context: container.mainContext)
        let subject = try subjects.add(name: "자료구조", color: .green)
        try ScheduleManager(context: container.mainContext)
            .add(subject: subject, weekday: .monday, start: TimeOfDay(hour: 10), end: TimeOfDay(hour: 11, minute: 15))
        return subject
    }

    @Test func 수업이_끝나고_10분_뒤에도_녹음_중이면_안내하고_알림을_한_번_보낸다() async throws {
        _ = try addSubjectWithSlot()  // 월 10:00~11:15
        let clock = TestClock(date(2026, 3, 2, 10, 0))
        let controller = makeController(at: clock.now, clock: clock)
        try await controller.start()

        clock.advance(by: 75 * 60 + 9 * 60 + 59)  // 11:24:59
        controller.checkOverrun()
        #expect(controller.overrunNotice == nil)
        #expect(overrunNotifier.notified.isEmpty)

        clock.advance(by: 1)  // 11:25:00
        controller.checkOverrun()
        controller.checkOverrun()
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.overrunNotice?.contains("자료구조 수업이 10분 전에 끝났습니다") == true)
        #expect(overrunNotifier.notified.count == 1)
    }

    @Test func 수업을_모르는_녹음은_종료_안내를_하지_않는다() async throws {
        let clock = TestClock(date(2026, 3, 2, 20, 0))
        let controller = makeController(at: clock.now, clock: clock)
        try await controller.start()

        clock.advance(by: 5 * 3600)
        controller.checkOverrun()

        #expect(controller.overrunNotice == nil)
        #expect(overrunNotifier.notified.isEmpty)
    }

    @Test func 정지하면_종료_안내가_사라진다() async throws {
        _ = try addSubjectWithSlot()
        let clock = TestClock(date(2026, 3, 2, 10, 0))
        let controller = makeController(at: clock.now, clock: clock)
        try await controller.start()
        clock.advance(by: 3 * 3600)
        #expect(controller.overrunNotice != nil)

        _ = try controller.stop()

        #expect(controller.overrunNotice == nil)
    }

    @Test func 시작_전에_고른_과목으로_저장한다() async throws {
        _ = try addSubjectWithSlot()
        let other = try SubjectManager(context: container.mainContext).add(name: "선형대수", color: .blue)
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        controller.subjectChoice = .subject(other.persistentModelID)
        #expect(controller.expectedSubjectName == "선형대수")

        try await controller.start()
        #expect(controller.currentSubjectName == "선형대수")
        let saved = try controller.stop()

        #expect(saved.subject?.name == "선형대수")
        #expect(saved.relativePath.hasPrefix("학기 미정/선형대수/"))
    }

    @Test func 수업_시간에도_미분류를_고를_수_있다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        controller.subjectChoice = .unclassified
        #expect(controller.expectedSubjectName == "미분류")

        try await controller.start()
        let saved = try controller.stop()

        #expect(saved.subject == nil)
    }

    @Test func 고르지_않으면_시간표로_분류한다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        #expect(controller.subjectChoice == .automatic)

        try await controller.start()

        #expect(controller.currentSubjectName == "자료구조")
    }

    @Test func 고른_과목은_한_번만_쓰고_자동으로_돌아간다() async throws {
        _ = try addSubjectWithSlot()
        let other = try SubjectManager(context: container.mainContext).add(name: "선형대수", color: .blue)
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        controller.subjectChoice = .subject(other.persistentModelID)
        try await controller.start()
        _ = try controller.stop()

        #expect(controller.subjectChoice == .automatic)
        #expect(controller.expectedSubjectName == "자료구조")
    }

    @Test func 고른_과목이_지워졌으면_시간표로_분류한다() async throws {
        _ = try addSubjectWithSlot()
        let subjects = SubjectManager(context: container.mainContext)
        let gone = try subjects.add(name: "선형대수", color: .blue)
        let id = gone.persistentModelID
        try subjects.delete(gone)
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        controller.subjectChoice = .subject(id)

        #expect(controller.expectedSubjectName == "자료구조")
    }

    @Test func 고를_수_있는_과목은_이름순이다() throws {
        let subjects = SubjectManager(context: container.mainContext)
        _ = try subjects.add(name: "자료구조", color: .green)
        _ = try subjects.add(name: "가정학", color: .blue)
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        #expect(controller.availableSubjects().map(\.name) == ["가정학", "자료구조"])
    }

    @Test func 녹음하는_동안만_잠자기를_막는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        #expect(!sleep.isActive)

        try await controller.start()
        #expect(sleep.isActive)

        try controller.pause()
        #expect(sleep.isActive)
        try controller.resume()
        #expect(sleep.isActive)

        try controller.stop()
        #expect(!sleep.isActive)
        #expect(sleep.beginCount == 1)
    }

    @Test func 녹음을_시작하지_못하면_잠자기를_막지_않는다() async throws {
        recorder.startError = RecordingError.insufficientStorage
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        await #expect(throws: RecordingError.self) { try await controller.start() }
        #expect(!sleep.isActive)
        #expect(sleep.beginCount == 0)
    }

    @Test func 잠자기_직전에_녹음을_저장하고_안내한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 600

        lifecycle.send(.willSleep)

        #expect(!controller.isRecording)
        #expect(!recorder.isRecording)
        #expect(!sleep.isActive)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        #expect(recordings.first?.duration == 600)
        #expect(journal.load() == nil)
        #expect(controller.interruptionNotice?.contains("잠자기") == true)

        lifecycle.send(.didWake)
        #expect(!controller.isRecording)
        #expect(controller.interruptionNotice != nil)
    }

    @Test func 일시정지_중_종료_직전에도_저장한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        try controller.pause()

        lifecycle.send(.willTerminate)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(controller.interruptionNotice?.contains("종료") == true)
    }

    @Test func 녹음기가_끝났다고_알리면_지금까지_녹음을_저장하고_크게_알린다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        let url = recorder.startedURLs[0]
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = Int64(RecordingFormat.workingBytesPerSecond) * 600
        recorder.currentTime = 0  // 멈춘 녹음기는 0을 돌려줄 수 있다
        recorder.hasEnded = true

        controller.checkRecorderHealth()

        #expect(!controller.isRecording)
        #expect(!sleep.isActive)
        #expect(journal.load() == nil)
        #expect(controller.recorderStallNotice?.contains("녹음이 멈춘 것 같습니다") == true)
        let saved = try #require(try container.mainContext.fetch(FetchDescriptor<Recording>()).first)
        // 길이 0으로 잡히지 않고 파일 크기로 어림한다.
        #expect(abs(saved.duration - 600) < 1)
        #expect(controller.lastSaved === saved)
    }

    @Test func 경과_시간이_연속_세_번_안_늘면_멈춘_것으로_보고_저장한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 120

        controller.checkRecorderHealth()  // 기준
        controller.checkRecorderHealth()  // 10초
        controller.checkRecorderHealth()  // 20초
        #expect(controller.isRecording)
        #expect(controller.recorderStallNotice == nil)

        controller.checkRecorderHealth()  // 30초
        #expect(!controller.isRecording)
        #expect(controller.recorderStallNotice != nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<Recording>()).first?.duration == 120)
        // 자동으로 새 녹음을 시작하지 않는다.
        #expect(recorder.startedURLs.count == 1)
    }

    @Test func 정상으로_녹음되면_경고하지_않는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        for step in 1...10 {
            recorder.currentTime = Double(step) * 10
            controller.checkRecorderHealth()
        }
        #expect(controller.isRecording)
        #expect(controller.recorderStallNotice == nil)
    }

    @Test func 일시정지_중에는_멈춤_경고를_하지_않는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 60
        try controller.pause()
        for _ in 1...10 { controller.checkRecorderHealth() }
        #expect(controller.isPaused)
        #expect(controller.recorderStallNotice == nil)
    }

    @Test func 멈춘_뒤_다시_늘면_저장하지_않고_계속_녹음한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 120
        controller.checkRecorderHealth()
        controller.checkRecorderHealth()
        controller.checkRecorderHealth()
        recorder.currentTime = 130
        controller.checkRecorderHealth()
        controller.checkRecorderHealth()
        controller.checkRecorderHealth()
        #expect(controller.isRecording)
        #expect(controller.recorderStallNotice == nil)
    }

    @Test func 새_녹음을_시작하면_멈춤_경고가_사라진다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.hasEnded = true
        controller.checkRecorderHealth()
        #expect(controller.recorderStallNotice != nil)

        recorder.hasEnded = false
        try await controller.start()
        #expect(controller.recorderStallNotice == nil)
        #expect(controller.isRecording)
    }

    @Test func 녹음_중이_아니면_잠자기_이벤트를_무시한다() throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        lifecycle.send(.willSleep)
        lifecycle.send(.willTerminate)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(controller.interruptionNotice == nil)
        #expect(controller.errorMessage == nil)
    }

    @Test func 정지하면_CAF로_저장하고_m4a로_압축한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0), compressing: true)
        try await controller.start()
        let caf = recorder.startedURLs[0]
        files.add(caf)
        recorder.currentTime = 90

        let saved = try controller.stop()
        // 압축이 끝나기 전에도 재생할 수 있는 CAF를 가리킨다.
        #expect(saved.relativePath == "미분류/03-02 월 10-00.caf")

        await controller.waitForCompression()
        #expect(saved.relativePath == "미분류/03-02 월 10-00.m4a")
        #expect(saved.duration == FakeAudioConverter.duration)
        #expect(files.fileExists(at: root.appending(path: "미분류/03-02 월 10-00.m4a")))
        #expect(!files.fileExists(at: caf))
    }

    @Test func 압축이_실패해도_CAF_녹음이_남는다() async throws {
        converter.error = CocoaError(.fileWriteOutOfSpace)
        let controller = makeController(at: date(2026, 3, 2, 10, 0), compressing: true)
        try await controller.start()
        let caf = recorder.startedURLs[0]
        files.add(caf)

        let saved = try controller.stop()
        await controller.waitForCompression()

        #expect(saved.relativePath == "미분류/03-02 월 10-00.caf")
        #expect(files.fileExists(at: caf))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    // MARK: 저장 공간 감시

    @Test func 남은_공간이_1시간_분량_미만이면_경고한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()

        files.capacity = 100_000_000 // 초당 32,000바이트 → 52분
        controller.checkStorage()

        #expect(controller.isRecording)
        #expect(controller.storageWarning?.contains("약 52분") == true)
    }

    @Test func 공간이_충분하면_경고하지_않고_확보되면_경고가_사라진다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        controller.checkStorage()
        #expect(controller.storageWarning == nil)

        files.capacity = 100_000_000
        controller.checkStorage()
        #expect(controller.storageWarning != nil)

        files.capacity = 10_000_000_000
        controller.checkStorage()
        #expect(controller.storageWarning == nil)
    }

    @Test func 공간이_바닥나기_전에_자동으로_정지하고_저장한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 7_200

        files.capacity = 10_000_000 // 10분 분량(약 19MB) 미만
        controller.checkStorage()

        #expect(!controller.isRecording)
        #expect(!recorder.isRecording)
        #expect(!sleep.isActive)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        #expect(recordings.first?.duration == 7_200)
        #expect(controller.interruptionNotice?.contains("저장 공간") == true)
        #expect(controller.storageWarning == nil)
    }

    @Test func 녹음_중이_아니거나_공간을_모르면_검사하지_않는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        files.capacity = 1
        controller.checkStorage()
        #expect(controller.storageWarning == nil)
        #expect(controller.interruptionNotice == nil)

        files.capacity = 10_000_000_000
        try await controller.start()
        files.capacity = nil
        controller.checkStorage()
        #expect(controller.isRecording)
        #expect(controller.storageWarning == nil)
    }

    // MARK: 장시간 녹음

    @Test func 세_시간_녹음의_경과_시간과_저장이_어긋나지_않는다() async throws {
        let clock = TestClock(date(2026, 3, 2, 10, 0))
        let simulated = SimulatedAudioRecorder(now: { clock.now })
        let controller = RecordingController(
            context: container.mainContext,
            recorder: simulated,
            storage: RecordingStorage(root: root, files: files),
            files: files,
            permission: permission,
            journal: journal,
            storageCheckInterval: nil,
            levelCheckInterval: nil,
            calendar: seoulCalendar,
            now: { clock.now }
        )

        try await controller.start()
        clock.advance(by: 3_600)
        try controller.pause()
        clock.advance(by: 20 * 60) // 쉬는 시간은 길이에 들어가지 않는다
        #expect(controller.elapsedText == "60:00")
        try controller.resume()
        clock.advance(by: 2 * 3_600)

        #expect(controller.elapsedText == "180:00")
        let saved = try controller.stop()
        #expect(saved.duration == 10_800)
        #expect(saved.startedAt == date(2026, 3, 2, 10, 0))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 시작하고_정지하면_Recording이_저장된다() async throws {
        let subject = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))

        try await controller.start()
        #expect(controller.isRecording)
        #expect(controller.currentSubjectName == "자료구조")
        #expect(recorder.startedURLs.map(\.path) == ["/tmp/LectureRecorderTests/Recordings/학기 미정/자료구조/03-02 월 10-00.caf"])

        recorder.currentTime = 4_500
        let saved = try controller.stop()

        #expect(!controller.isRecording)
        let recordings = try container.mainContext.fetch(FetchDescriptor<Recording>())
        #expect(recordings.count == 1)
        let recording = try #require(recordings.first)
        #expect(recording === saved)
        #expect(recording.subject === subject)
        #expect(recording.title == "자료구조 3월 2일 10:00")
        #expect(recording.duration == 4_500)
        #expect(recording.startedAt == date(2026, 3, 2, 10, 0))
        #expect(recording.relativePath == "학기 미정/자료구조/03-02 월 10-00.caf")
    }

    // MARK: 예상 과목 (3-8)

    @Test func 수업_중이면_지금_녹음하면_그_과목이다() throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 30))
        #expect(controller.expectedSubjectName == "자료구조")
        #expect(controller.expectedSubject()?.name == "자료구조")
    }

    @Test func 수업_시작_5분_전에도_그_과목이다() throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 9, 55))
        #expect(controller.expectedSubjectName == "자료구조")
    }

    @Test func 수업이_없으면_미분류다() throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 12, 30))
        #expect(controller.expectedSubjectName == "미분류")
        #expect(controller.expectedSubject() == nil)
    }

    @Test func 시간표를_바꾸면_예상_과목도_바뀐다() throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 30))
        #expect(controller.expectedSubjectName == "미분류")
        let subject = try addSubjectWithSlot()
        #expect(controller.expectedSubjectName == "자료구조")

        let schedule = ScheduleManager(context: container.mainContext)
        let slot = try #require(schedule.slots.first)
        try schedule.delete(slot)
        #expect(controller.expectedSubjectName == "미분류")
        _ = subject
    }

    @Test func 녹음을_시작하면_예상_과목과_실제_과목이_같다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 9, 55))
        let expected = controller.expectedSubjectName
        try await controller.start()
        #expect(controller.currentSubjectName == expected)
    }

    // MARK: 너무 짧은 녹음 (3-7)

    @Test func 기준_초는_5초다() {
        #expect(RecordingController.shortRecordingSeconds == 5)
    }

    @Test func 정지한_녹음이_5초_미만이면_저장할지_묻는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.toggle()
        recorder.currentTime = 4.9
        await controller.toggle()
        #expect(controller.shortRecordingPrompt != nil)
        #expect(controller.shortRecordingPrompt === controller.lastSaved)
    }

    @Test func 정확히_5초면_묻지_않는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.toggle()
        recorder.currentTime = 5
        await controller.toggle()
        #expect(controller.shortRecordingPrompt == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 저장을_고르면_녹음이_그대로_남는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.toggle()
        recorder.currentTime = 2
        await controller.toggle()
        controller.keepShortRecording()
        #expect(controller.shortRecordingPrompt == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(controller.lastSaved != nil)
    }

    @Test func 버리기를_고르면_파일과_기록이_모두_지워진다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.toggle()
        let caf = recorder.startedURLs[0]
        files.add(caf)
        recorder.currentTime = 2
        controller.addBookmark()
        await controller.toggle()

        controller.discardShortRecording()
        #expect(controller.shortRecordingPrompt == nil)
        await controller.waitForDiscard()

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Bookmark>()) == 0)
        #expect(!files.fileExists(at: caf))
        #expect(controller.lastSaved == nil)
        #expect(controller.errorMessage == nil)
    }

    @Test func 압축이_진행_중이어도_버리면_압축된_파일까지_지운다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0), compressing: true)
        await controller.toggle()
        let caf = recorder.startedURLs[0]
        files.add(caf)
        recorder.currentTime = 3
        await controller.toggle()

        controller.discardShortRecording()
        await controller.waitForDiscard()

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(files.allPaths.filter { $0.hasSuffix(".caf") || $0.hasSuffix(".m4a") }.isEmpty)
    }

    @Test func 새_녹음을_시작하면_이전_질문은_사라진다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        await controller.toggle()
        recorder.currentTime = 1
        await controller.toggle()
        try await controller.start()
        #expect(controller.shortRecordingPrompt == nil)
    }

    @Test func 종료나_잠자기로_멈춘_짧은_녹음은_묻지_않고_저장한다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 1
        try controller.stop()
        #expect(controller.shortRecordingPrompt == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 수업_없는_시간이면_미분류로_저장된다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 12, 30))
        try await controller.start()
        #expect(controller.currentSubjectName == "미분류")
        let recording = try controller.stop()
        #expect(recording.subject == nil)
        #expect(recording.relativePath == "미분류/03-02 월 12-30.caf")
    }

    @Test func 수업_시작_5분_전에_누른_녹음은_그_수업으로_저장된다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 9, 55))
        try await controller.start()
        #expect(controller.currentSubjectName == "자료구조")
        let recording = try controller.stop()
        #expect(recording.subject?.name == "자료구조")
        #expect(recording.relativePath == "학기 미정/자료구조/03-02 월 09-55.caf")
    }

    @Test func 권한이_없으면_시작하지_않는다() async throws {
        permission.status = .denied
        let controller = makeController(at: clock)
        await #expect(throws: RecordingError.permissionDenied) { try await controller.start() }
        #expect(!controller.isRecording)
        #expect(recorder.startedURLs.isEmpty)
    }

    @Test func 권한이_거부되어_있으면_처음부터_거부_상태다() {
        permission.status = .denied
        let controller = makeController(at: clock)
        #expect(controller.isPermissionDenied)
    }

    @Test func 권한을_거절하면_거부_상태가_된다() async throws {
        permission.status = .notDetermined
        permission.answer = .denied
        let controller = makeController(at: clock)
        #expect(!controller.isPermissionDenied)
        await controller.toggle()
        #expect(controller.isPermissionDenied)
        #expect(controller.errorMessage == RecordingError.permissionDenied.errorDescription)
    }

    @Test func 시스템_설정에서_허용하고_돌아오면_거부_상태가_풀린다() async {
        permission.status = .denied
        let controller = makeController(at: clock)
        await controller.toggle()
        #expect(controller.errorMessage != nil)
        permission.status = .granted
        controller.refreshPermission()
        #expect(!controller.isPermissionDenied)
        #expect(controller.errorMessage == nil)
    }

    @Test func 저장_공간이_부족하면_시작하지_않는다() async throws {
        files.capacity = 10 * 1024 * 1024
        let controller = makeController(at: clock)
        await #expect(throws: RecordingError.insufficientStorage) { try await controller.start() }
        #expect(recorder.startedURLs.isEmpty)
    }

    @Test func 녹음기가_실패하면_오류를_알린다() async throws {
        recorder.startError = CocoaError(.fileWriteNoPermission)
        let controller = makeController(at: clock)
        await controller.toggle()
        #expect(!controller.isRecording)
        #expect(controller.errorMessage?.hasPrefix("녹음을 시작하지 못했습니다") == true)
    }

    @Test func 녹음_중이_아니면_정지할_수_없다() {
        let controller = makeController(at: clock)
        #expect(throws: RecordingError.notRecording) { try controller.stop() }
    }

    @Test func 버튼으로_시작과_정지를_번갈아_한다() async throws {
        let controller = makeController(at: clock)
        await controller.toggle()
        #expect(controller.isRecording)
        await controller.toggle()
        #expect(!controller.isRecording)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 일시정지_후_재개해도_하나의_파일로_저장된다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        try controller.pause()
        #expect(controller.isPaused)
        #expect(controller.isRecording)
        #expect(recorder.isPaused)
        try controller.resume()
        #expect(!controller.isPaused)
        #expect(!recorder.isPaused)
        recorder.currentTime = 120
        let saved = try controller.stop()
        #expect(recorder.startedURLs.count == 1)
        #expect(saved.duration == 120)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Recording>()) == 1)
    }

    @Test func 일시정지_중에도_정지하면_저장된다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        recorder.currentTime = 30
        try controller.pause()
        let saved = try controller.stop()
        #expect(saved.duration == 30)
        #expect(!controller.isRecording)
        #expect(!controller.isPaused)
    }

    @Test func 녹음_중이_아니면_일시정지와_재개를_할_수_없다() {
        let controller = makeController(at: clock)
        #expect(throws: RecordingError.notRecording) { try controller.pause() }
        #expect(throws: RecordingError.notRecording) { try controller.resume() }
    }

    @Test func 일시정지하지_않았으면_재개할_수_없다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        #expect(throws: RecordingError.notPaused) { try controller.resume() }
    }

    @Test func 재개에_실패하면_일시정지_상태로_남고_오류를_알린다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        try controller.pause()
        recorder.resumeError = CocoaError(.fileWriteUnknown)
        controller.togglePause()
        #expect(controller.isPaused)
        #expect(controller.errorMessage?.hasPrefix("녹음을 다시 시작하지 못했습니다") == true)
    }

    @Test func 녹음_중에는_저널에_남고_정상_저장되면_지워진다() async throws {
        _ = try addSubjectWithSlot()
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        #expect(journal.load() == PendingRecording(relativePath: "학기 미정/자료구조/03-02 월 10-00.caf", subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0)))
        try controller.stop()
        #expect(journal.load() == nil)
    }

    @Test func 같은_분에_두_번_녹음하면_파일_이름이_겹치지_않는다() async throws {
        let controller = makeController(at: clock)
        try await controller.start()
        files.add(recorder.startedURLs[0])
        try controller.stop()
        try await controller.start()
        let second = try controller.stop()
        #expect(second.relativePath == "미분류/03-02 월 10-00_2.caf")
    }

    @Test func 녹음_중_북마크를_찍으면_정지할_때_녹음에_저장된다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 65
        controller.addBookmark()
        recorder.currentTime = 600
        controller.addBookmark()
        #expect(controller.bookmarkTimes == [65, 600])

        recorder.currentTime = 900
        let saved = try controller.stop()
        #expect(saved.sortedBookmarks.map(\.time) == [65, 600])
        #expect(controller.bookmarkTimes.isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<Bookmark>()).count == 2)
    }

    @Test func 일시정지_중에도_북마크를_찍을_수_있다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 30
        try controller.pause()
        controller.addBookmark()
        #expect(controller.bookmarkTimes == [30])
    }

    @Test func 녹음_중이_아니면_북마크를_찍지_않는다() throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        controller.addBookmark()
        #expect(controller.bookmarkTimes.isEmpty)
    }

    @Test func 새_녹음을_시작하면_이전_북마크가_남지_않는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 10
        controller.addBookmark()
        try controller.stop()
        try await controller.start()
        #expect(controller.bookmarkTimes.isEmpty)
    }

    @Test func 녹음을_시작하면_시작_알림이_불린다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        var calls = 0
        var wasRecording = false
        controller.onStarted = {
            calls += 1
            wasRecording = controller.isRecording
        }
        try await controller.start()
        #expect(calls == 1)
        #expect(wasRecording)
    }

    @Test func 시작에_실패하면_시작_알림이_불리지_않는다() async throws {
        recorder.startError = CocoaError(.fileWriteUnknown)
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        var calls = 0
        controller.onStarted = { calls += 1 }
        await #expect(throws: RecordingError.self) { try await controller.start() }
        #expect(calls == 0)
    }

    @Test func 북마크를_찍을_때마다_저널에_시점이_남는다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        #expect(journal.load()?.bookmarkTimes == [])
        recorder.currentTime = 65
        controller.addBookmark()
        recorder.currentTime = 600
        controller.addBookmark()
        #expect(journal.load()?.bookmarkTimes == [65, 600])
        #expect(journal.load()?.relativePath == "미분류/03-02 월 10-00.caf")
    }

    @Test func 정상_저장되면_저널이_지워진다() async throws {
        let controller = makeController(at: date(2026, 3, 2, 10, 0))
        try await controller.start()
        recorder.currentTime = 10
        controller.addBookmark()
        try controller.stop()
        #expect(journal.load() == nil)
    }
}

@Suite struct ElapsedFormatTests {
    @Test(arguments: [(0.0, "00:00"), (5.9, "00:05"), (65, "01:05"), (600, "10:00"), (5_403, "90:03"), (-3, "00:00")])
    func 경과_시간을_분과_초로_보여준다(seconds: Double, expected: String) {
        #expect(RecordingController.format(seconds) == expected)
    }
}
#endif
