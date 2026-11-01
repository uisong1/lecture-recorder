import LectureCore
import SwiftUI

/// 설정 > 일반의 "앱 업데이트" 구역. 상태 표시와 버튼만 있고 판단은 `AppUpdateModel`이 한다.
struct AppUpdateSection: View {
    let model: AppUpdateModel
    let isRecording: Bool

    var body: some View {
        Section {
            HStack {
                Text("현재 빌드 \(model.currentBuild)")
                Spacer()
                statusText
            }
            HStack {
                Button("새 버전 확인") {
                    Task { await model.check(now: Date()) }
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("checkUpdateButton")
                if let release = model.availableRelease {
                    Button("빌드 \(release.build)로 업데이트") {
                        Task { await model.install() }
                    }
                    .buttonStyle(.pill)
                    .disabled(model.isBusy || !model.canInstall)
                    .accessibilityIdentifier("installUpdateButton")
                }
            }
            if isRecording, model.availableRelease != nil {
                Text(AppUpdateModel.recordingMessage)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            if case .failed(let message) = model.state {
                Label(message, systemImage: "exclamationmark.circle")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("updateFailureMessage")
            }
            Text("새 버전은 GitHub에 올라온 앱을 받아 이 앱을 바꿔 끼웁니다. 녹음 파일과 설정은 그대로 남고, 녹음 중에는 업데이트하지 않습니다.")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
        } header: {
            Text("앱 업데이트")
        }
    }

    @ViewBuilder private var statusText: some View {
        switch model.state {
        case .checking: Text("확인하는 중…")
        case .upToDate: Text("최신 버전입니다")
        case .available(let release): Text("새 버전 있음 (빌드 \(release.build))").foregroundStyle(Design.Palette.primary)
        case .downloading: Text("받는 중…")
        case .installing: Text("바꾸는 중… 앱이 곧 다시 열립니다")
        case .idle, .failed: EmptyView()
        }
    }
}
