import LectureCore
import SwiftUI

struct ScheduleSettingsView: View {
    let subjects: SubjectManager
    @Bindable var manager: ScheduleManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("에브리타임 시간표 캡처를 읽어 한 번에 넣을 수 있습니다.")
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.inkMuted)
                Spacer()
                Button("이미지로 가져오기…") { openWindow(id: TimetableImportView.windowID) }
                    .buttonStyle(.pillSecondary)
                    .accessibilityIdentifier("openTimetableImport")
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("과목")
                    Picker("과목", selection: $manager.draftSubject) {
                        Text("선택").tag(Subject?.none)
                        ForEach(subjects.subjects) { subject in
                            Text(subject.name).tag(Subject?.some(subject))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("slotSubject")
                }
                GridRow {
                    Text("요일")
                    Picker("요일", selection: $manager.draftWeekday) {
                        ForEach(Weekday.mondayFirst, id: \.self) { weekday in
                            Text(weekday.shortName).tag(weekday)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("시간")
                    HStack {
                        TimePicker(label: "시작", time: $manager.draftStart)
                        Text("–")
                        TimePicker(label: "종료", time: $manager.draftEnd)
                        Spacer()
                        Button("추가", action: manager.addDraft)
                            .buttonStyle(.pill)
                            .accessibilityIdentifier("addSlot")
                    }
                }
            }

            if let message = manager.errorMessage {
                Text(message)
                    .designText(.caption)
                    .foregroundStyle(Design.Palette.danger)
                    .accessibilityIdentifier("slotError")
            }

            List {
                ForEach(manager.slots) { slot in
                    if let period = slot.period, let subject = slot.subject {
                        HStack {
                            Image(systemName: "circle.fill").foregroundStyle(subject.color.color)
                            Text("\(period.weekday.shortName)  \(period.start.description)–\(period.end.description)")
                                .monospacedDigit()
                            Text(subject.name)
                            Spacer()
                            Button(role: .destructive) {
                                manager.perform { try manager.delete(slot) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("시간표 칸 삭제")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("slot-\(period.weekday.shortName)-\(period.start.description)")
                    }
                }
            }
            .overlay {
                if manager.slots.isEmpty {
                    ContentUnavailableView("시간표가 비어 있습니다", systemImage: "calendar", description: Text("과목마다 수업 요일과 시간을 추가하세요."))
                }
            }
        }
        .padding()
        .designCanvas()
        .onAppear {
            subjects.reload()
            manager.reload()
        }
    }
}
