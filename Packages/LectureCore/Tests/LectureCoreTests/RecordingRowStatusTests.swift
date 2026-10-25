import Foundation
import Testing
@testable import LectureCore

@Suite struct RecordingRowStatusTests {
    let files = FakeFileStore()
    var storage: RecordingStorage {
        RecordingStorage(root: URL(filePath: "/tmp/LectureRecorderTests/Recordings", directoryHint: .isDirectory), files: files)
    }

    func status(_ path: String, exists: Bool = true, recovered: Bool = false) -> RecordingRowStatus {
        if exists { files.add(storage.url(for: path)) }
        return RecordingRowStatus(relativePath: path, isRecovered: recovered, storage: storage)
    }

    @Test func 평범한_녹음은_상태_글자가_없다() {
        let result = status("미분류/a.m4a")
        #expect(result.labels.isEmpty)
        #expect(result.isPlayable)
    }

    @Test func 아직_caf이면_압축_중() {
        #expect(status("미분류/a.caf").labels == ["압축 중"])
    }

    @Test func 되살린_녹음은_복구됨() {
        #expect(status("미분류/a.m4a", recovered: true).labels == ["복구됨"])
    }

    @Test func 압축_중이면서_복구된_녹음은_둘_다_보인다() {
        #expect(status("미분류/a.caf", recovered: true).labels == ["압축 중", "복구됨"])
    }

    @Test func 파일이_없으면_파일_없음만_보이고_재생할_수_없다() {
        let result = status("미분류/a.caf", exists: false, recovered: true)
        #expect(result.labels == ["파일 없음"])
        #expect(!result.isPlayable)
        #expect(!result.isCompressing)
    }

    @Test func 북마크_글자는_하나_이상일_때만() {
        #expect(RecordingRowStatus.bookmarkLabel(count: 0) == nil)
        #expect(RecordingRowStatus.bookmarkLabel(count: 3) == "북마크 3")
    }
}
