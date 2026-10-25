import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingStorageTests {
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    @Test func 과목_폴더와_날짜_시각으로_경로를_만든다() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        let path = storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar)
        #expect(path == "자료구조/2026-03-02_1000.m4a")
        #expect(storage.url(for: path).path == "/tmp/LectureRecorderTests/Recordings/자료구조/2026-03-02_1000.m4a")
    }

    @Test func 과목이_없으면_미분류_폴더() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        #expect(storage.newRelativePath(subjectName: nil, startedAt: date(2026, 3, 2, 9, 5), calendar: seoulCalendar) == "미분류/2026-03-02_0905.m4a")
    }

    @Test func 같은_이름이_있으면_2를_붙인다() {
        let files = FakeFileStore(files: [root.appending(path: "자료구조/2026-03-02_1000.m4a")])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "자료구조/2026-03-02_1000_2.m4a")
    }

    @Test func _2도_있으면_3을_붙인다() {
        let files = FakeFileStore(files: [
            root.appending(path: "자료구조/2026-03-02_1000.m4a"),
            root.appending(path: "자료구조/2026-03-02_1000_2.m4a"),
        ])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "자료구조/2026-03-02_1000_3.m4a")
    }

    @Test func 다른_과목_폴더의_같은_이름은_상관없다() {
        let files = FakeFileStore(files: [root.appending(path: "운영체제/2026-03-02_1000.m4a")])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "자료구조/2026-03-02_1000.m4a")
    }

    @Test(arguments: [
        ("C/C++", "C-C++"),
        ("  선형대수  ", "선형대수"),
        ("..", "미분류"),
        (".hidden", "hidden"),
        ("", "미분류"),
        ("시간:공간", "시간-공간"),
    ])
    func 폴더_이름으로_쓸_수_없는_문자를_바꾼다(name: String, expected: String) {
        #expect(RecordingStorage.folderName(for: name) == expected)
    }

    @Test func 한자리_월일시분은_0을_채운다() {
        #expect(RecordingStorage.baseFileName(for: date(2026, 1, 5, 8, 7), calendar: seoulCalendar) == "2026-01-05_0807")
    }

    @Test func 과목_폴더를_만든다() throws {
        let files = FakeFileStore()
        let storage = RecordingStorage(root: root, files: files)
        try storage.prepareFolder(for: "자료구조/2026-03-02_1000.m4a")
        #expect(files.fileExists(at: root.appending(path: "자료구조")))
    }
}
