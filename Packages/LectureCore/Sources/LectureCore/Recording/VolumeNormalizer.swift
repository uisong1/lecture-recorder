import Foundation

/// 압축할 때 작은 녹음의 음량을 키우는 배율을 정한다. 계산만 하는 순수 함수라 UI·오디오 없이 테스트한다.
public enum VolumeNormalizer {
    /// 키운 뒤 가장 큰 소리가 이 값(선형, 1.0 = 최대)에 닿게 한다. 약 -1 dBFS로 클리핑 여유를 둔다.
    public static let targetPeak: Float = 0.89
    /// 최대 배율. 약 +18 dB. 아주 작은 녹음에서 잡음만 키우지 않도록 한계를 둔다.
    public static let maxGain: Float = 8
    /// 이 값(약 -60 dBFS)보다 작은 피크는 사실상 무음이라 그대로 둔다.
    public static let silencePeak: Float = 0.001
    /// 이 배율보다 작게 달라지면 키우지 않는다. 이미 충분히 큰 녹음을 괜히 건드리지 않는다.
    public static let minimumGain: Float = 1.1

    /// 가장 큰 소리 크기(`peak`, 0...1)에 곱할 배율. 줄이는 일은 없고(1 이상), 클리핑이 생기지 않는다.
    public static func gain(forPeak peak: Float) -> Float {
        guard peak.isFinite, peak > silencePeak else { return 1 }
        let wanted = targetPeak / peak
        guard wanted >= minimumGain else { return 1 }
        return min(wanted, maxGain)
    }
}
