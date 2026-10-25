import Testing
@testable import LectureCore

@Suite struct VolumeNormalizerTests {
    @Test func 이미_큰_녹음은_그대로_둔다() {
        #expect(VolumeNormalizer.gain(forPeak: 1.0) == 1)
        #expect(VolumeNormalizer.gain(forPeak: VolumeNormalizer.targetPeak) == 1)
    }

    @Test func 조금_작은_정도는_건드리지_않는다() {
        // 필요한 배율이 minimumGain보다 작다.
        #expect(VolumeNormalizer.gain(forPeak: 0.85) == 1)
    }

    @Test func 작은_녹음은_가장_큰_소리가_목표에_닿게_키운다() {
        let gain = VolumeNormalizer.gain(forPeak: 0.2)
        #expect(abs(gain * 0.2 - VolumeNormalizer.targetPeak) < 0.0001)
    }

    @Test func 키운_뒤에도_클리핑되지_않는다() {
        for peak in stride(from: Float(0.002), through: 1.0, by: 0.01) {
            #expect(gain(peak) * peak <= 1)
        }
    }

    @Test func 아주_작은_녹음은_최대_배율에서_멈춘다() {
        #expect(VolumeNormalizer.gain(forPeak: 0.01) == VolumeNormalizer.maxGain)
        #expect(VolumeNormalizer.gain(forPeak: 0.002) == VolumeNormalizer.maxGain)
    }

    @Test func 무음에_가까우면_잡음을_키우지_않는다() {
        #expect(VolumeNormalizer.gain(forPeak: 0) == 1)
        #expect(VolumeNormalizer.gain(forPeak: VolumeNormalizer.silencePeak) == 1)
    }

    @Test func 비정상_값은_그대로_둔다() {
        #expect(VolumeNormalizer.gain(forPeak: .nan) == 1)
        #expect(VolumeNormalizer.gain(forPeak: .infinity) == 1)
        #expect(VolumeNormalizer.gain(forPeak: -0.5) == 1)
    }

    private func gain(_ peak: Float) -> Float { VolumeNormalizer.gain(forPeak: peak) }
}
