import Foundation
import Testing
@testable import LectureCore

@Suite struct MediaFileValidatorTests {
    /// 실제 mp4 앞부분: 크기 0x20, "ftyp", 브랜드 "isom".
    static let mp4Header = Data([0, 0, 0, 0x20] + Array("ftypisom".utf8))

    @Test func ftyp_상자로_시작하면_통과한다() {
        #expect(MediaFileValidator.hasFtypBox(Self.mp4Header))
    }

    @Test func html_오류_페이지는_통과하지_못한다() {
        #expect(!MediaFileValidator.hasFtypBox(Data("<!DOCTYPE html><html>".utf8)))
    }

    @Test func 너무_짧거나_비어_있으면_통과하지_못한다() {
        #expect(!MediaFileValidator.hasFtypBox(Data()))
        #expect(!MediaFileValidator.hasFtypBox(Data([0, 0, 0, 0x20, 0x66, 0x74, 0x79])))
    }

    @Test func 파일로_읽어서도_가린다() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appending(path: "good.mp4")
        let bad = directory.appending(path: "bad.mp4")
        try Self.mp4Header.write(to: good)
        try Data("not a video".utf8).write(to: bad)

        #expect(MediaFileValidator.hasFtypBox(at: good))
        #expect(!MediaFileValidator.hasFtypBox(at: bad))
        #expect(!MediaFileValidator.hasFtypBox(at: directory.appending(path: "missing.mp4")))
    }

    @Test func 확장자로_종류를_가린다() {
        #expect(MediaFileKind(fileName: "screen.mp4") == .video)
        #expect(MediaFileKind(fileName: "수업.M4A") == .audio)
        #expect(MediaFileKind(fileName: "memo.txt") == nil)
        #expect(MediaFileKind(fileName: "noextension") == nil)
    }
}
