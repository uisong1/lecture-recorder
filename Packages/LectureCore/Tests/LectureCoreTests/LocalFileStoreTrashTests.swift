import Foundation
import Testing
@testable import LectureCore

@Suite struct LocalFileStoreTrashTests {
    func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LocalFileStoreTrashTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func 휴지통_폴더를_주면_그곳으로_옮기고_원본은_사라진다() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.m4a")
        try Data("소리".utf8).write(to: file)
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        let store = LocalFileStore(trashDirectory: trash)

        try store.trashItem(at: file)

        #expect(!store.fileExists(at: file))
        let moved = try store.contentsOfDirectory(at: trash)
        #expect(moved.count == 1)
        #expect(moved.first?.lastPathComponent.hasSuffix("-a.m4a") == true)
    }

    @Test func 같은_이름을_두_번_보내도_덮어쓰지_않는다() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        let store = LocalFileStore(trashDirectory: trash)
        let file = folder.appending(path: "a.m4a")

        for _ in 0..<2 {
            try Data("소리".utf8).write(to: file)
            try store.trashItem(at: file)
        }

        #expect(try store.contentsOfDirectory(at: trash).count == 2)
    }

    @Test func 없는_파일을_보내면_오류이고_휴지통_폴더는_그대로다() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalFileStore(trashDirectory: folder.appending(path: "Trash", directoryHint: .isDirectory))

        #expect(throws: (any Error).self) { try store.trashItem(at: folder.appending(path: "없음.m4a")) }
    }
}
