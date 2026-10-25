import Testing
@testable import LectureCore

@Suite struct RecordingFormatTests {
    static let threeHours: Double = 3 * 3_600

    @Test func 세_시간_녹음의_파일_크기를_계산한다() {
        #expect(RecordingFormat.workingBytes(for: Self.threeHours) == 345_600_000) // 약 346MB
        #expect(RecordingFormat.compressedBytes(for: Self.threeHours) == 43_200_000) // 약 43MB
    }

    @Test func 압축하면_녹음_중_파일의_8분의_1이다() {
        #expect(RecordingFormat.workingBytes(for: 1_000) == RecordingFormat.compressedBytes(for: 1_000) * 8)
    }

    @Test func 음수_길이는_0바이트() {
        #expect(RecordingFormat.workingBytes(for: -5) == 0)
        #expect(RecordingFormat.compressedBytes(for: -5) == 0)
    }

}

#if canImport(SwiftData)
@MainActor
@Suite struct RecordingStorageLimitTests {
    @Test func 세_시간_녹음과_압축본이_함께_있어도_시작_여유_공간_안에_든다() {
        let both = RecordingFormat.workingBytes(for: RecordingFormatTests.threeHours) + RecordingFormat.compressedBytes(for: RecordingFormatTests.threeHours)
        #expect(both < RecordingController.minimumFreeBytes)
    }

    @Test func 경고는_바닥_자동정지보다_먼저_온다() {
        #expect(RecordingController.storageWarningBytes > RecordingController.storageCriticalBytes)
        #expect(RecordingController.storageWarningBytes == 115_200_000) // 1시간 분량
    }
}
#endif
