#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

final class FakeTranscriptionTool: TranscriptionToolManaging, @unchecked Sendable {
    var ready = true
    var missing = false
    var installError: TranscriptionToolError?
    private(set) var installCount = 0

    var statusError: TranscriptionToolError?

    func isReady() async throws -> Bool {
        if missing { throw TranscriptionToolError.helperMissing }
        if let statusError { throw statusError }
        return ready
    }

    func install() async throws {
        installCount += 1
        if let installError { throw installError }
        ready = true
    }
}

@MainActor
final class MemoryTranscriptionPreferences: TranscriptionPreferences {
    var concurrency = 2
    var powerOnly = false
}

@MainActor
@Suite struct TranscriptionCenterTests {
    let container: ModelContainer
    let storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: FakeFileStore())
    let engine = FakeTranscriber()
    let tool = FakeTranscriptionTool()
    let preferences = MemoryTranscriptionPreferences()
    let power = FakePowerStatus(PowerStatus(batteryPercent: 80, isPluggedIn: true))
    let subject = Subject(name: "자료구조", color: .blue)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        container.mainContext.insert(subject)
    }

    @discardableResult
    private func add(_ path: String, day: Int, duration: TimeInterval = 5294) -> Recording {
        let recording = Recording(title: path, subject: subject, startedAt: date(2026, 11, day, 10, 30), duration: duration, relativePath: path)
        context.insert(recording)
        // 앱에서 전사할 녹음은 늘 저장된 뒤라 고정 id가 정해져 있다.
        do { try context.save() } catch { Issue.record("저장 실패: \(error)") }
        return recording
    }

    private func key(_ path: String) -> String {
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.relativePath == path })
        return (try? context.fetch(descriptor).first?.transcriptionKey) ?? path
    }

    private func makeCenter(active: Set<String> = []) -> TranscriptionCenter {
        TranscriptionCenter(
            context: context, storage: storage, engine: engine, tool: tool, preferences: preferences,
            power: power, activePaths: { active }, now: { date(2026, 11, 28, 9, 0) }, calendar: seoulCalendar
        )
    }

    @Test func listsUntranscribedNewestFirstAndSkipsActiveAndCaf() throws {
        add("a.m4a", day: 20)
        add("b.m4a", day: 26)
        add("c.caf", day: 27)
        add("live.m4a", day: 28)
        let done = add("d.m4a", day: 10)
        done.transcriptData = try Transcript(segments: [], model: "m").encoded()
        let center = makeCenter(active: ["live.m4a"])
        #expect(center.candidates.map(\.relativePath) == ["b.m4a", "a.m4a"])
        #expect(center.transcribed.map(\.relativePath) == ["d.m4a"])
        #expect(center.candidatesDuration == 5294 * 2)
    }

    @Test func subtitleShowsSubjectDateAndLength() {
        let recording = add("a.m4a", day: 26)
        let center = makeCenter()
        #expect(center.subtitle(for: recording).hasPrefix("자료구조 · 11월 26일 · 1:28:14"))
    }

    @Test func transcribeAllSavesResults() async throws {
        add("a.m4a", day: 20)
        add("b.m4a", day: 26)
        let center = makeCenter()
        await center.checkTool()
        center.transcribeAll()
        await waitUntil { engine.running.count == 2 }
        #expect(center.queue.entries.first?.job.audioURL.path.hasSuffix("/Recordings/b.m4a") == true)
        engine.finish("a.m4a", text: "해시 테이블")
        await waitUntil { center.transcribed.count == 1 }
        let saved = try #require(center.transcribed.first)
        #expect(saved.transcript?.segments.first?.text == "해시 테이블")
        #expect(saved.transcribedAt == date(2026, 11, 28, 9, 0))
        #expect(center.candidates.map(\.relativePath) == ["b.m4a"])
    }

    @Test func transcribeSelectedOnlyQueuesChosen() async {
        add("a.m4a", day: 20)
        add("b.m4a", day: 26)
        add("c.m4a", day: 27)
        let center = makeCenter()
        await center.checkTool()
        center.isSelecting = true
        center.toggleSelection(center.candidates[0])
        center.toggleSelection(center.candidates[2])
        #expect(center.selectedDuration == 5294 * 2)
        center.transcribeSelected()
        #expect(Set(center.queue.entries.map(\.job.title)) == ["c.m4a", "a.m4a"])
        #expect(!center.isSelecting)
        #expect(center.selection.isEmpty)
    }

    @Test func selectAllSkipsQueued() async {
        add("a.m4a", day: 20)
        add("b.m4a", day: 26)
        let center = makeCenter()
        await center.checkTool()
        center.transcribe(center.candidates[0])
        center.selectAll()
        #expect(center.selection == [key("a.m4a")])
        #expect(center.idleCandidates.map(\.relativePath) == ["a.m4a"])
    }

    @Test func refusesWhenToolNotInstalled() async {
        add("a.m4a", day: 20)
        tool.ready = false
        let center = makeCenter()
        await center.checkTool()
        #expect(center.toolStatus == .notInstalled)
        center.transcribeAll()
        #expect(center.queue.entries.isEmpty)
        #expect(center.errorMessage?.contains("설치") == true)

        await center.installTool()
        #expect(center.toolStatus == .ready)
        #expect(tool.installCount == 1)
    }

    @Test func reportsMissingHelperAndInstallFailure() async {
        tool.missing = true
        let center = makeCenter()
        await center.checkTool()
        #expect(center.toolStatus == .helperMissing)

        tool.missing = false
        tool.ready = false
        tool.installError = .failed("Python 3.10 이상이 필요해요")
        await center.installTool()
        #expect(center.toolStatus == .failed("Python 3.10 이상이 필요해요"))
    }

    @Test func recordingPausesAndResumes() async {
        add("a.m4a", day: 20)
        let center = makeCenter()
        await center.checkTool()
        center.transcribeAll()
        await waitUntil { engine.running == ["a.m4a"] }
        center.recordingDidStart()
        #expect(center.queue.suspendReason == TranscriptionCenter.recordingPauseReason)
        await waitUntil { center.queue.state(for: key("a.m4a")) == .waiting }
        center.recordingDidStop()
        await waitUntil { engine.running == ["a.m4a"] }
    }

    @Test func powerOnlyWaitsForCharger() async {
        add("a.m4a", day: 20)
        power.status = PowerStatus(batteryPercent: 50, isPluggedIn: false)
        let center = makeCenter()
        await center.checkTool()
        center.transcribeAll()
        await waitUntil { engine.running == ["a.m4a"] }

        center.powerOnly = true
        #expect(preferences.powerOnly)
        #expect(center.queue.suspendReason == TranscriptionCenter.powerPauseReason)

        power.status = PowerStatus(batteryPercent: 50, isPluggedIn: true)
        center.refreshConditions()
        #expect(center.queue.suspendReason == nil)
    }

    @Test func desktopMacWithoutBatteryIsNeverPowerPaused() {
        power.status = nil
        preferences.powerOnly = true
        let center = makeCenter()
        #expect(center.queue.suspendReason == nil)
    }

    @Test func concurrencyIsSavedClamped() {
        preferences.concurrency = 3
        let center = makeCenter()
        #expect(center.concurrency == 3)
        center.concurrency = 7
        #expect(center.concurrency == 4)
        #expect(preferences.concurrency == 4)
    }

    @Test func removeTranscriptReturnsToCandidates() throws {
        let recording = add("a.m4a", day: 20)
        recording.transcriptData = try Transcript(segments: [], model: "m").encoded()
        let center = makeCenter()
        #expect(center.candidates.isEmpty)
        center.removeTranscript(of: recording)
        #expect(center.candidates.map(\.relativePath) == ["a.m4a"])
        #expect(recording.transcribedAt == nil)
    }

    @Test func movingRecordingWhileWaitingTranscribesTheNewPathAndSavesResult() async throws {
        let recording = add("자료구조/a.m4a", day: 20)
        let center = makeCenter()
        await center.checkTool()
        center.queue.pauseAll()
        center.transcribe(recording)
        // 기다리는 사이 과목을 옮겨 경로가 바뀌었다.
        recording.relativePath = "알고리즘/a.m4a"
        try context.save()
        center.queue.resumeAll()
        await waitUntil { engine.running == ["자료구조/a.m4a"] }
        #expect(engine.audioURL(of: "자료구조/a.m4a")?.path.hasSuffix("/Recordings/알고리즘/a.m4a") == true)

        // 전사 중에 또 옮겨도 결과는 같은 녹음에 저장된다.
        recording.relativePath = "운영체제/a.m4a"
        try context.save()
        engine.finish("자료구조/a.m4a", text: "옮긴 녹음")
        await waitUntil { center.transcribed.count == 1 }
        #expect(recording.transcript?.segments.first?.text == "옮긴 녹음")
    }

    @Test func deletedRecordingFailsItsRowInsteadOfTranscribing() async throws {
        let recording = add("a.m4a", day: 20)
        let center = makeCenter()
        await center.checkTool()
        center.queue.pauseAll()
        center.transcribe(recording)
        let id = key("a.m4a")
        context.delete(recording)
        try context.save()
        center.queue.resumeAll()
        guard case .failed = center.queue.state(for: id) else {
            Issue.record("지운 녹음 줄은 실패여야 해요")
            return
        }
        #expect(engine.started.isEmpty)
    }

    @Test func retranscribeKeepsOldResultUntilNewOneIsSaved() async throws {
        let recording = add("a.m4a", day: 20)
        recording.transcriptData = try Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: "예전")], model: "m").encoded()
        try context.save()
        let center = makeCenter()
        await center.checkTool()
        center.retranscribe(recording)
        await waitUntil { engine.running == ["a.m4a"] }
        #expect(recording.transcript?.segments.first?.text == "예전")

        center.queue.pause(id: key("a.m4a"))
        await waitUntil { center.queue.state(for: key("a.m4a")) == .paused(progress: 0) }
        #expect(recording.transcript?.segments.first?.text == "예전")

        center.queue.resume(id: key("a.m4a"))
        await waitUntil { engine.running == ["a.m4a"] }
        engine.finish("a.m4a", text: "새로")
        await waitUntil { center.queue.state(for: key("a.m4a")) == .done }
        #expect(recording.transcript?.segments.first?.text == "새로")
    }

    @Test func helperThatCannotRunIsNotReportedAsNotInstalled() async {
        tool.statusError = .failed("전사 도우미를 실행하지 못했어요 (코드 -1)")
        let center = makeCenter()
        await center.checkTool()
        #expect(center.toolStatus == .failed("전사 도우미를 실행하지 못했어요 (코드 -1)"))
    }
}
#endif
