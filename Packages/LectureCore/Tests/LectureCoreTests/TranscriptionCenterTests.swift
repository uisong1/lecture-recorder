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

    func isReady() async throws -> Bool {
        if missing { throw TranscriptionToolError.helperMissing }
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
        return recording
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
        #expect(Set(center.queue.entries.map(\.id)) == ["c.m4a", "a.m4a"])
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
        #expect(center.selection == ["a.m4a"])
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
        await waitUntil { center.queue.state(for: "a.m4a") == .waiting }
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
}
#endif
