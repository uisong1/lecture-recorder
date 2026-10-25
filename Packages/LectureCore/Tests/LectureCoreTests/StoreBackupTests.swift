import Foundation
import Testing
@testable import LectureCore

@Suite struct StoreBackupTests {
    let support = URL(filePath: "/tmp/LectureRecorderTests/Support", directoryHint: .isDirectory)
    let backups = URL(filePath: "/tmp/LectureRecorderTests/Backups", directoryHint: .isDirectory)
    let files = FakeFileStore()

    var store: URL { support.appending(path: "default.store") }

    func backup(on day: Date = date(2026, 10, 25, 9, 0)) -> StoreBackup {
        StoreBackup(storeURL: store, backupsRoot: backups, files: files, now: { day }, calendar: seoulCalendar)
    }

    func addStore(sidecars: Bool = true) {
        files.add(store)
        files.sizes[store.standardizedFileURL.path] = 4_096
        if sidecars {
            for suffix in ["-wal", "-shm"] {
                let url = support.appending(path: "default.store" + suffix)
                files.add(url)
                files.sizes[url.standardizedFileURL.path] = 512
            }
        }
    }

    func addOldBackup(_ day: String) {
        files.add(backups.appending(path: "\(day)/default.store"))
    }

    func exists(_ path: String) -> Bool {
        files.fileExists(at: backups.appending(path: path))
    }

    @Test func 저장소가_아직_없으면_할_일이_없다() {
        #expect(backup().backupIfNeeded() == .noStore)
        #expect(!files.fileExists(at: backups))
    }

    @Test func 저장소와_부속_파일을_날짜_폴더에_복사한다() {
        addStore()

        let outcome = backup().backupIfNeeded()

        #expect(outcome == .created(day: "2026-10-25", removedOld: 0))
        #expect(exists("2026-10-25/default.store"))
        #expect(exists("2026-10-25/default.store-wal"))
        #expect(exists("2026-10-25/default.store-shm"))
        // 원본은 그대로다.
        #expect(files.fileExists(at: store))
    }

    @Test func 부속_파일이_없으면_본_파일만_복사한다() {
        addStore(sidecars: false)

        #expect(backup().backupIfNeeded() == .created(day: "2026-10-25", removedOld: 0))
        #expect(exists("2026-10-25/default.store"))
        #expect(!exists("2026-10-25/default.store-wal"))
    }

    @Test func 같은_날_두_번째는_새로_만들지_않는다() {
        addStore()
        backup().backupIfNeeded()
        files.failNextCopy = true

        let second = backup(on: date(2026, 10, 25, 23, 59)).backupIfNeeded()

        #expect(second == .alreadyBackedUp)
        // 복사를 시도하지 않았으니 실패 예약이 남아 있다.
        #expect(files.failNextCopy)
    }

    @Test func 다음_날에는_새로_만든다() {
        addStore()
        backup().backupIfNeeded()

        let next = backup(on: date(2026, 10, 26, 0, 0)).backupIfNeeded()

        #expect(next == .created(day: "2026-10-26", removedOld: 0))
        #expect(exists("2026-10-25/default.store"))
        #expect(exists("2026-10-26/default.store"))
    }

    @Test func 세_개를_넘으면_가장_오래된_백업부터_지운다() {
        addStore()
        for day in ["2026-10-20", "2026-10-21", "2026-10-22"] { addOldBackup(day) }

        let outcome = backup().backupIfNeeded()

        #expect(outcome == .created(day: "2026-10-25", removedOld: 1))
        #expect(!exists("2026-10-20/default.store"))
        #expect(exists("2026-10-21/default.store"))
        #expect(exists("2026-10-22/default.store"))
        #expect(exists("2026-10-25/default.store"))
    }

    @Test func 한꺼번에_많이_쌓여_있어도_세_개만_남긴다() {
        addStore()
        for day in ["2026-09-01", "2026-09-02", "2026-09-03", "2026-10-01", "2026-10-02"] { addOldBackup(day) }

        #expect(backup().backupIfNeeded() == .created(day: "2026-10-25", removedOld: 3))
        #expect(exists("2026-10-02/default.store"))
        #expect(exists("2026-10-01/default.store"))
        #expect(!exists("2026-09-03/default.store"))
    }

    @Test func 날짜_폴더가_아닌_항목은_건드리지_않는다() {
        addStore()
        for day in ["2026-10-22", "2026-10-23", "2026-10-24"] { addOldBackup(day) }
        files.add(backups.appending(path: "메모.txt"))
        files.add(backups.appending(path: "2026-10-2x/default.store"))

        backup().backupIfNeeded()

        #expect(exists("메모.txt"))
        #expect(exists("2026-10-2x/default.store"))
        #expect(!exists("2026-10-22/default.store"))
    }

    @Test func 복사에_실패하면_앱은_계속_되고_예전_백업은_남는다() {
        addStore()
        for day in ["2026-10-22", "2026-10-23", "2026-10-24"] { addOldBackup(day) }
        files.failNextCopy = true

        let outcome = backup().backupIfNeeded()

        guard case .failed = outcome else {
            Issue.record("실패여야 함: \(outcome)")
            return
        }
        #expect(!exists("2026-10-25/default.store"))
        #expect(!files.fileExists(at: backups.appending(path: "2026-10-25")))
        for day in ["2026-10-22", "2026-10-23", "2026-10-24"] { #expect(exists("\(day)/default.store")) }
    }

    @Test func 복사본_크기가_다르면_실패로_보고_사본을_치운다() {
        addStore(sidecars: false)
        files.corruptNextCopy = true

        let outcome = backup().backupIfNeeded()

        guard case .failed = outcome else {
            Issue.record("실패여야 함: \(outcome)")
            return
        }
        #expect(!exists("2026-10-25/default.store"))
        // 다음에 다시 시도할 수 있다.
        #expect(backup().backupIfNeeded() == .created(day: "2026-10-25", removedOld: 0))
    }

    @Test func 본_파일_없이_남은_조각은_치우고_다시_만든다() {
        addStore()
        files.add(backups.appending(path: "2026-10-25"))
        files.add(backups.appending(path: "2026-10-25/default.store-wal"))
        files.add(backups.appending(path: "2026-10-25/stale-partial"))

        #expect(backup().backupIfNeeded() == .created(day: "2026-10-25", removedOld: 0))
        #expect(exists("2026-10-25/default.store"))
        #expect(!exists("2026-10-25/stale-partial"))
    }

    @Test func 백업_목록을_읽지_못해도_새_백업은_만들어진다() {
        addStore()
        addOldBackup("2026-10-24")
        files.failNextListing = true

        #expect(backup().backupIfNeeded() == .created(day: "2026-10-25", removedOld: 0))
        #expect(exists("2026-10-25/default.store"))
    }

    @Test(arguments: [
        ("2026-10-25", true), ("2026-1-5", false), ("2026-10-2x", false), ("메모.txt", false), ("2026-10-25-1", false), ("", false),
    ])
    func 날짜_폴더_이름을_알아본다(name: String, expected: Bool) {
        #expect(StoreBackup.isDayName(name) == expected)
    }
}
