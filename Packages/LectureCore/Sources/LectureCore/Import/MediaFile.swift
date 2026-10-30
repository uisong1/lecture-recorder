import Foundation

/// 가져올 수 있는 파일 종류. 확장자로 가린다.
public enum MediaFileKind: Equatable, Sendable {
    /// mp4 영상: 소리만 m4a로 꺼내 저장한다.
    case video
    /// m4a 소리: 그대로 복사한다.
    case audio

    public static let supportedExtensions = ["mp4", "m4a"]

    public init?(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "mp4": self = .video
        case "m4a": self = .audio
        default: return nil
        }
    }
}

/// 받거나 끌어다 놓은 파일이 정말 mp4/m4a 계열인지 가린다.
/// 서버가 오류 페이지(HTML)나 일부만 담긴 파일을 mp4 이름으로 돌려주는 경우를 걸러 내는 첫 관문이다.
public enum MediaFileValidator {
    /// 처음 몇 바이트만 보면 되는 만큼. `[크기 4바이트]["ftyp"][브랜드]`.
    public static let headerLength = 12

    /// 앞부분이 MP4 계열(ISO base media) 파일의 `ftyp` 상자로 시작하는지.
    public static func hasFtypBox(_ header: Data) -> Bool {
        let bytes = Array(header.prefix(headerLength))
        guard bytes.count >= 8 else { return false }
        return bytes[4..<8].elementsEqual(Array("ftyp".utf8))
    }

    /// 파일 앞부분을 읽어 `hasFtypBox(_:)`로 본다. 읽을 수 없으면 false.
    public static func hasFtypBox(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: headerLength) else { return false }
        return hasFtypBox(header)
    }
}

/// 영상 파일에서 소리만 꺼낸다. 테스트에서는 가짜 구현을 쓴다.
public protocol AudioExtracting: Sendable {
    /// `source`의 소리를 m4a로 `destination`에 쓰고 길이(초)를 돌려준다. 소리가 없거나 쓴 길이가 원본보다 짧으면 오류.
    func extractAudio(from source: URL, to destination: URL) async throws -> TimeInterval
}

public enum MediaImportError: Error, Equatable, LocalizedError {
    case unsupportedType(String)
    case notMediaFile(String)
    case noAudio(String)
    case unplayable(String)
    case notEnoughSpace
    case fileFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let name): "‘\(name)’은 가져올 수 없습니다. mp4, m4a 파일만 가져올 수 있습니다."
        case .notMediaFile(let name): "‘\(name)’은 정상적인 mp4/m4a 파일이 아닙니다. 파일이 일부만 받아졌거나 손상됐을 수 있습니다."
        case .noAudio(let name): "‘\(name)’에는 소리가 없습니다."
        case .unplayable(let name): "‘\(name)’의 재생 길이를 읽지 못했습니다."
        case .notEnoughSpace: "저장 공간이 부족해 가져오지 못했습니다."
        case .fileFailed(let reason): "파일을 처리하지 못했습니다: \(reason)"
        case .saveFailed(let reason): "저장하지 못했습니다: \(reason)"
        }
    }
}
