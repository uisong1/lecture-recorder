#if canImport(SwiftData)
import Foundation

/// 전사 대기열 한 줄에 보일 상태와 버튼 (시안 transcribe-rows: 멈추는 중 → 멈춤·N%까지 함 + 이어서/빼기, 실패 이유 + 도우미 마지막 줄).
public struct TranscriptionRowDisplay: Equatable, Sendable {
    public enum Action: Hashable, Sendable {
        case pause, resume, remove, retry, open

        public var title: String {
            switch self {
            case .pause: "멈춤"
            case .resume: "이어서"
            case .remove: "빼기"
            case .retry: "다시 시도"
            case .open: "보기"
            }
        }
    }

    /// 굵은 상태 글 (예: "전사 중 62%", "멈춤 · 66%까지 함", "실패: 모델을 불러오지 못했어요").
    public let status: String
    /// 상태 옆 작은 회색 글 (예: "지금 조각까지"). 남은 시간은 `remainingSeconds`로 따로 준다.
    public let note: String?
    /// 진행 막대 값. 막대가 없는 상태면 nil.
    public let progress: Double?
    /// 남은 시간 어림(초). 전사 중일 때만.
    public let remainingSeconds: TimeInterval?
    public let isFailure: Bool
    /// 실패 줄 아래 작게 보이는 도우미의 마지막 줄.
    public let failureDetail: String?
    public let actions: [Action]

    public init(entry: TranscriptionQueue.Entry, waitingPosition: Int) {
        let percent: (Double) -> Int = { Int((min(max($0, 0), 1) * 100).rounded()) }
        var note: String?
        var progress: Double?
        var remaining: TimeInterval?
        var isFailure = false
        var detail: String?
        switch entry.state {
        case .running(let value):
            status = "전사 중 \(percent(value))%"
            progress = value
            remaining = entry.job.duration * (1 - min(max(value, 0), 1)) * TranscriptionQueue.secondsPerAudioSecond
            actions = [.pause]
        case .stopping(let value):
            status = "멈추는 중…"
            note = "지금 조각까지"
            progress = value
            actions = []
        case .paused(let value):
            status = value > 0 ? "멈춤 · \(percent(value))%까지 함" : "멈춤"
            actions = [.resume, .remove]
        case .waiting:
            status = "대기 중 · \(waitingPosition)번째"
            actions = [.remove]
        case .failed(let message):
            status = "실패: \(message)"
            isFailure = true
            detail = entry.failureDetail?.split(whereSeparator: \.isNewline).last.map(String.init)
            actions = [.retry]
        case .done:
            status = "전사 완료"
            actions = [.open]
        }
        self.note = note
        self.progress = progress
        self.remainingSeconds = remaining
        self.isFailure = isFailure
        self.failureDetail = detail
    }
}
#endif
