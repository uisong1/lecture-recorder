import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingBundleExporterTests {
    let root = URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory)
    let parent = URL(filePath: "/tmp/LectureRecorderTests/Out", directoryHint: .isDirectory)
    let files = FakeFileStore()
    let storage: RecordingStorage
    let exporter: RecordingBundleExporter
    let now = date(2026, 10, 25, 20, 0)

    init() {
        storage = RecordingStorage(root: root, files: files)
        exporter = RecordingBundleExporter(storage: storage, files: files, calendar: seoulCalendar)
    }

    func recording(
        _ title: String = "1주차",
        subject: String? = "자료구조",
        at start: Date = date(2026, 3, 2, 10, 0),
        duration: TimeInterval = 3000,
        path: String = "2026년 1학기/자료구조/03-02 월 10-00.m4a",
        bookmarks: [BundleBookmark] = [],
        exists: Bool = true
    ) -> BundleRecording {
        if exists { files.add(storage.url(for: path)) }
        return BundleRecording(title: title, subjectName: subject, semester: "2026년 1학기", startedAt: start, duration: duration, relativePath: path, bookmarks: bookmarks)
    }

    func summary(_ result: RecordingBundleResult) throws -> String {
        let url = result.folder.appending(path: RecordingBundleExporter.summaryFileName)
        let data = try #require(files.written[url.standardizedFileURL.path])
        return String(decoding: data, as: UTF8.self)
    }

    @Test func 녹음_파일을_복사하고_원본은_그대로_둔다() throws {
        let r = recording()
        let result = try exporter.export([r], label: "자료구조", to: parent, now: now)
        #expect(result.folder.lastPathComponent == "Claude용 묶음 자료구조 2026-10-25")
        #expect(result.exportedCount == 1)
        #expect(files.fileExists(at: result.folder.appending(path: "녹음/자료구조 2026-03-02 월 10-00.m4a")))
        #expect(files.fileExists(at: storage.url(for: r.relativePath)))
    }

    @Test func 글에_과목_날짜_길이_북마크_메모가_들어간다() throws {
        let r = recording(bookmarks: [
            BundleBookmark(time: 3723, note: "시험에 나옴"),
            BundleBookmark(time: 754, note: "정의\n다시 보기"),
            BundleBookmark(time: 30, note: ""),
        ])
        let text = try summary(try exporter.export([r], label: "자료구조", to: parent, now: now))
        #expect(text.contains("# 수업 녹음: 자료구조"))
        #expect(text.contains("## 자료구조 (2026년 1학기)"))
        #expect(text.contains("### 1. 1주차"))
        #expect(text.contains("- 날짜: 2026-03-02 (월) 10:00"))
        #expect(text.contains("- 길이: 50분"))
        #expect(text.contains("- 파일: `녹음/자료구조 2026-03-02 월 10-00.m4a`"))
        #expect(text.contains("- 북마크 3개:"))
        // 시각 순서로 적고, 메모의 줄바꿈은 한 줄로 합치며, 빈 메모는 표시한다.
        let order = ["00:30 — (메모 없음)", "12:34 — 정의 다시 보기", "1:02:03 — 시험에 나옴"].compactMap { text.range(of: $0)?.lowerBound }
        #expect(order.count == 3)
        #expect(order == order.sorted())
    }

    @Test func 수업_메모는_있을_때만_한_줄로_적는다() throws {
        var withMemo = recording(path: "a/1.m4a")
        withMemo.memo = "중간고사\n범위 발표"
        let without = recording("2주차", at: date(2026, 3, 9, 10, 0), path: "a/2.m4a")
        let text = try summary(try exporter.export([withMemo, without], label: "자료구조", to: parent, now: now))
        #expect(text.contains("- 수업 메모: 중간고사 범위 발표"))
        #expect(text.components(separatedBy: "수업 메모").count == 2)
    }

    @Test func 북마크가_없으면_없음이라고_적는다() throws {
        let text = try summary(try exporter.export([recording()], label: "자료구조", to: parent, now: now))
        #expect(text.contains("- 북마크: 없음"))
    }

    @Test func 과목별로_묶고_오래된_수업부터_적는다() throws {
        let later = recording("2주차", at: date(2026, 3, 9, 10, 0), path: "a/2.m4a")
        let other = recording("물리 1주차", subject: "물리", at: date(2026, 3, 3, 9, 0), path: "b/1.m4a")
        let earlier = recording("1주차", at: date(2026, 3, 2, 10, 0), path: "a/1.m4a")
        let text = try summary(try exporter.export([later, other, earlier], label: "모든 녹음", to: parent, now: now))
        let positions = ["## 자료구조", "### 1. 1주차", "### 2. 2주차", "## 물리", "### 1. 물리 1주차"].map { text.range(of: $0)?.lowerBound }
        #expect(!positions.contains { $0 == nil })
        // 자료구조 2주차가 물리보다 먼저 나온다 (과목 순서는 가장 오래된 수업 기준).
        #expect(text.range(of: "### 2. 2주차")!.lowerBound < text.range(of: "## 물리")!.lowerBound)
        #expect(text.contains("- 녹음 3개, 총 "))
    }

    @Test func 과목이_없으면_미분류로_적는다() throws {
        let r = recording(subject: nil, path: "미분류/03-02 월 10-00.m4a")
        let result = try exporter.export([r], label: "미분류", to: parent, now: now)
        #expect(try summary(result).contains("## 미분류"))
        #expect(files.fileExists(at: result.folder.appending(path: "녹음/미분류 2026-03-02 월 10-00.m4a")))
    }

    @Test func 같은_시각의_녹음은_파일_이름에_번호를_붙인다() throws {
        let a = recording("가", path: "x/a.m4a")
        let b = recording("나", path: "y/b.m4a")
        let result = try exporter.export([a, b], label: "자료구조", to: parent, now: now)
        #expect(files.fileExists(at: result.folder.appending(path: "녹음/자료구조 2026-03-02 월 10-00.m4a")))
        #expect(files.fileExists(at: result.folder.appending(path: "녹음/자료구조 2026-03-02 월 10-00_2.m4a")))
    }

    @Test func 파일이_없는_녹음은_건너뛰고_알린다() throws {
        let ok = recording("있음", path: "a/ok.m4a")
        let missing = recording("빠진녹음", at: date(2026, 3, 3, 10, 0), path: "a/missing.m4a", exists: false)
        let result = try exporter.export([ok, missing], label: "자료구조", to: parent, now: now)
        #expect(result.exportedCount == 1)
        #expect(result.skippedTitles == ["빠진녹음"])
        #expect(!(try summary(result).contains("빠진녹음")))
    }

    @Test func 담을_녹음이_없거나_파일이_모두_없으면_오류() {
        #expect(throws: RecordingBundleError.nothingToExport) { try exporter.export([], label: "x", to: parent, now: now) }
        let missing = recording(path: "a/missing.m4a", exists: false)
        #expect(throws: RecordingBundleError.self) { try exporter.export([missing], label: "x", to: parent, now: now) }
        #expect(files.allPaths.filter { $0.hasPrefix(parent.path) }.isEmpty)
    }

    @Test func 같은_이름의_묶음이_있으면_번호를_붙여_덮어쓰지_않는다() throws {
        let r = recording()
        let first = try exporter.export([r], label: "자료구조", to: parent, now: now)
        let second = try exporter.export([r], label: "자료구조", to: parent, now: now)
        #expect(first.folder != second.folder)
        #expect(second.folder.lastPathComponent == "Claude용 묶음 자료구조 2026-10-25_2")
    }

    @Test func 복사에_실패하면_만들던_폴더를_지우고_원본은_남는다() throws {
        let r = recording()
        files.failNextCopy = true
        #expect(throws: RecordingBundleError.self) { try exporter.export([r], label: "자료구조", to: parent, now: now) }
        #expect(files.allPaths.filter { $0.hasPrefix(parent.path) }.isEmpty)
        #expect(files.fileExists(at: storage.url(for: r.relativePath)))
    }

    @Test func 글을_쓰지_못해도_만들던_폴더를_지운다() throws {
        let r = recording()
        files.failNextWrite = true
        #expect(throws: RecordingBundleError.self) { try exporter.export([r], label: "자료구조", to: parent, now: now) }
        #expect(files.allPaths.filter { $0.hasPrefix(parent.path) }.isEmpty)
    }

    @Test func 폴더_이름의_위험한_글자는_바꾼다() throws {
        let result = try exporter.export([recording()], label: "컴구/운영:체제", to: parent, now: now)
        #expect(result.folder.lastPathComponent == "Claude용 묶음 컴구-운영-체제 2026-10-25")
        #expect(result.folder.deletingLastPathComponent().path == parent.path)
    }

    @Test func 시각과_길이_표기() {
        #expect(RecordingBundleExporter.clockText(0) == "00:00")
        #expect(RecordingBundleExporter.clockText(3599) == "59:59")
        #expect(RecordingBundleExporter.clockText(3600) == "1:00:00")
        #expect(RecordingBundleExporter.durationText(30) == "30초")
        #expect(RecordingBundleExporter.durationText(3000) == "50분")
        #expect(RecordingBundleExporter.durationText(3900) == "1시간 5분")
        #expect(RecordingBundleExporter.durationText(7200) == "2시간")
    }
}
