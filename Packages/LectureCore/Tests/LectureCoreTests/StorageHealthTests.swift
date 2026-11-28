import Testing
@testable import LectureCore

@MainActor
@Suite struct StorageHealthTests {
    final class Remaining { var value = 2 }

    @Test func 문제가_없으면_줄이_없다() {
        let health = StorageHealth()
        #expect(health.lines.isEmpty)
        #expect(!health.hasProblems)
        #expect(health.libraryLine == nil)
    }

    @Test func 실패_개수를_문구로_바꾼다() {
        let lines = StorageHealth.lines(uncompressed: 2, uncompressedBytes: 700_000_000, unmigrated: 1, unrecovered: 3)
        #expect(lines.map(\.kind) == [.uncompressed, .unmigrated, .unrecovered])
        #expect(lines[0].title == "압축하지 못한 녹음 2개")
        #expect(lines[0].detail.hasPrefix("원본(CAF)은 그대로 있어요 · 약 "))
        #expect(lines[1].title == "폴더로 옮기지 못한 녹음 1개")
        #expect(lines[1].detail == "예전 폴더에 그대로 있어 재생은 돼요")
        #expect(lines[2].title == "되살리지 못한 녹음 3개")
    }

    @Test func 크기를_모르면_크기는_빼고_보인다() {
        let lines = StorageHealth.lines(uncompressed: 1, uncompressedBytes: 0, unmigrated: 0, unrecovered: 0)
        #expect(lines == [.init(kind: .uncompressed, title: "압축하지 못한 녹음 1개", detail: "원본(CAF)은 그대로 있어요")])
    }

    @Test func 모든_녹음_화면에는_압축_실패만_보인다() {
        let health = StorageHealth()
        health.setUnmigrated(1)
        #expect(health.hasProblems)
        #expect(health.libraryLine == nil)

        health.countUncompressed = { (2, 0) }
        health.refreshUncompressed()
        #expect(health.libraryLine?.title == "압축하지 못한 녹음 2개")
    }

    @Test func 압축을_다시_시도하면_남은_개수를_다시_센다() async {
        let health = StorageHealth()
        let remaining = Remaining()
        health.countUncompressed = { (remaining.value, 0) }
        health.refreshUncompressed()
        health.retryCompression = { remaining.value = 0 }

        await health.retryCompressionNow()

        #expect(health.uncompressedCount == 0)
        #expect(!health.isRetrying)
    }

    @Test func 폴더_정리를_다시_시도하면_실패_개수를_바꾼다() async {
        let health = StorageHealth()
        health.setUnmigrated(3)
        health.retryMigration = { 1 }

        await health.retryMigrationNow()

        #expect(health.unmigratedCount == 1)
    }
}
