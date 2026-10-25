#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import LectureCore

@MainActor
@Suite struct RecordingLibraryPerformanceTests {
    let container: ModelContainer
    let files = FakeFileStore()
    let storage: RecordingStorage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try LectureModelContainer.make(inMemory: true)
        storage = RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    @discardableResult
    func addRecording(_ title: String, subject: Subject?, at startedAt: Date = date(2026, 3, 2, 10, 0)) -> Recording {
        let recording = Recording(title: title, subject: subject, startedAt: startedAt, duration: 60, relativePath: "\(title).m4a")
        context.insert(recording)
        files.add(storage.url(for: recording.relativePath))
        return recording
    }

    /// 시간 제한은 CI에서 흔들리지 않도록 느슨하게 잡는다 (실제로는 훨씬 빠르다).
    func seconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test func 과목_40개_녹음_2000개_북마크_5000개에서도_reload와_select와_필터가_빠르다() throws {
        let subjects = try (0..<40).map { try SubjectManager(context: context).add(name: "과목\($0)", color: .blue) }
        for index in 0..<2000 {
            let recording = addRecording("녹음\(index)", subject: index % 41 == 40 ? nil : subjects[index % 40], at: date(2026, 3, 2, 10, 0).addingTimeInterval(Double(index) * 60))
            for mark in 0..<(index < 1000 ? 3 : 2) {
                context.insert(Bookmark(time: Double(mark * 10), note: "메모\(mark)", createdAt: date(2026, 3, 2, 10, 0), recording: recording))
            }
        }
        try context.save()

        let library = RecordingLibrary(context: context, now: { date(2026, 3, 30, 15, 0) }, calendar: seoulCalendar)
        #expect(seconds { library.reload() } < 3)
        #expect(seconds { library.select(.all) } < 3)
        #expect(seconds { for subject in subjects { library.select(.subject(subject.persistentModelID)) } } < 3)
        library.select(.all)
        #expect(seconds { library.filter.query = "녹음19" } < 3)
        #expect(seconds { for subject in subjects { _ = library.count(for: .subject(subject.persistentModelID)) } } < 0.5)
        #expect(library.count(for: .all) == 2000)
    }

    @Test func 개수는_reload_뒤에_맞게_갱신된다() throws {
        let ds = try SubjectManager(context: context).add(name: "자료구조", color: .green)
        addRecording("a", subject: ds)
        addRecording("b", subject: nil)
        try context.save()
        let library = RecordingLibrary(context: context)
        #expect(library.count(for: .all) == 2)
        #expect(library.count(for: .subject(ds.persistentModelID)) == 1)
        #expect(library.count(for: .unclassified) == 1)

        addRecording("c", subject: ds)
        try context.save()
        library.reload()

        #expect(library.count(for: .all) == 3)
        #expect(library.count(for: .subject(ds.persistentModelID)) == 2)
        #expect(library.count(for: .unclassified) == 1)
    }

    @Test func 행_상태의_파일_확인은_처음_한_번만_하고_reload까지_재사용한다() throws {
        let recording = addRecording("a", subject: nil)
        try context.save()
        let manager = RecordingManager(context: context, storage: storage)
        let library = RecordingLibrary(context: context)

        let before = files.fileExistsCalls
        for _ in 0..<5 { #expect(library.rowStatus(for: recording, using: manager).labels.isEmpty) }
        #expect(files.fileExistsCalls == before + 1)

        // reload 전에는 파일이 사라져도 다시 확인하지 않는다. reload하면 새로 확인한다.
        try files.removeItem(at: storage.url(for: "a.m4a"))
        #expect(library.rowStatus(for: recording, using: manager).labels.isEmpty)
        library.reload()
        #expect(library.rowStatus(for: recording, using: manager).labels == ["파일 없음"])
    }

    @Test func 경로가_바뀐_녹음의_행_상태는_다시_확인한다() throws {
        let recording = addRecording("a", subject: nil)
        files.add(storage.url(for: "b.caf"))
        try context.save()
        let manager = RecordingManager(context: context, storage: storage)
        let library = RecordingLibrary(context: context)
        #expect(library.rowStatus(for: recording, using: manager).labels.isEmpty)

        recording.relativePath = "b.caf"

        #expect(library.rowStatus(for: recording, using: manager).labels == ["압축 중"])
    }
}
#endif
