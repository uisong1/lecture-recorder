import Foundation

/// 녹음 중 녹음기가 실제로 녹음하고 있는지 확인한다. 10초마다 `check`를 부르면 녹음기가 끝났다고 알렸거나
/// 경과 시간이 30초(연속 3번 점검) 동안 늘지 않을 때 멈춘 이유를 돌려준다. 멈춘 뒤 저장과 안내는 부르는 쪽이 한다.
/// 자동으로 새 파일에 이어 녹음하지는 않는다 (사용자가 다시 시작한다).
@MainActor
struct RecorderHealthMonitor {
    private var detector = RecorderStallDetector()

    /// 저장 자체가 실패한 경우에도 멈춘 사실은 크게 보이도록 쓰는 안내.
    static let unsavedNotice = "녹음이 멈춘 것 같습니다. 녹음을 다시 시작하세요."

    /// 멈춘 녹음을 여기까지 저장했을 때의 안내.
    static func savedNotice(title: String) -> String {
        "녹음이 멈춘 것 같습니다. '\(title)' 녹음을 여기까지 저장했습니다. 녹음을 다시 시작하세요."
    }

    /// 새 녹음을 시작할 때 지난 점검 기록을 지운다.
    mutating func reset() {
        detector.reset()
    }

    /// 멈춘 것으로 보이면 그 이유, 건강하면 nil. 일시정지 중에는 시간이 서지 않는 게 정상이라 멈춘 것으로 보지 않는다.
    mutating func check(_ recorder: any AudioRecording, isPaused: Bool) -> RecorderStallDetector.Reason? {
        let verdict = detector.update(elapsed: recorder.currentTime, isPaused: isPaused, recorderEnded: recorder.hasEnded)
        guard case .stalled(let reason) = verdict else { return nil }
        return reason
    }
}
