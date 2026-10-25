import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingStorageTests {
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    @Test func 학기_과목_폴더와_날짜_요일_시각으로_경로를_만든다() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        let path = storage.newRelativePath(subjectName: "컴퓨터구조", semester: "2026년 2학기", startedAt: date(2026, 10, 28, 13, 30), calendar: seoulCalendar)
        #expect(path == "2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
        #expect(storage.url(for: path).path == "/tmp/LectureRecorderTests/Recordings/2026년 2학기/컴퓨터구조/10-28 수 13-30.m4a")
    }

    @Test func 학기를_모르는_과목은_학기_미정_폴더() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        #expect(storage.newRelativePath(subjectName: "자료구조", semester: "  ", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "학기 미정/자료구조/03-02 월 10-00.m4a")
        #expect(storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "학기 미정/자료구조/03-02 월 10-00.m4a")
    }

    @Test func 과목이_없으면_미분류_폴더() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        #expect(storage.newRelativePath(subjectName: nil, semester: "2026년 2학기", startedAt: date(2026, 3, 2, 9, 5), calendar: seoulCalendar) == "미분류/03-02 월 09-05.m4a")
        #expect(storage.newRelativePath(subjectName: "  ", startedAt: date(2026, 3, 2, 9, 5), calendar: seoulCalendar) == "미분류/03-02 월 09-05.m4a")
    }

    @Test func 같은_이름이_있으면_2를_붙인다() {
        let files = FakeFileStore(files: [root.appending(path: "2026년 2학기/자료구조/03-02 월 10-00.m4a")])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", semester: "2026년 2학기", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "2026년 2학기/자료구조/03-02 월 10-00_2.m4a")
    }

    @Test func _2도_있으면_3을_붙인다() {
        let files = FakeFileStore(files: [
            root.appending(path: "2026년 2학기/자료구조/03-02 월 10-00.m4a"),
            root.appending(path: "2026년 2학기/자료구조/03-02 월 10-00_2.m4a"),
        ])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", semester: "2026년 2학기", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "2026년 2학기/자료구조/03-02 월 10-00_3.m4a")
    }

    @Test func 다른_과목_폴더의_같은_이름은_상관없다() {
        let files = FakeFileStore(files: [root.appending(path: "2026년 2학기/운영체제/03-02 월 10-00.m4a")])
        let storage = RecordingStorage(root: root, files: files)
        #expect(storage.newRelativePath(subjectName: "자료구조", semester: "2026년 2학기", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar) == "2026년 2학기/자료구조/03-02 월 10-00.m4a")
    }

    @Test func 학기_폴더_이름에도_쓸_수_없는_문자를_바꾼다() {
        #expect(RecordingStorage.folderPath(semester: "2026/2학기", subjectName: "C/C++") == "2026-2학기/C-C++")
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
        #expect(RecordingStorage.baseFileName(for: date(2026, 1, 5, 8, 7), calendar: seoulCalendar) == "01-05 월 08-07")
    }

    @Test func 과목_폴더를_만든다() throws {
        let files = FakeFileStore()
        let storage = RecordingStorage(root: root, files: files)
        try storage.prepareFolder(for: "2026년 2학기/자료구조/03-02 월 10-00.m4a")
        #expect(files.fileExists(at: root.appending(path: "2026년 2학기/자료구조")))
    }

    @Test func 녹음_중_파일은_CAF_확장자를_쓴다() {
        let storage = RecordingStorage(root: root, files: FakeFileStore())
        let path = storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar, fileExtension: RecordingStorage.workingExtension)
        #expect(path == "학기 미정/자료구조/03-02 월 10-00.caf")
    }

    @Test func 압축_전_CAF나_압축된_m4a가_있으면_이름이_겹치지_않는다() {
        let files = FakeFileStore(files: [
            root.appending(path: "학기 미정/자료구조/03-02 월 10-00.caf"),
            root.appending(path: "학기 미정/자료구조/03-02 월 10-00_2.m4a"),
        ])
        let storage = RecordingStorage(root: root, files: files)
        let path = storage.newRelativePath(subjectName: "자료구조", startedAt: date(2026, 3, 2, 10, 0), calendar: seoulCalendar, fileExtension: RecordingStorage.workingExtension)
        #expect(path == "학기 미정/자료구조/03-02 월 10-00_3.caf")
    }

    @Test(arguments: [
        ("자료구조/2026-03-02_1000.m4a", true),
        ("자료구조/2026-03-02_1000_2.m4a", true),
        ("미분류/2026-12-31_2359.caf", true),
        ("2026년 2학기/자료구조/03-02 월 10-00.m4a", false),
        ("미분류/03-02 월 10-00.m4a", false),
        ("자료구조/강의 녹음.m4a", false),
        ("자료구조/2026-03-02_1000_x.m4a", false),
        ("자료구조/2026-3-2_1000.m4a", false),
        ("2026-03-02_1000.m4a", false),
    ])
    func 예전_규칙의_경로를_알아본다(path: String, expected: Bool) {
        #expect(RecordingStorage.isLegacyPath(path) == expected)
    }

    @Test func 압축_경로를_만든다() {
        #expect(RecordingStorage.compressedPath(for: "자료구조/a.caf") == "자료구조/a.m4a")
        #expect(RecordingStorage.temporaryCompressedPath(for: "자료구조/a.caf") == "자료구조/a.converting.m4a")
        #expect(RecordingStorage.isWorkingPath("자료구조/a.caf"))
        #expect(!RecordingStorage.isWorkingPath("자료구조/a.m4a"))
    }

    // MARK: 폴더 훑기와 빈 폴더 정리

    func store(_ paths: [String], directories: [String] = []) throws -> (RecordingStorage, FakeFileStore) {
        let files = FakeFileStore()
        let storage = RecordingStorage(root: root, files: files)
        for path in paths { files.add(storage.url(for: path)) }
        for directory in directories { try files.createDirectory(at: storage.url(for: directory)) }
        return (storage, files)
    }

    @Test func 오디오_파일만_모으고_임시_파일과_숨김_파일은_뺀다() throws {
        let (storage, _) = try store([
            "학기/과목/a.m4a", "학기/과목/b.caf", "학기/과목/b.converting.m4a",
            "학기/과목/메모.txt", "학기/과목/.hidden.m4a", "미분류/c.M4A",
        ])
        #expect(storage.audioFilePaths() == ["미분류/c.M4A", "학기/과목/a.m4a", "학기/과목/b.caf"])
    }

    @Test func 빈_폴더만_지우고_파일이_있는_폴더와_루트는_남긴다() throws {
        let (storage, files) = try store(["학기/과목/a.m4a"], directories: ["예전과목", "학기/빈과목", "깊은", "깊은/빈"])
        let removed = storage.removeEmptyFolders()
        #expect(removed == 4)
        #expect(!files.isDirectory(at: storage.url(for: "예전과목")))
        #expect(!files.isDirectory(at: storage.url(for: "깊은")))
        #expect(files.fileExists(at: storage.url(for: "학기/과목/a.m4a")))
    }

    @Test func 녹음_중인_파일이_들어갈_폴더는_비어_있어도_지우지_않는다() throws {
        let (storage, files) = try store([], directories: ["학기", "학기/과목", "학기/다른과목"])
        let removed = storage.removeEmptyFolders(protecting: ["학기/과목/03-02 월 10-00.caf"])
        #expect(removed == 1)
        #expect(files.isDirectory(at: storage.url(for: "학기/과목")))
        #expect(!files.isDirectory(at: storage.url(for: "학기/다른과목")))
    }

    @Test func 녹음_중이_아니면_같은_폴더도_지운다() throws {
        let (storage, files) = try store([], directories: ["학기", "학기/과목"])
        #expect(storage.removeEmptyFolders(protecting: []) == 2)
        #expect(!files.isDirectory(at: storage.url(for: "학기/과목")))
    }

    @Test func 폴더_아래에_녹음_중_파일이_있는지_경계를_구분한다() {
        let active: Set<String> = ["학기/과목/a.caf"]
        #expect(RecordingStorage.folder("학기/과목", containsActive: active))
        #expect(RecordingStorage.folder("학기", containsActive: active))
        #expect(!RecordingStorage.folder("학기/과", containsActive: active))
        #expect(!RecordingStorage.folder("학기/과목2", containsActive: active))
        #expect(!RecordingStorage.folder("학기/과목", containsActive: []))
    }

    @Test func 녹음_중인_폴더는_옮기지_않는다() throws {
        let (storage, files) = try store(["학기/과목/a.caf"])
        #expect(throws: StorageError.recordingInProgress) {
            try storage.moveFolder(from: "학기/과목", to: "학기/새과목", protecting: ["학기/과목/a.caf"])
        }
        #expect(files.fileExists(at: storage.url(for: "학기/과목/a.caf")))
        #expect(!storage.folderExists("학기/새과목"))
    }

    @Test func 옮길_자리가_녹음_중인_폴더여도_옮기지_않는다() throws {
        let (storage, _) = try store(["학기/과목/a.m4a", "학기/새과목/b.caf"])
        #expect(throws: StorageError.recordingInProgress) {
            try storage.moveFolder(from: "학기/과목", to: "학기/새과목", protecting: ["학기/새과목/b.caf"])
        }
    }

    @Test func DS_Store만_있는_폴더는_비었다고_본다() throws {
        let (storage, files) = try store(["예전과목/.DS_Store"], directories: ["예전과목"])
        #expect(storage.removeEmptyFolders() == 1)
        #expect(!files.isDirectory(at: storage.url(for: "예전과목")))
    }

    @Test func 숨김_파일이_있는_폴더는_지우지_않는다() throws {
        let (storage, files) = try store(["예전과목/.hidden"])
        #expect(storage.removeEmptyFolders() == 0)
        #expect(files.fileExists(at: storage.url(for: "예전과목/.hidden")))
    }
}
