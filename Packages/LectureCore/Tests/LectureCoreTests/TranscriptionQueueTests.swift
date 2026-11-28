#if canImport(SwiftData)
import Foundation
import Testing
@testable import LectureCore

/// 작업마다 테스트가 `finish`를 부를 때까지 기다리는 가짜 전사 엔진.
final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [String: CheckedContinuation<Transcript, Error>] = [:]
    private var progressHandlers: [String: @Sendable (Double) -> Void] = [:]
    private var _started: [String] = []

    var started: [String] { lock.withLock { _started } }
    var running: Set<String> { lock.withLock { Set(waiters.keys) } }

    func transcribe(_ job: TranscriptionJob, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    _started.append(job.id)
                    waiters[job.id] = continuation
                    progressHandlers[job.id] = progress
                }
            }
        } onCancel: {
            resume(job.id, with: .failure(CancellationError()))
        }
    }

    func report(_ id: String, _ value: Double) {
        let handler = lock.withLock { progressHandlers[id] }
        handler?(value)
    }

    func finish(_ id: String, text: String = "끝") {
        resume(id, with: .success(Transcript(segments: [TranscriptSegment(start: 0, end: 1, text: text)], model: "fake")))
    }

    func fail(_ id: String) {
        resume(id, with: .failure(TranscriptionError("모델 오류")))
    }

    private func resume(_ id: String, with result: Result<Transcript, Error>) {
        let waiter = lock.withLock { () -> CheckedContinuation<Transcript, Error>? in
            progressHandlers[id] = nil
            return waiters.removeValue(forKey: id)
        }
        waiter?.resume(with: result)
    }
}

private func job(_ id: String, duration: TimeInterval = 100) -> TranscriptionJob {
    TranscriptionJob(id: id, title: id, subtitle: "", audioURL: URL(filePath: "/tmp/\(id).m4a"), duration: duration)
}

/// 조건이 맞을 때까지 메인 액터를 잠깐씩 양보한다.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    Issue.record("조건을 기다리다 시간이 지났어요")
}

@MainActor
@Suite struct TranscriptionQueueTests {
    let engine = FakeTranscriber()

    @Test func runsAtMostMaxConcurrentAtOnce() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 2)
        queue.enqueue([job("a"), job("b"), job("c")])
        await waitUntil { engine.running.count == 2 }
        #expect(queue.runningCount == 2)
        #expect(queue.waitingCount == 1)
        #expect(Set(engine.started) == ["a", "b"])

        engine.finish("a")
        await waitUntil { engine.running == ["b", "c"] }
        #expect(queue.state(for: "a") == .done)
        #expect(queue.runningCount == 2)
    }

    @Test func clampsConcurrency() {
        #expect(TranscriptionQueue(engine: engine, maxConcurrent: 0).maxConcurrent == 1)
        #expect(TranscriptionQueue(engine: engine, maxConcurrent: 9).maxConcurrent == 4)
        let queue = TranscriptionQueue(engine: engine)
        #expect(queue.maxConcurrent == 2)
        queue.maxConcurrent = 10
        #expect(queue.maxConcurrent == 4)
    }

    @Test func raisingConcurrencyStartsMore() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 1)
        queue.enqueue([job("a"), job("b")])
        await waitUntil { engine.running.count == 1 }
        queue.maxConcurrent = 2
        await waitUntil { engine.running.count == 2 }
    }

    @Test func duplicatesAreIgnored() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 1)
        queue.enqueue([job("a"), job("b")])
        queue.enqueue([job("a"), job("b")])
        #expect(queue.entries.count == 2)
    }

    @Test func progressAndOverallProgress() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 2)
        queue.enqueue([job("a", duration: 100), job("b", duration: 300)])
        await waitUntil { engine.running.count == 2 }
        engine.report("a", 0.5)
        engine.report("b", 0.5)
        await waitUntil { queue.state(for: "b") == .running(progress: 0.5) }
        #expect(abs(queue.overallProgress - 0.5) < 0.0001)
        // 남은 오디오 200초 × 0.2 ÷ 2
        #expect(abs(queue.estimatedRemainingSeconds - 20) < 0.0001)
    }

    @Test func overallProgressWeightsByDurationAndSkipsFailures() {
        let entries = [
            TranscriptionQueue.Entry(job: job("a", duration: 100), state: .done),
            TranscriptionQueue.Entry(job: job("b", duration: 300), state: .waiting),
            TranscriptionQueue.Entry(job: job("c", duration: 1000), state: .failed("x")),
        ]
        #expect(TranscriptionQueue.overallProgress(entries) == 0.25)
        #expect(TranscriptionQueue.overallProgress([]) == 0)
        #expect(TranscriptionQueue.estimatedRemainingSeconds(entries, concurrency: 1) == 60)
    }

    @Test func savesResultWhenFinished() async {
        let queue = TranscriptionQueue(engine: engine)
        var saved: [String: String] = [:]
        queue.onFinished = { job, transcript in saved[job.id] = transcript.segments.first?.text }
        queue.enqueue([job("a")])
        await waitUntil { engine.running == ["a"] }
        engine.finish("a", text: "안녕하세요")
        await waitUntil { queue.state(for: "a") == .done }
        #expect(saved == ["a": "안녕하세요"])
        #expect(!queue.isActive)
    }

    @Test func saveFailureMarksRowFailed() async {
        struct SaveError: Error {}
        let queue = TranscriptionQueue(engine: engine)
        queue.onFinished = { _, _ in throw SaveError() }
        queue.enqueue([job("a")])
        await waitUntil { engine.running == ["a"] }
        engine.finish("a")
        await waitUntil { queue.state(for: "a") != .running(progress: 0) }
        guard case .failed(let message) = queue.state(for: "a") else {
            Issue.record("실패로 표시되어야 해요")
            return
        }
        #expect(message.contains("저장하지 못했어요"))
    }

    @Test func engineFailureShowsMessageAndRetryWorks() async {
        let queue = TranscriptionQueue(engine: engine)
        queue.enqueue([job("a")])
        await waitUntil { engine.running == ["a"] }
        engine.fail("a")
        await waitUntil { queue.state(for: "a") == .failed("모델 오류") }

        queue.retry(id: "a")
        await waitUntil { engine.running == ["a"] }
        #expect(engine.started == ["a", "a"])
    }

    @Test func pauseReturnsRunningToWaitingAndResumeRestarts() async {
        let queue = TranscriptionQueue(engine: engine)
        queue.enqueue([job("a"), job("b")])
        await waitUntil { engine.running.count == 2 }
        queue.pauseAll()
        await waitUntil { queue.waitingCount == 2 }
        #expect(engine.running.isEmpty)
        #expect(queue.isPaused)

        queue.enqueue([job("c")])
        #expect(queue.runningCount == 0)

        queue.resumeAll()
        await waitUntil { engine.running == ["a", "b"] }
    }

    @Test func suspendForRecordingStopsAndResumes() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 1)
        queue.enqueue([job("a")])
        await waitUntil { engine.running == ["a"] }
        queue.setSuspended("녹음 중이라 잠시 멈췄어요")
        await waitUntil { queue.state(for: "a") == .waiting }
        #expect(queue.suspendReason == "녹음 중이라 잠시 멈췄어요")

        queue.setSuspended(nil)
        await waitUntil { engine.running == ["a"] }
        #expect(queue.suspendReason == nil)
    }

    @Test func enqueueWhileSuspendedDoesNotStart() async {
        let queue = TranscriptionQueue(engine: engine)
        queue.setSuspended("전원에 연결되면 시작해요")
        queue.enqueue([job("a")])
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(engine.started.isEmpty)
        #expect(queue.waitingCount == 1)
    }

    @Test func removeRunningCancelsAndRemoves() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 1)
        queue.enqueue([job("a"), job("b")])
        await waitUntil { engine.running == ["a"] }
        queue.remove(id: "a")
        await waitUntil { engine.running == ["b"] }
        #expect(queue.entries.map(\.id) == ["b"])
    }

    @Test func removeWaitingJustDrops() {
        let queue = TranscriptionQueue(engine: engine)
        queue.pauseAll()
        queue.enqueue([job("a")])
        queue.remove(id: "a")
        #expect(queue.entries.isEmpty)
    }

    @Test func newBatchClearsOldDoneRows() async {
        let queue = TranscriptionQueue(engine: engine)
        queue.enqueue([job("a")])
        await waitUntil { engine.running == ["a"] }
        engine.finish("a")
        await waitUntil { queue.state(for: "a") == .done }
        queue.enqueue([job("b")])
        #expect(queue.entries.map(\.id) == ["b"])
    }

    @Test func requeueingDoneRowRunsAgain() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 2)
        queue.enqueue([job("a"), job("b")])
        await waitUntil { engine.running.count == 2 }
        engine.finish("a")
        await waitUntil { queue.state(for: "a") == .done }
        // b가 아직 진행 중이라 a는 남아 있고, 다시 넣으면 대기로 돌아간다.
        queue.enqueue([job("a")])
        await waitUntil { engine.started.count == 3 }
        #expect(engine.started.last == "a")
    }

    @Test func clearFinishedKeepsActiveRows() async {
        let queue = TranscriptionQueue(engine: engine, maxConcurrent: 2)
        queue.enqueue([job("a"), job("b")])
        await waitUntil { engine.running.count == 2 }
        engine.fail("a")
        await waitUntil { queue.state(for: "a") == .failed("모델 오류") }
        queue.clearFinished()
        #expect(queue.entries.map(\.id) == ["b"])
    }
}
#endif
