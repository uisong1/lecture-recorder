import LectureCore
import SwiftUI

struct ScheduleSettingsView: View {
    let subjects: SubjectManager
    @Bindable var manager: ScheduleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            .accessibilityIdentifier("addSlot")
                    }
                }
            }

            if let message = manager.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
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
        .onAppear {
            subjects.reload()
            manager.reload()
        }
    }
}

/// `TimeOfDay`를 시:분 선택 컨트롤로 보여준다.
private struct TimePicker: View {
    let label: String
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker(label, selection: Binding(
            get: { time.date(on: .now, calendar: .current) },
            set: { time = TimeOfDay(date: $0, calendar: .current) }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
    }
}
