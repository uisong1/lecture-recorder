import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingsFolderInfoTests {
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)

    @Test func 폴더가_있으면_위치와_함께_열_수_있다() throws {
        let files = FakeFileStore()
        try files.createDirectory(at: root)
        let info = RecordingStorage(root: root, files: files).folderInfo()
        #expect(info.url == root)
        #expect(info.isAvailable)
    }

    @Test func 폴더가_없으면_열_수_없다() {
        let info = RecordingStorage(root: root, files: FakeFileStore()).folderInfo()
        #expect(info.url == root)
        #expect(!info.isAvailable)
    }

    @Test func 홈_아래_경로는_물결표로_줄여_보인다() {
        let home = URL(filePath: "/Users/song", directoryHint: .isDirectory)
        let info = RecordingsFolderInfo(url: URL(filePath: "/Users/song/Library/Application Support/LectureRecorder/Recordings", directoryHint: .isDirectory), isAvailable: true)
        #expect(info.displayPath(home: home) == "~/Library/Application Support/LectureRecorder/Recordings")
    }

    @Test func 홈_밖_경로와_홈_자체() {
        let home = URL(filePath: "/Users/song", directoryHint: .isDirectory)
        #expect(RecordingsFolderInfo(url: URL(filePath: "/Users/songwriter/x"), isAvailable: true).displayPath(home: home) == "/Users/songwriter/x")
        #expect(RecordingsFolderInfo(url: home, isAvailable: true).displayPath(home: home) == "~")
    }

    @Test func 보관_안내는_폴더를_옮기지_말라고_알린다() {
        #expect(RecordingsFolderInfo.archiveGuide.contains("통째로 복사"))
        #expect(RecordingsFolderInfo.archiveGuide.contains("옮기지 마세요"))
    }
}
