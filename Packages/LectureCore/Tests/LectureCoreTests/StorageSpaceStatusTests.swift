import Testing
@testable import LectureCore

@Suite struct StorageSpaceStatusTests {
    @Test func 경계값_1시간_분량_이상이면_충분하다() {
        #expect(StorageSpaceStatus.assess(freeBytes: StorageSpaceStatus.warningBytes) == .enough)
        #expect(StorageSpaceStatus.assess(freeBytes: StorageSpaceStatus.warningBytes + 1) == .enough)
        #expect(StorageSpaceStatus.assess(freeBytes: 500 * 1024 * 1024 * 1024) == .enough)
    }

    @Test func 경계값_1시간_분량_바로_아래는_경고이고_남은_분을_센다() {
        #expect(StorageSpaceStatus.assess(freeBytes: StorageSpaceStatus.warningBytes - 1) == .low(minutesLeft: 59))
        #expect(StorageSpaceStatus.assess(freeBytes: RecordingFormat.workingBytes(for: 1_800)) == .low(minutesLeft: 30))
        #expect(StorageSpaceStatus.assess(freeBytes: StorageSpaceStatus.criticalBytes) == .low(minutesLeft: 10))
    }

    @Test func 경계값_10분_분량_아래는_자동_정지_대상이다() {
        #expect(StorageSpaceStatus.assess(freeBytes: StorageSpaceStatus.criticalBytes - 1) == .critical)
        #expect(StorageSpaceStatus.assess(freeBytes: 0) == .critical)
    }

    @Test func 경고_문구는_부족할_때만_있다() {
        #expect(StorageSpaceStatus.enough.warningMessage == nil)
        #expect(StorageSpaceStatus.critical.warningMessage == nil)
        #expect(StorageSpaceStatus.low(minutesLeft: 25).warningMessage == "저장 공간이 부족합니다. 약 25분 더 녹음할 수 있어요. 공간을 비워 주세요.")
    }

#if canImport(SwiftData)
    @MainActor @Test func 컨트롤러의_기준값은_같은_값을_쓴다() {
        #expect(RecordingController.storageWarningBytes == StorageSpaceStatus.warningBytes)
        #expect(RecordingController.storageCriticalBytes == StorageSpaceStatus.criticalBytes)
    }
#endif
}
