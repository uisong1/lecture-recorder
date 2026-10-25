import LectureCore
import SwiftUI

/// `TimeOfDay`를 시:분 선택 컨트롤로 보여준다.
struct TimePicker: View {
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
