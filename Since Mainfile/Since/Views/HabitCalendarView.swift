import SwiftData
import SwiftUI

struct HabitCalendarView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var plannerTasks: [PlannerTask]

    @State private var month = Date.now
    @State private var selectedDay: CalendarDaySelection?
    @State private var showsTasksOnly = false
    @State private var selectedHabitIDs: Set<UUID> = []

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    private var displayedHabits: [Habit] {
        guard !showsTasksOnly else { return [] }
        guard !selectedHabitIDs.isEmpty else { return activeHabits }
        return activeHabits.filter { selectedHabitIDs.contains($0.id) }
    }

    private var detailHabitIDs: Set<UUID>? {
        if showsTasksOnly {
            return []
        }
        return selectedHabitIDs.isEmpty ? nil : selectedHabitIDs
    }

    private var filterTitle: String {
        if showsTasksOnly {
            return "Tasks only"
        }
        if selectedHabitIDs.isEmpty {
            return "All activity"
        }
        if selectedHabitIDs.count == 1,
           let habit = activeHabits.first(where: { selectedHabitIDs.contains($0.id) }) {
            return habit.name
        }
        return "\(selectedHabitIDs.count) habits"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                filterMenu
                monthHeader
                weekdayHeader
                monthGrid
                legend
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    withAnimation {
                        month = .now
                    }
                }
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
        }
        .sheet(item: $selectedDay) { selection in
            CalendarDayDetailView(
                initialDate: selection.date,
                habitIDs: detailHabitIDs
            )
        }
        .onChange(of: activeHabits.map(\.id)) { _, activeIDs in
            selectedHabitIDs.formIntersection(Set(activeIDs))
        }
        .task(id: month) {
            guard activeHabits.contains(where: \.isHealthPowered) else { return }
            await healthKitManager.refreshMonth(containing: month)
        }
    }

    private var filterMenu: some View {
        Menu {
            Button {
                showsTasksOnly = false
                selectedHabitIDs.removeAll()
            } label: {
                filterOptionLabel("All activity", isSelected: !showsTasksOnly && selectedHabitIDs.isEmpty)
            }

            Button {
                showsTasksOnly = true
                selectedHabitIDs.removeAll()
            } label: {
                filterOptionLabel("Tasks only", isSelected: showsTasksOnly)
            }

            if !activeHabits.isEmpty {
                Section("Habits") {
                    ForEach(activeHabits) { habit in
                        Button {
                            toggleHabitFilter(habit)
                        } label: {
                            filterOptionLabel(
                                habit.name,
                                systemImage: habit.symbolName,
                                isSelected: !showsTasksOnly
                                    && !selectedHabitIDs.isEmpty
                                    && selectedHabitIDs.contains(habit.id)
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: showsTasksOnly ? "checklist" : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(filterTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityIdentifier("calendar-filter-menu")
    }

    private func filterOptionLabel(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool
    ) -> some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func toggleHabitFilter(_ habit: Habit) {
        if showsTasksOnly || selectedHabitIDs.isEmpty {
            showsTasksOnly = false
            selectedHabitIDs = [habit.id]
        } else if selectedHabitIDs.contains(habit.id) {
            selectedHabitIDs.remove(habit.id)
        } else {
            selectedHabitIDs.insert(habit.id)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                withAnimation {
                    month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(orderedWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthGrid: some View {
        let days = gridDates()
        let presentations = monthPresentations(for: days.compactMap { $0 })
        let showsHabitActivity = !displayedHabits.isEmpty

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date, let presentation = presentations[calendar.startOfDay(for: date)] {
                    Button {
                        selectedDay = CalendarDaySelection(date: date)
                    } label: {
                        CalendarMonthDayCell(
                            date: date,
                            presentation: presentation,
                            showsHabitActivity: showsHabitActivity
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        calendar.isDateInToday(date)
                            ? "calendar-today-cell"
                            : "calendar-day-\(calendar.component(.day, from: date))"
                    )
                    .accessibilityHint("Opens activity details for this day")
                } else {
                    Color.clear
                        .frame(height: 56)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Builds each day's display data once for the visible month. Calendar cells stay
    /// lightweight and no longer repeat task, habit, and event scans while rendering
    /// badges, markers, and accessibility descriptions.
    private func monthPresentations(for dates: [Date]) -> [Date: CalendarDayPresentation] {
        let now = Date.now
        let healthStepTotals = healthKitManager.stepTotals
        let habits = displayedHabits

        return dates.reduce(into: [:]) { result, date in
            let day = calendar.startOfDay(for: date)
            let dayTasks = PlannerTaskManager.dayTasks(
                on: day,
                from: plannerTasks,
                calendar: calendar
            )
            var slipCount = 0
            var markers: [CalendarHabitMarker] = []

            for habit in habits {
                let steps = healthStepTotals[day]
                guard CalendarActivityManager.isHabit(
                    habit,
                    trackedOn: day,
                    healthStepCount: steps,
                    now: now,
                    calendar: calendar
                ) else {
                    continue
                }

                let slips = CalendarActivityManager.slipEvents(
                    for: habit,
                    on: day,
                    calendar: calendar
                )
                slipCount += slips.count

                let healthGoalReached: Bool?
                if habit.isHealthPowered {
                    healthGoalReached = HealthGoalManager.progress(
                        for: habit,
                        on: day,
                        stepCount: steps,
                        calendar: calendar
                    )?.isReached == true
                } else {
                    healthGoalReached = nil
                }

                markers.append(
                    CalendarHabitMarker(
                        id: habit.id,
                        tint: habit.tint.color,
                        hasSlip: !slips.isEmpty,
                        healthGoalReached: healthGoalReached
                    )
                )
            }

            result[day] = CalendarDayPresentation(
                summary: CalendarDaySummary(
                    completedTaskCount: dayTasks.filter(\.isCompleted).count,
                    totalTaskCount: dayTasks.count,
                    trackedHabitCount: markers.count,
                    slipCount: slipCount
                ),
                hasDeadline: dayTasks.contains { $0.reasons.contains(.due) },
                habitMarkers: markers
            )
        }
    }

    private var legend: some View {
        AdaptiveFlowLayout(horizontalSpacing: 14, verticalSpacing: 8) {
            legendItems
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var legendItems: some View {
        Label("Tasks left", systemImage: "number.circle.fill")
        Label("Deadline", systemImage: "flag.fill")
            .foregroundStyle(.orange)
        Label("Tasks done", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        if !displayedHabits.isEmpty {
            Label("Habit activity", systemImage: "circle.fill")
            Label("Slip", systemImage: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func gridDates() -> [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: month),
            let range = calendar.range(of: .day, in: .month, for: month)
        else {
            return []
        }

        let weekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: monthInterval.start)
        }
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
    }
}

private struct CalendarDaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

private struct CalendarDayPresentation {
    let summary: CalendarDaySummary
    let hasDeadline: Bool
    let habitMarkers: [CalendarHabitMarker]
}

private struct CalendarHabitMarker: Identifiable {
    let id: UUID
    let tint: Color
    let hasSlip: Bool
    /// `nil` denotes a manually tracked habit. Health habits store whether the
    /// daily goal was reached so the cell does not need to recalculate it.
    let healthGoalReached: Bool?
}

private struct CalendarMonthDayCell: View {
    let date: Date
    let presentation: CalendarDayPresentation
    let showsHabitActivity: Bool

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)

            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.monospacedDigit().weight(calendar.isDateInToday(date) ? .bold : .regular))
                    .foregroundStyle(isFuture ? .secondary : .primary)

                habitMarkers
                    .frame(height: 10)
            }
            .padding(.top, 3)
        }
        .frame(height: 56)
        .overlay(alignment: .topTrailing) {
            taskBadge
                .padding(3)
        }
        .overlay(alignment: .bottomLeading) {
            if presentation.hasDeadline {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    calendar.isDateInToday(date) ? Color.accentColor : Color.secondary.opacity(0.10),
                    lineWidth: calendar.isDateInToday(date) ? 2 : 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var taskBadge: some View {
        if presentation.summary.areAllTasksComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        } else if presentation.summary.incompleteTaskCount > 0 {
            Text("\(presentation.summary.incompleteTaskCount)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var habitMarkers: some View {
        if !presentation.habitMarkers.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(presentation.habitMarkers.prefix(3))) { marker in
                    habitMarker(for: marker)
                }

                if presentation.habitMarkers.count > 3 {
                    Text("+\(presentation.habitMarkers.count - 3)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isFuture: Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: .now)
    }

    @ViewBuilder
    private func habitMarker(for marker: CalendarHabitMarker) -> some View {
        if let healthGoalReached = marker.healthGoalReached {
            Image(systemName: healthGoalReached ? "circle.fill" : "circle.lefthalf.filled")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(marker.tint)
        } else if !marker.hasSlip {
            Circle()
                .fill(marker.tint)
                .frame(width: 7, height: 7)
        } else {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private var accessibilityText: String {
        var details = [date.formatted(date: .complete, time: .omitted)]

        if presentation.summary.totalTaskCount > 0 {
            details.append(
                "\(presentation.summary.completedTaskCount) of \(presentation.summary.totalTaskCount) tasks completed"
            )
        } else {
            details.append("no tasks")
        }

        if presentation.hasDeadline {
            details.append("deadline")
        }

        if showsHabitActivity {
            details.append("\(presentation.summary.trackedHabitCount) habit activities")
        }
        if presentation.summary.slipCount > 0 {
            details.append("\(presentation.summary.slipCount) slips recorded")
        }

        return details.joined(separator: ", ")
    }
}
