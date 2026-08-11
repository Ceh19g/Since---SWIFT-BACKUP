import SwiftData
import SwiftUI

struct CalendarDayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @Query private var plannerTasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    let habitIDs: Set<UUID>?

    @State private var date: Date
    @State private var isPresentingNewTask = false
    @State private var editingTask: PlannerTask?
    @State private var taskPendingDeletion: PlannerDayTask?
    @State private var recentlyDeletedTask: CalendarPlannerTaskSnapshot?
    @State private var persistenceIssue: PersistenceIssue?

    private let calendar = Calendar.autoupdatingCurrent

    init(initialDate: Date, habitIDs: Set<UUID>?) {
        self.habitIDs = habitIDs
        _date = State(initialValue: Calendar.autoupdatingCurrent.startOfDay(for: initialDate))
    }

    private var dayTasks: [PlannerDayTask] {
        PlannerTaskManager.dayTasks(on: date, from: plannerTasks, calendar: calendar)
    }

    private var overdueTasks: [PlannerDayTask] {
        PlannerTaskManager.overdue(before: date, from: plannerTasks, calendar: calendar).map {
            PlannerDayTask(task: $0, date: date, reasons: [.due], session: nil, isCompleted: false)
        }
    }

    private var unfinishedTasks: [PlannerDayTask] {
        PlannerTaskManager.unfinished(before: date, from: plannerTasks, calendar: calendar).map {
            PlannerDayTask(task: $0, date: date, reasons: [.planned], session: nil, isCompleted: false)
        }
    }

    private var incompleteDayTasks: [PlannerDayTask] { dayTasks.filter { !$0.isCompleted } }
    private var completedDayTasks: [PlannerDayTask] { dayTasks.filter(\.isCompleted) }
    private var dueOnlyTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.isDue && !$0.isPlanned }
    }
    private var anytimeTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.session?.timeMode == .anytime }
    }
    private var morningTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.session?.timeMode == .daySection && $0.session?.daySection == .morning }
    }
    private var exactTimeTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.session?.timeMode == .exactTime }
    }
    private var afternoonTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.session?.timeMode == .daySection && $0.session?.daySection == .afternoon }
    }
    private var eveningTasks: [PlannerDayTask] {
        incompleteDayTasks.filter { $0.session?.timeMode == .daySection && $0.session?.daySection == .evening }
    }

    private var activeFilteredHabits: [Habit] {
        let active = habits.filter { !$0.isArchived }
        guard let habitIDs else { return active }
        return active.filter { habitIDs.contains($0.id) }
    }

    private var dayHabits: [Habit] {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        return activeFilteredHabits.filter { habit in
            if habit.type == .countdown {
                return calendar.isDate(habit.startAt, inSameDayAs: date)
            }
            return habit.startAt < nextDay
        }
    }

    private var progress: PlannerProgress {
        PlannerTaskManager.progress(for: dayTasks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    dateNavigator
                    daySummary
                    tasksSection

                    if habitIDs?.isEmpty != true {
                        habitsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewTask) {
                PlannerTaskEditorView(scheduledDay: date)
            }
            .sheet(item: $editingTask) { task in
                PlannerTaskEditorView(task: task, scheduledDay: task.scheduledDay)
            }
            .confirmationDialog(
                "Delete \(taskPendingDeletion?.task.title ?? "task")?",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {
                    taskPendingDeletion = nil
                }
                deletionActions
            } message: {
                Text(deletionMessage)
            }
            .persistenceIssueAlert($persistenceIssue)
            .safeAreaInset(edge: .bottom) {
                if recentlyDeletedTask != nil {
                    undoBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("calendar-day-detail")
        .task(id: date) {
            guard dayHabits.contains(where: \.isHealthPowered) else { return }
            await healthKitManager.refreshDay(containing: date)
        }
    }

    private var dateNavigator: some View {
        HStack {
            Button {
                moveDisplayedDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(date.formatted(.dateTime.month(.wide).day().year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            Spacer()

            Button {
                moveDisplayedDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next day")
        }
        .buttonStyle(.plain)
    }

    private var daySummary: some View {
        HStack(spacing: 12) {
            summaryMetric(
                value: "\(progress.completed)/\(progress.total)",
                label: "Tasks done",
                symbol: progress.total > 0 && progress.completed == progress.total
                    ? "checkmark.circle.fill"
                    : "checklist",
                tint: progress.total > 0 && progress.completed == progress.total ? .green : .accentColor
            )

            if habitIDs?.isEmpty != true {
                let slipCount = dayHabits.reduce(into: 0) { count, habit in
                    count += CalendarActivityManager.slipEvents(
                        for: habit,
                        on: date,
                        calendar: calendar
                    ).count
                }

                summaryMetric(
                    value: "\(dayHabits.count)",
                    label: dayHabits.count == 1 ? "Habit shown" : "Habits shown",
                    symbol: slipCount > 0 ? "arrow.counterclockwise.circle.fill" : "circle.grid.2x2.fill",
                    tint: slipCount > 0 ? .orange : .accentColor
                )
            }
        }
    }

    private func summaryMetric(
        value: String,
        label: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks")
                    .font(.headline)

                Spacer()

                Button {
                    isPresentingNewTask = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("calendar-add-task-button")
            }

            if dayTasks.isEmpty && overdueTasks.isEmpty && unfinishedTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Nothing scheduled")
                        .font(.subheadline.weight(.semibold))
                    Text("Add a task and it will also appear in your planner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                dayTaskSection("Overdue", symbol: "exclamationmark.circle.fill", tint: .red, tasks: overdueTasks)
                dayTaskSection("Unfinished", symbol: "arrow.uturn.forward.circle", tint: .orange, tasks: unfinishedTasks)
                dayTaskSection(
                    calendar.isDateInToday(date) ? "Due Today" : "Due",
                    symbol: "flag.fill",
                    tint: .orange,
                    tasks: dueOnlyTasks
                )
                dayTaskSection("Anytime", symbol: "circle.dotted", tint: .secondary, tasks: anytimeTasks)
                dayTaskSection("Morning", symbol: "sunrise.fill", tint: .orange, tasks: morningTasks)
                dayTaskSection("Timeline", symbol: "clock.fill", tint: .indigo, tasks: exactTimeTasks)
                dayTaskSection("Afternoon", symbol: "sun.max.fill", tint: .orange, tasks: afternoonTasks)
                dayTaskSection("Evening", symbol: "moon.stars.fill", tint: .indigo, tasks: eveningTasks)
                dayTaskSection("Completed", symbol: "checkmark.circle.fill", tint: .green, tasks: completedDayTasks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dayTaskSection(
        _ title: String,
        symbol: String,
        tint: Color,
        tasks: [PlannerDayTask]
    ) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)

                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, entry in
                        CalendarPlannerTaskRow(
                            entry: entry,
                            habit: habits.first(where: { $0.id == entry.task.habitID }),
                            onToggle: { toggleCompletion(entry) },
                            onEdit: { editingTask = entry.task },
                            onMoveToPreviousDay: { moveTask(entry.task, from: date, by: -1) },
                            onMoveToNextDay: { moveTask(entry.task, from: date, by: 1) },
                            onDelete: { taskPendingDeletion = entry }
                        )

                        if index < tasks.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Habit activity")
                .font(.headline)

            if dayHabits.isEmpty {
                Text("No active habits for this date and filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayHabits.enumerated()), id: \.element.id) { index, habit in
                        NavigationLink {
                            HabitDetailView(habit: habit)
                        } label: {
                            CalendarHabitActivityRow(
                                habit: habit,
                                date: date,
                                healthStepCount: healthKitManager.steps(on: date)
                            )
                        }
                        .buttonStyle(.plain)

                        if index < dayHabits.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var undoBar: some View {
        HStack(spacing: 12) {
            Text("Task deleted")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button("Undo") {
                undoTaskDeletion()
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var navigationTitle: String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func moveDisplayedDay(by value: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: value, to: date) else { return }
        withAnimation {
            date = calendar.startOfDay(for: newDate)
        }
    }

    private func toggleCompletion(_ entry: PlannerDayTask) {
        PlannerTaskManager.setCompletion(
            !entry.isCompleted,
            for: entry.task,
            on: date,
            calendar: calendar
        )
        saveChanges(title: "Task Could Not Be Updated")
    }

    private func moveTask(_ task: PlannerTask, from sourceDate: Date, by dayOffset: Int) {
        guard let destination = calendar.date(byAdding: .day, value: dayOffset, to: sourceDate) else {
            return
        }

        let destinationDay = calendar.startOfDay(for: destination)
        if task.scheduleKind == .multipleDays {
            var sessions = workSessions(for: task)
            if let index = sessions.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: sourceDate) }) {
                if let destinationIndex = sessions.firstIndex(where: {
                    calendar.isDate($0.day, inSameDayAs: destinationDay)
                }) {
                    sessions[destinationIndex] = sessions[destinationIndex].moved(
                        to: calendar.startOfDay(for: sourceDate),
                        calendar: calendar
                    )
                }
                sessions[index] = sessions[index].moved(to: destinationDay, calendar: calendar)
                sessions.sort { $0.day < $1.day }
                task.customWorkSessionsData = PlannerTaskManager.encodedSessions(sessions)
                task.scheduledDay = sessions.first?.day ?? destinationDay
                task.scheduleEndDate = sessions.last?.day ?? destinationDay
            }
        } else if task.scheduleKind == .repeating {
            var excluded = PlannerTaskManager.decodedDays(task.excludedOccurrenceDaysData, calendar: calendar)
            excluded.insert(calendar.startOfDay(for: sourceDate))
            task.excludedOccurrenceDaysData = PlannerTaskManager.encodedDays(excluded, calendar: calendar)
            let detached = PlannerTask(
                title: task.title,
                taskNotes: task.taskNotes,
                scheduledDay: destinationDay,
                dueDate: nil,
                timeMode: task.timeMode,
                scheduledTime: task.scheduledTime.map { time in
                    let components = calendar.dateComponents([.hour, .minute], from: time)
                    return calendar.date(
                        bySettingHour: components.hour ?? 0,
                        minute: components.minute ?? 0,
                        second: 0,
                        of: destinationDay
                    ) ?? destinationDay
                },
                daySection: task.daySection,
                scheduleKind: .once,
                plannedDurationMinutes: task.plannedDurationMinutes,
                position: PlannerTaskManager.nextPosition(for: plannerTasks, on: destinationDay),
                priority: task.priority,
                status: task.status,
                habitID: task.habitID
            )
            modelContext.insert(detached)
        } else {
            task.scheduledDay = destinationDay
        }
        task.position = PlannerTaskManager.nextPosition(for: plannerTasks, on: destinationDay)

        if task.scheduleKind == .once,
           task.timeMode == .exactTime,
           let scheduledTime = task.scheduledTime {
            let time = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
            task.scheduledTime = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: destinationDay
            )
        }

        task.updatedAt = .now
        saveChanges(title: "Task Could Not Be Moved")
    }

    @ViewBuilder
    private var deletionActions: some View {
        if let entry = taskPendingDeletion {
            switch entry.task.scheduleKind {
            case .repeating:
                Button("Delete This Occurrence", role: .destructive) {
                    deleteOccurrence(entry)
                }
                Button("Delete This and Future Occurrences", role: .destructive) {
                    deleteThisAndFuture(entry)
                }
                Button("Delete Entire Repeating Task", role: .destructive) {
                    deleteEntireTask(entry.task)
                }
                .accessibilityIdentifier("calendar-confirm-delete-task-button")
            case .multipleDays:
                Button("Delete This Work Session", role: .destructive) {
                    deleteOccurrence(entry)
                }
                Button("Delete This and Future Sessions", role: .destructive) {
                    deleteThisAndFuture(entry)
                }
                Button("Delete Entire Task", role: .destructive) {
                    deleteEntireTask(entry.task)
                }
                .accessibilityIdentifier("calendar-confirm-delete-task-button")
            case .none, .once:
                Button("Delete Task", role: .destructive) {
                    deleteEntireTask(entry.task)
                }
                .accessibilityIdentifier("calendar-confirm-delete-task-button")
            }
        }
    }

    private var deletionMessage: String {
        switch taskPendingDeletion?.task.scheduleKind {
        case .repeating:
            "Choose whether to remove this date, this date forward, or the entire repeating task."
        case .multipleDays:
            "This is one work session within a multi-day task."
        case .some(.none), .some(.once), nil:
            "Deleting the entire task can be undone for five seconds."
        }
    }

    private func deleteOccurrence(_ entry: PlannerDayTask) {
        let task = entry.task
        switch task.scheduleKind {
        case .repeating:
            var excluded = PlannerTaskManager.decodedDays(
                task.excludedOccurrenceDaysData,
                calendar: calendar
            )
            excluded.insert(calendar.startOfDay(for: entry.date))
            task.excludedOccurrenceDaysData = PlannerTaskManager.encodedDays(excluded, calendar: calendar)
            task.updatedAt = .now
            taskPendingDeletion = nil
            saveChanges(title: "Occurrence Could Not Be Deleted")
        case .multipleDays:
            let remaining = workSessions(for: task).filter {
                !calendar.isDate($0.day, inSameDayAs: entry.date)
            }
            taskPendingDeletion = nil
            if remaining.isEmpty {
                deleteEntireTask(task)
            } else {
                apply(remaining, to: task)
                saveChanges(title: "Work Session Could Not Be Deleted")
            }
        case .none, .once:
            taskPendingDeletion = nil
            deleteEntireTask(task)
        }
    }

    private func deleteThisAndFuture(_ entry: PlannerDayTask) {
        let task = entry.task
        let selectedDay = calendar.startOfDay(for: entry.date)
        taskPendingDeletion = nil

        switch task.scheduleKind {
        case .repeating:
            let startDay = calendar.startOfDay(for: task.scheduledDay)
            guard selectedDay > startDay,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: selectedDay) else {
                deleteEntireTask(task)
                return
            }
            task.repeatEndMode = .onDate
            task.repeatEndDate = previousDay
            task.repeatCount = nil
            task.updatedAt = .now
            saveChanges(title: "Repeating Task Could Not Be Updated")
        case .multipleDays:
            let remaining = workSessions(for: task).filter {
                calendar.startOfDay(for: $0.day) < selectedDay
            }
            if remaining.isEmpty {
                deleteEntireTask(task)
            } else {
                apply(remaining, to: task)
                saveChanges(title: "Multi-Day Task Could Not Be Updated")
            }
        case .none, .once:
            deleteEntireTask(task)
        }
    }

    private func workSessions(for task: PlannerTask) -> [PlannerWorkSession] {
        let stored = PlannerTaskManager.decodedSessions(task.customWorkSessionsData)
        if !stored.isEmpty { return stored.sorted { $0.day < $1.day } }

        let start = calendar.startOfDay(for: task.scheduledDay)
        let end = calendar.startOfDay(for: task.scheduleEndDate ?? task.scheduledDay)
        var sessions: [PlannerWorkSession] = []
        var cursor = start
        while cursor <= end {
            if let session = PlannerTaskManager.session(for: task, on: cursor, calendar: calendar) {
                sessions.append(session)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return sessions
    }

    private func apply(_ sessions: [PlannerWorkSession], to task: PlannerTask) {
        let ordered = sessions.sorted { $0.day < $1.day }
        task.customWorkSessionsData = PlannerTaskManager.encodedSessions(ordered)
        task.scheduledDay = ordered.first?.day ?? task.scheduledDay
        task.scheduleEndDate = ordered.last?.day ?? task.scheduleEndDate
        task.updatedAt = .now
    }

    private func deleteEntireTask(_ task: PlannerTask) {
        let snapshot = CalendarPlannerTaskSnapshot(task: task)
        modelContext.delete(task)
        self.taskPendingDeletion = nil

        do {
            try modelContext.save()
            withAnimation {
                recentlyDeletedTask = snapshot
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard recentlyDeletedTask?.id == snapshot.id else { return }
                withAnimation {
                    recentlyDeletedTask = nil
                }
            }
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Task Could Not Be Deleted", error: error)
        }
    }

    private func undoTaskDeletion() {
        guard let snapshot = recentlyDeletedTask else { return }
        modelContext.insert(snapshot.makeTask())

        do {
            try modelContext.save()
            withAnimation {
                recentlyDeletedTask = nil
            }
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Task Could Not Be Restored", error: error)
        }
    }

    private func saveChanges(title: String) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: title, error: error)
        }
    }
}

private struct CalendarPlannerTaskRow: View {
    let entry: PlannerDayTask
    let habit: Habit?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMoveToPreviousDay: () -> Void
    let onMoveToNextDay: () -> Void
    let onDelete: () -> Void

    private var task: PlannerTask { entry.task }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.isCompleted ? .teal : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar-task-toggle-\(task.id)")
            .accessibilityLabel(entry.isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.body.weight(task.priority == .important ? .semibold : .regular))
                            .strikethrough(entry.isCompleted)
                            .foregroundStyle(entry.isCompleted ? .secondary : .primary)

                        if task.priority == .important {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Important")
                        }
                    }

                    HStack(spacing: 8) {
                        Label(timeDescription, systemImage: timeSymbol)

                        if entry.isDue {
                            Label(dueDescription, systemImage: "flag.fill")
                                .foregroundStyle(.orange)
                        }

                        if let habit {
                            Label(
                                habit.isArchived ? "\(habit.name) — Archived" : habit.name,
                                systemImage: habit.symbolName
                            )
                            .foregroundStyle(habit.tint.color)
                        } else if task.habitID != nil {
                            Label("Habit removed", systemImage: "link.badge.plus")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !task.taskNotes.isEmpty {
                        Text(task.taskNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(action: onMoveToPreviousDay) {
                    Label("Move to Previous Day", systemImage: "arrow.left")
                }
                Button(action: onMoveToNextDay) {
                    Label("Move to Next Day", systemImage: "arrow.right")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(task.title)")
        }
        .padding(.horizontal, 8)
        .accessibilityAction(named: entry.isCompleted ? "Mark incomplete" : "Complete") {
            onToggle()
        }
        .accessibilityAction(named: "Edit") {
            onEdit()
        }
        .accessibilityAction(named: "Move to Previous Day") {
            onMoveToPreviousDay()
        }
        .accessibilityAction(named: "Move to Next Day") {
            onMoveToNextDay()
        }
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
    }

    private var timeDescription: String {
        guard let session = entry.session else {
            return entry.isDue ? "Deadline" : "Unscheduled"
        }
        switch session.timeMode {
        case .anytime:
            return "Anytime"
        case .daySection:
            return session.daySection?.title ?? "Anytime"
        case .exactTime:
            guard let start = session.startTime else { return "Exact time" }
            guard let duration = session.durationMinutes,
                  let end = Calendar.current.date(byAdding: .minute, value: duration, to: start) else {
                return start.formatted(date: .omitted, time: .shortened)
            }
            return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var timeSymbol: String {
        guard let session = entry.session else { return entry.isDue ? "flag" : "calendar" }
        return switch session.timeMode {
        case .anytime: "calendar"
        case .daySection: session.daySection?.symbolName ?? "calendar"
        case .exactTime: "clock"
        }
    }

    private var dueDescription: String {
        if let dueTime = task.dueTime {
            return "Due \(dueTime.formatted(date: .omitted, time: .shortened))"
        }
        return "Due today"
    }
}

private struct CalendarHabitActivityRow: View {
    let habit: Habit
    let date: Date
    let healthStepCount: Int?

    private let calendar = Calendar.autoupdatingCurrent

    private var slips: [HabitEvent] {
        CalendarActivityManager.slipEvents(for: habit, on: date, calendar: calendar)
    }

    private var hasRecordedActivity: Bool {
        if habit.isHealthPowered {
            return healthStepCount != nil
        }
        return HabitTrackingManager.hasCalendarActivity(
            habit,
            on: date,
            calendar: calendar
        )
    }

    private var activityTint: Color {
        if !slips.isEmpty {
            return .orange
        }
        return hasRecordedActivity ? habit.tint.color : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.symbolName)
                .foregroundStyle(activityTint)
                .frame(width: 36, height: 36)
                .background(
                    activityTint.opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(slips.isEmpty ? Color.secondary : Color.orange)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var statusDescription: String {
        if habit.isHealthPowered {
            guard let progress = HealthGoalManager.progress(
                for: habit,
                on: date,
                stepCount: healthStepCount,
                calendar: calendar
            ) else {
                return "No step goal for this date"
            }
            guard progress.isScheduled else { return "Rest day" }
            guard let value = progress.value else { return "No step data available" }
            return progress.isReached
                ? "\(value.formatted()) of \(progress.target.formatted()) · Goal reached"
                : "\(value.formatted()) of \(progress.target.formatted()) steps"
        }
        switch habit.type {
        case .abstinence:
            if slips.count == 1, let slip = slips.first {
                return [
                    "Slip at \(slip.occurredAt.formatted(date: .omitted, time: .shortened))",
                    slip.formattedMeasurement
                ].compactMap { $0 }.joined(separator: " · ")
            }
            if slips.count > 1 {
                return [
                    "\(slips.count) slips recorded",
                    HabitMeasurementManager.summary(for: slips)
                ].compactMap { $0 }.joined(separator: " · ")
            }
            return isFuture ? "Upcoming tracked day" : "Tracked day"
        case .positiveStreak:
            let completions = HabitTrackingManager.completionEvents(for: habit, on: date, calendar: calendar)
            if !completions.isEmpty {
                return ["Completed", HabitMeasurementManager.summary(for: completions)]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
            return isFuture ? "Upcoming day" : "Not completed"
        case .event:
            let occurrences = HabitTrackingManager.occurrenceEvents(
                for: habit,
                on: date,
                calendar: calendar
            )
            if occurrences.count == 1, let occurrence = occurrences.first {
                return [
                    "Logged at \(occurrence.occurredAt.formatted(date: .omitted, time: .shortened))",
                    occurrence.formattedMeasurement
                ].compactMap { $0 }.joined(separator: " · ")
            }
            if occurrences.isEmpty { return "No occurrence logged" }
            return [
                "\(occurrences.count) occurrences logged",
                HabitMeasurementManager.summary(for: occurrences)
            ].compactMap { $0 }.joined(separator: " · ")
        case .sinceDate:
            return isFuture ? "Before meaningful date" : "Tracked day"
        case .countdown:
            return date < calendar.startOfDay(for: .now) ? "Target date reached" : "Target date"
        case .frequency, .count, .duration:
            return isFuture ? "Upcoming tracked day" : "Tracked day"
        }
    }

    private var isFuture: Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: .now)
    }
}

private struct CalendarPlannerTaskSnapshot {
    let id: UUID
    let title: String
    let taskNotes: String
    let scheduledDay: Date
    let dueDate: Date?
    let dueTime: Date?
    let timeMode: PlannerTimeMode
    let scheduledTime: Date?
    let daySection: PlannerDaySection?
    let scheduleKind: PlannerScheduleKind
    let scheduleEndDate: Date?
    let scheduleWeekdays: Set<Int>
    let plannedDurationMinutes: Int?
    let customWorkSessionsData: Data?
    let repeatFrequency: PlannerRepeatFrequency
    let repeatInterval: Int
    let repeatEndMode: PlannerRepeatEndMode
    let repeatEndDate: Date?
    let repeatCount: Int?
    let completedOccurrenceDaysData: Data?
    let excludedOccurrenceDaysData: Data?
    let isCompleted: Bool
    let completedAt: Date?
    let position: Int
    let priority: PlannerTaskPriority
    let status: PlannerTaskStatus
    let habitID: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(task: PlannerTask) {
        id = task.id
        title = task.title
        taskNotes = task.taskNotes
        scheduledDay = task.scheduledDay
        dueDate = task.dueDate
        dueTime = task.dueTime
        timeMode = task.timeMode
        scheduledTime = task.scheduledTime
        daySection = task.daySection
        scheduleKind = task.scheduleKind
        scheduleEndDate = task.scheduleEndDate
        scheduleWeekdays = PlannerTaskManager.decodedWeekdays(task.scheduleWeekdaysRawValue)
        plannedDurationMinutes = task.plannedDurationMinutes
        customWorkSessionsData = task.customWorkSessionsData
        repeatFrequency = task.repeatFrequency
        repeatInterval = task.repeatInterval ?? 1
        repeatEndMode = task.repeatEndMode
        repeatEndDate = task.repeatEndDate
        repeatCount = task.repeatCount
        completedOccurrenceDaysData = task.completedOccurrenceDaysData
        excludedOccurrenceDaysData = task.excludedOccurrenceDaysData
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        position = task.position
        priority = task.priority
        status = task.status
        habitID = task.habitID
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    func makeTask() -> PlannerTask {
        PlannerTask(
            id: id,
            title: title,
            taskNotes: taskNotes,
            scheduledDay: scheduledDay,
            dueDate: dueDate,
            dueTime: dueTime,
            timeMode: timeMode,
            scheduledTime: scheduledTime,
            daySection: daySection,
            scheduleKind: scheduleKind,
            scheduleEndDate: scheduleEndDate,
            scheduleWeekdays: scheduleWeekdays,
            plannedDurationMinutes: plannedDurationMinutes,
            customWorkSessionsData: customWorkSessionsData,
            repeatFrequency: repeatFrequency,
            repeatInterval: repeatInterval,
            repeatEndMode: repeatEndMode,
            repeatEndDate: repeatEndDate,
            repeatCount: repeatCount,
            completedOccurrenceDaysData: completedOccurrenceDaysData,
            excludedOccurrenceDaysData: excludedOccurrenceDaysData,
            isCompleted: isCompleted,
            completedAt: completedAt,
            position: position,
            priority: priority,
            status: status,
            habitID: habitID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
