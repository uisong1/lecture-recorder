import Foundation

/// 녹음 파일 형식과 크기 계산. 녹음기·변환기·복구·저장 공간 검사가 같은 값을 쓴다.
/// 녹음 중에는 PCM(CAF)으로 쓰고, 정지 뒤 AAC(m4a)로 압축한다. 둘 다 모노다.
public enum RecordingFormat {
    /// 녹음 중 PCM의 샘플레이트. 음성 강의에는 8kHz 대역까지면 충분하다.
    public static let workingSampleRate: Double = 16_000
    public static let workingBitDepth = 16
    /// 압축한 AAC의 비트레이트 (bit/s).
    public static let compressedBitRate = 32_000

    /// 녹음 중 파일이 1초에 늘어나는 바이트 수 (32,000).
    public static var workingBytesPerSecond: Int64 {
        Int64(workingSampleRate) * Int64(workingBitDepth / 8)
    }

    /// 압축한 파일이 1초에 늘어나는 바이트 수 (4,000).
    public static var compressedBytesPerSecond: Int64 {
        Int64(compressedBitRate / 8)
    }

    /// `seconds`초 녹음했을 때 압축 전 CAF의 크기.
    public static func workingBytes(for seconds: TimeInterval) -> Int64 {
        Int64(max(0, seconds)) * workingBytesPerSecond
    }

    /// `seconds`초 녹음을 압축한 m4a의 크기.
    public static func compressedBytes(for seconds: TimeInterval) -> Int64 {
        Int64(max(0, seconds)) * compressedBytesPerSecond
    }
}
