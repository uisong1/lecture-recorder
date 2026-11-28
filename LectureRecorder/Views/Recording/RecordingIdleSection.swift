import AppKit
import LectureCore
import SwiftUI

/// 녹음 전에 보이는 구역: 마이크 확인, 이어 듣기, 첫 안내, 시작 버튼(또는 권한 안내), 멈춤·중단 안내.
struct RecordingIdleSection: View {
    let recording: RecordingController
    let playback: PlaybackController
    let manager: RecordingManager
    let library: RecordingLibrary
    let showsFirstRunGuide: Bool

    var body: some View {
        // 시안 01: 과목 고르기를 대기 카드 첫 줄로 둔다.
        HStack {
            Text("과목")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
            Spacer()
            // 메뉴 선택 칸은 폭을 고정해야 처음 그릴 때 "자…"처럼 잘리지 않는다 (fixedSize는 항목이 채워지기 전 폭으로 굳는다).
            Picker("과목", selection: Bindable(recording).subjectChoice) {
                Text("자동 (시간표)").tag(SubjectChoice.automatic)
                ForEach(recording.availableSubjects()) { subject in
                    Text(subject.name).tag(SubjectChoice.subject(subject.persistentModelID))
                }
                Text("미분류").tag(SubjectChoice.unclassified)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 200)
            .accessibilityIdentifier("subjectChoice")
        }
        Rectangle().fill(Design.Palette.fill).frame(height: 1)

        if !recording.isPermissionDenied {
            micCheck
        }

        if let resume = library.resumeCandidate(using: manager),
           !(playback.current === resume && playback.isPlaying) {
            HStack(spacing: Design.Spacing.sm) {
                Label(ResumeListening.lineText(for: resume), systemImage: "headphones")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("resumeListeningLine")
                Button("이어 듣기") {
                    playback.select(resume)
                    playback.play()
                }
                .buttonStyle(.pillSecondary)
                .accessibilityIdentifier("resumeListening")
            }
        }

        if showsFirstRunGuide {
            VStack(spacing: Design.Spacing.sm) {
                Text(SubjectManager.firstRunGuideText)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("firstRunGuide")
                SettingsLink {
                    Text("과목과 시간표 설정 열기")
                }
                .buttonStyle(.pill)
                .accessibilityIdentifier("firstRunOpenSettings")
            }
        }

        if let advice = recording.preRecordingAdvice {
            Label(advice, systemImage: "battery.100percent.bolt")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .accessibilityIdentifier("chargeAdvice")
        }

        if recording.isPermissionDenied {
            VStack(spacing: Design.Spacing.xs) {
                Label("마이크 권한이 꺼져 있어 녹음할 수 없습니다.", systemImage: "mic.slash")
                    .designText(.bodyStrong)
                    .accessibilityIdentifier("microphoneDenied")
                Text("시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 LectureRecorder를 켜 주세요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                Button("시스템 설정 열기") {
                    if let url = Self.microphoneSettingsURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.pill)
                .accessibilityIdentifier("openSystemSettings")
            }
        }

        RecordingNoticeLines(notices: RecordingScreenNotices(
            isRecording: false,
            isPaused: false,
            stallResumeNotice: nil,
            storageWarning: nil,
            batteryWarning: nil,
            inputDeviceWarning: recording.inputDeviceWarning,
            isInputSilent: false
        ))

        if let notice = recording.recorderStallNotice {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .designText(.bodyStrong)
                .foregroundStyle(Design.Palette.danger)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("recorderStallNotice")
        }

        if let notice = recording.interruptionNotice {
            Label(notice, systemImage: "moon.zzz")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .accessibilityIdentifier("interruptionNotice")
        }
    }

    private var micCheck: some View {
        VStack(spacing: Design.Spacing.xs) {
            HStack {
                Label("마이크: \(recording.inputDeviceName ?? "시스템 기본")", systemImage: "mic")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("inputDevice")
                Spacer()
                Button(recording.isPreviewing ? "확인 중…" : "마이크 확인") {
                    Task { await recording.startPreview() }
                }
                .buttonStyle(.pillSecondaryCompact)
                .disabled(recording.isPreviewing)
                .accessibilityIdentifier("checkMicrophone")
            }
            if recording.isPreviewing {
                InputLevelBar(level: recording.previewLevel)
                    .accessibilityIdentifier("previewLevel")
            }
            switch recording.previewOutcome {
            case .heard:
                Label("소리가 잘 들어옵니다", systemImage: "checkmark.circle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("previewHeard")
            case .quiet:
                Label("소리가 거의 안 들려요. 마이크 위치나 입력 장치를 확인해 주세요.", systemImage: "mic.slash")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("previewSilenceHint")
            case nil:
                EmptyView()
            }
        }
    }

    private static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
}
