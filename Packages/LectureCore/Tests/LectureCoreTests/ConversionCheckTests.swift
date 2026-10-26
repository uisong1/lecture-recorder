import Testing
@testable import LectureCore

struct ConversionCheckTests {
    @Test func 같은_길이는_완료() {
        #expect(ConversionCheck.isComplete(sourceSeconds: 10_800, convertedSeconds: 10_800))
    }

    @Test func AAC_여유로_조금_짧거나_긴_것은_완료() {
        #expect(ConversionCheck.isComplete(sourceSeconds: 60, convertedSeconds: 59.5))
        #expect(ConversionCheck.isComplete(sourceSeconds: 60, convertedSeconds: 60.2))
    }

    @Test func 뒷부분만_남은_압축본은_미완료() {
        #expect(!ConversionCheck.isComplete(sourceSeconds: 10_800, convertedSeconds: 5_400))
        #expect(!ConversionCheck.isComplete(sourceSeconds: 60, convertedSeconds: 0))
    }

    @Test func 긴_녹음은_비율만큼_허용() {
        #expect(ConversionCheck.isComplete(sourceSeconds: 10_800, convertedSeconds: 10_760))
        #expect(!ConversionCheck.isComplete(sourceSeconds: 10_800, convertedSeconds: 10_700))
    }

    @Test func 길이_0인_원본은_완료() {
        #expect(ConversionCheck.isComplete(sourceSeconds: 0, convertedSeconds: 0))
    }
}
