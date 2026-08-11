import SwiftUI

struct WeekdaySelector: View {
    @Binding var selection: Set<Int>
    private let calendar = Calendar.autoupdatingCurrent

    private var weekdays: [(value: Int, title: String, fullTitle: String)] {
        let short = calendar.veryShortStandaloneWeekdaySymbols
        let full = calendar.weekdaySymbols
        return (0..<7).map { offset in
            let value = ((calendar.firstWeekday - 1 + offset) % 7) + 1
            return (value, short[value - 1], full[value - 1])
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(weekdays, id: \.value) { weekday in
                Button {
                    toggle(weekday.value)
                } label: {
                    Text(weekday.title)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(
                            selection.contains(weekday.value) ? Color.accentColor : Color.primary
                        )
                        .background(
                            selection.contains(weekday.value)
                                ? Color.accentColor.opacity(0.16)
                                : Color.secondary.opacity(0.12),
                            in: Circle()
                        )
                        .overlay {
                            if selection.contains(weekday.value) {
                                Circle().stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.fullTitle)
                .accessibilityAddTraits(selection.contains(weekday.value) ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ weekday: Int) {
        if selection.contains(weekday) {
            guard selection.count > 1 else { return }
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
    }
}
