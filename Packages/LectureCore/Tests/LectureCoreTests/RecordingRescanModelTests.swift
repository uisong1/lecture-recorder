#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
final class FinishCounter { var count = 0 }

@MainActor
@Suite struct RecordingRescanModelTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func addFile(_ path: String) {
        let url = storage.url(for: path)
        files.add(url)
        files.sizes[url.standardizedFileURL.path] = 4_000_000
    }

    func model(activePaths: @escaping @MainActor () -> Set<String> = { [] }, onFinished: @escaping @MainActor () -> Void = {}) -> RecordingRescanModel {
        let rescanner = RecordingRescanner(context: context, storage: storage, durations: FakeDurationReader(), calendar: seoulCalendar)
        return RecordingRescanModel(rescanner: rescanner, activePaths: activePaths, onFinished: onFinished)
    }

    @Test func 처음에는_메시지가_없고_실행_중이_아니다() {
        let model = model()
        #expect(model.message == nil)
        #expect(model.isError == false)
        #expect(model.isRunning == false)
    }

    @Test func 되살릴_파일이_없으면_안내_문구가_나온다() async {
        let model = model()
        await model.run()
        #expect(model.message == "목록에 없는 녹음 파일이 없습니다.")
        #expect(model.isError == false)
        #expect(model.isRunning == false)
    }

    @Test func 파일을_되살리면_요약이_나오고_목록을_다시_불러온다() async throws {
        addFile("2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        let counter = FinishCounter()
        let model = model(onFinished: { counter.count += 1 })

        await model.run()

        #expect(model.message?.contains("1개를 목록에 되살렸습니다.") == true)
        #expect(model.isError == false)
        #expect(counter.count == 1)
        #expect(try context.fetch(FetchDescriptor<Recording>()).count == 1)
    }

    @Test func 녹음_중인_파일은_건드리지_않는다() async throws {
        addFile("2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        let model = model(activePaths: { ["2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a"] })

        await model.run()

        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test func 다시_실행하면_이전_메시지를_새_결과로_바꾼다() async {
        addFile("2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        let model = model()
        await model.run()
        #expect(model.message?.contains("되살렸습니다") == true)

        await model.run()
        #expect(model.message == "목록에 없는 녹음 파일이 없습니다.")
    }

    @Test func 데이터베이스_오류_문구는_이유를_포함한다() {
        let error = RescanError.databaseFailed("디스크 가득 참")
        #expect(error.errorDescription == "녹음 목록을 읽거나 저장하지 못했습니다: 디스크 가득 참")
    }
}
#endif
