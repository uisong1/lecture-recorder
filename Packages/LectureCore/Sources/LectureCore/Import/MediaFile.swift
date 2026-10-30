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

extension MediaFileValidator {
    /// 받은 파일이 로그인 페이지 같은 HTML인지. 세션이 만료되면 서버가 영상 대신 이런 페이지를 준다.
    public static func looksLikeHTML(_ header: Data) -> Bool {
        let text = String(decoding: header.prefix(256), as: UTF8.self).lowercased()
        return text.contains("<!doctype html") || text.contains("<html") || text.contains("<head")
    }

    /// 받은 파일이 스트리밍 목록(HLS/DASH)인지. 영상 조각을 따로 받아야 하는 형식이라 통째로 받은 mp4가 아니다.
    public static func looksLikeStreamingManifest(_ header: Data) -> Bool {
        let text = String(decoding: header.prefix(256), as: UTF8.self)
        return text.hasPrefix("#EXTM3U") || text.contains("<MPD")
    }

    /// moov를 이만큼보다 크게 읽지는 않는다.
    static let maxMoovBytes: UInt64 = 64 * 1024 * 1024

    /// mp4 안의 소리·영상이 DRM/암호화(CENC 등)로 보호돼 있는지. 최상위 상자를 건너뛰며 `moov`만 읽어 보호 표시(`sinf`, `encv`, `enca`, `schm`, `cenc`)를 찾는다.
    /// 판단할 수 없으면(상자가 깨졌거나 moov가 너무 큼) false다. 이 검사는 보호된 영상을 가려내 멈추기 위한 것이지 우회하려는 것이 아니다.
    public static func isEncrypted(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return false }
        var offset: UInt64 = 0
        while offset + 8 <= end {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16), header.count >= 8 else { return false }
            let bytes = [UInt8](header)
            var size = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            let type = String(decoding: bytes[4..<8], as: UTF8.self)
            var headerSize: UInt64 = 8
            if size == 1 {
                guard bytes.count >= 16 else { return false }
                size = bytes[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                headerSize = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerSize else { return false }
            if type == "moov" {
                let bodySize = size - headerSize
                guard bodySize <= maxMoovBytes,
                      (try? handle.seek(toOffset: offset + headerSize)) != nil,
                      let body = try? handle.read(upToCount: Int(bodySize)) else { return false }
                return protectionMarkers.contains { body.range(of: Data($0.utf8)) != nil }
            }
            offset += size
        }
        return false
    }

    private static let protectionMarkers = ["sinf", "encv", "enca", "schm", "cenc", "cbcs"]
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
