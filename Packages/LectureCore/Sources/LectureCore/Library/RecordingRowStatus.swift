import Foundation

/// 녹음 목록 한 줄에 보일 상태. 파일을 직접 열어 보지 않고 있는지만 확인한다.
public struct RecordingRowStatus: Equatable, Sendable {
    /// 파일이 사라졌다. 이때는 재생할 수 없다.
    public var isMissing: Bool
    /// 아직 압축 전(CAF)이라 파일이 크다.
    public var isCompressing: Bool
    /// 앱이 꺼져서 남은 파일로 되살린 녹음.
    public var isRecovered: Bool

    public init(relativePath: String, isRecovered: Bool, storage: RecordingStorage) {
        isMissing = !storage.fileExists(at: storage.url(for: relativePath))
        // 파일이 없으면 압축 여부는 의미가 없다.
        isCompressing = !isMissing && RecordingStorage.isWorkingPath(relativePath)
        self.isRecovered = isRecovered
    }

    /// 재생을 시도해도 되는지.
    public var isPlayable: Bool { !isMissing }

    /// 줄에 덧붙일 상태 글자들 (예: ["압축 중", "복구됨"]). 없으면 빈 배열.
    public var labels: [String] {
        if isMissing { return ["파일 없음"] }
        var result: [String] = []
        if isCompressing { result.append("압축 중") }
        if isRecovered { result.append("복구됨") }
        return result
    }

    /// 재생할 수 없을 때 보일 안내.
    public static let missingFileNotice = "녹음 파일을 찾을 수 없습니다. 파일이 옮겨졌거나 지워졌을 수 있습니다. Finder에서 녹음 폴더를 확인해 주세요."

    /// 북마크 개수 글자 (예: "북마크 3"). 없으면 nil.
    public static func bookmarkLabel(count: Int) -> String? {
        count > 0 ? "북마크 \(count)" : nil
    }
}
