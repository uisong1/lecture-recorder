import LectureCore
import SwiftUI

/// 앱 안 LMS 창: 위는 웹, 아래는 "이 영상 가져오기" 줄.
struct LMSBrowserWindow: View {
    static let windowID = "lms"

    let browser: LMSBrowser
    let model: LMSImportModel
    let subjects: SubjectManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Design.Palette.hairline)
            LMSWebView(browser: browser)
                .accessibilityIdentifier("lmsWebView")
            Divider().overlay(Design.Palette.hairline)
            LMSImportBar(model: model, subjects: subjects)
        }
        .frame(minWidth: 900, minHeight: 640)
        .designCanvas()
        .onAppear { browser.loadHomeIfNeeded() }
    }

    private var toolbar: some View {
        HStack(spacing: Design.Spacing.xs) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
                .help("뒤로")
                .accessibilityLabel("뒤로")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
                .help("앞으로")
                .accessibilityLabel("앞으로")
            Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("새로고침")
                .accessibilityLabel("새로고침")
            Button { browser.goHome() } label: { Image(systemName: "house") }
                .help("LMS 첫 화면")
                .accessibilityLabel("LMS 첫 화면")
            Text(browser.currentURL?.host() ?? "")
                .designText(.caption)
                .foregroundStyle(Design.Palette.inkMuted)
                .lineLimit(1)
            Spacer()
            if browser.isLoading { ProgressView().controlSize(.small) }
        }
        .buttonStyle(.textLink)
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
    }
}

/// 영상을 찾으면 강의명·과목·날짜를 확인하고 "이 영상 가져오기"를 누르는 줄.
private struct LMSImportBar: View {
    let model: LMSImportModel
    let subjects: SubjectManager
    @AppStorage(LMSImportModel.keepVideoDefaultsKey) private var keepVideo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            if model.isHalted {
                halted
            } else if model.candidate != nil {
                found
            } else {
                Text("강의 영상을 열면 여기에 \"이 영상 가져오기\"가 나타납니다. 가져온 영상은 개인 복습용이라 공유·업로드되지 않습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                    .accessibilityIdentifier("lmsHint")
            }
            statusLine
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Palette.parchment)
    }

    private var halted: some View {
        HStack(spacing: Design.Spacing.sm) {
            Label("LMS 가져오기를 멈췄습니다. 영상이 암호화되었거나 스트리밍 형식이라 우회하지 않습니다.", systemImage: "exclamationmark.triangle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.danger)
                .accessibilityIdentifier("lmsHalted")
            Spacer()
            Button("다시 시도 허용") { model.resumeAfterHalt() }
                .buttonStyle(.pillSecondary)
                .accessibilityIdentifier("lmsResume")
        }
    }

    private var found: some View {
        HStack(alignment: .center, spacing: Design.Spacing.sm) {
            Image(systemName: "play.rectangle")
                .foregroundStyle(Design.Palette.primary)
            TextField("강의명", text: Binding(get: { model.courseName }, set: { model.editCourseName($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 260)
                .disabled(model.isBusy)
                .accessibilityIdentifier("lmsCourseName")
            Picker("과목", selection: Binding(get: { model.subject }, set: { model.editSubject($0) })) {
                Text("미분류").tag(Subject?.none)
                ForEach(subjects.subjects) { subject in
                    Text(subject.name).tag(Subject?.some(subject))
                }
            }
            .frame(maxWidth: 220)
            .disabled(model.isBusy)
            .accessibilityIdentifier("lmsSubject")
            Toggle("날짜 지정", isOn: Binding(
                get: { model.customDate != nil },
                set: { model.customDate = $0 ? Date() : nil }
            ))
            .disabled(model.isBusy)
            .accessibilityIdentifier("lmsCustomDate")
            if let date = model.customDate {
                DatePicker("수업 날짜", selection: Binding(get: { date }, set: { model.customDate = $0 }))
                    .labelsHidden()
                    .disabled(model.isBusy)
            } else {
                Text("영상이 올라온 날")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            Spacer()
            Button("이 영상 가져오기") { Task { await model.importCurrent() } }
                .buttonStyle(.pill)
                .disabled(!model.canImport)
                .accessibilityIdentifier("lmsImport")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .idle:
            if model.candidate != nil {
                Text(keepVideo ? "소리(m4a)와 영상(mp4)을 함께 보관합니다. 설정 > 녹음 파일에서 바꿀 수 있습니다." : "기본은 소리(m4a)만 저장합니다. 영상도 보관하려면 설정 > 녹음 파일에서 켜세요.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        case .downloading(let fraction):
            HStack(spacing: Design.Spacing.xs) {
                ProgressView(value: fraction)
                    .frame(maxWidth: 240)
                Text("받는 중 \(Int(fraction * 100))%")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
            .accessibilityIdentifier("lmsProgress")
        case .importing:
            HStack(spacing: Design.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("소리를 꺼내 저장하는 중…")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
            }
        case .done(let title):
            Label("녹음 목록에 넣었습니다: \(title)", systemImage: "checkmark.circle")
                .designText(.caption)
                .foregroundStyle(Design.Palette.primary)
                .accessibilityIdentifier("lmsDone")
        case .failed(let message):
            if !model.isHalted {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("lmsFailed")
            }
        }
    }
}
