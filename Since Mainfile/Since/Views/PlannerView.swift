import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tasks: [PlannerTask]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    @State private var selection: PlannerSmartList = .inbox
    @State private var quickTaskTitle = ""
    @State private var editingTask: PlannerTask?
    @State private var taskPendingDeletion: PlannerTask?
    @State private var isPresentingNewTask = false
    @State private var recentlyDeletedTask: PlannerDeletedTaskSnapshot?
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isQuickTaskFocused: Bool

    private let calendar = Calendar.autoupdatingCurrent

    private var displayedTasks: [PlannerTask] {
        switch selection {
        case .inbox:
            return PlannerTaskManager.inbox(from: tasks)
        case .today:
            let overdueIDs = Set(
                PlannerTaskManager.overdue(before: .now, from: tasks, calendar: calendar).map(\.id)
            )
            return PlannerTaskManager.tasks(on: .now, from: tasks, calendar: calendar)
                .filter { !overdueIDs.contains($0.id) }
        case .overdue:
            return PlannerTaskManager.overdue(before: .now, from: tasks, calendar: calendar)
        case .upcoming:
            return PlannerTaskManager.upcoming(after: .now, from: tasks, calendar: calendar)
        case .waiting:
            return PlannerTaskManager.waiting(from: tasks)
        case .completed:
            return PlannerTaskManager.completed(from: tasks)
        }
    }

    private var overdueTasks: [PlannerTask] {
        guard selection == .today else { return [] }
        return PlannerTaskManager.overdue(before: .now, from: tasks, calendar: calendar)
    }

    private var unfinishedTasks: [PlannerTask] {
        guard selection == .today else { return [] }
        return PlannerTaskManager.unfinished(before: .now, from: tasks, calendar: calendar)
    }

    var body: some View {
        List {
            Section {
                smartListPicker
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if selection == .inbox {
                Section {
                    quickCapture
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    if displayedTasks.isEmpty {
                        Text("Capture it now; organize it when you are ready.")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }

            if !overdueTasks.isEmpty {
                taskSection(
                    title: "Overdue",
                    symbol: "exclamationmark.circle",
                    tasks: overdueTasks,
                    tint: .orange
                )
            }

            if !unfinishedTasks.isEmpty {
                taskSection(
                    title: "Unfinished",
                    symbol: "arrow.uturn.forward.circle",
                    tasks: unfinishedTasks,
                    tint: .orange
                )
            }

            if displayedTasks.isEmpty && overdueTasks.isEmpty && unfinishedTasks.isEmpty {
                Section {
                    plannerEmptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                taskSection(
                    title: selection.sectionTitle,
                    symbol: selection.symbolName,
                    tasks: displayedTasks,
                    tint: selection.tint
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isQuickTaskFocused = false
                    isPresentingNewTask = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("planner-add-task-button")
                .accessibilityLabel("Add a task")
            }
        }
        .sheet(isPresented: $isPresentingNewTask) {
            PlannerTaskEditorView(
                scheduledDay: selection.newTaskDay,
                initialStatus: selection.newTaskStatus
            )
        }
        .sheet(item: $editingTask) { task in
            PlannerTaskEditorView(task: task, scheduledDay: task.scheduledDay)
        }
        .alert(
            "Delete \(taskPendingDeletion?.title ?? "task")?",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
            Button("Delete Task", role: .destructive) {
                deletePendingTask()
            }
            .accessibilityIdentifier("confirm-delete-planner-task-button")
        } message: {
            Text("This removes the task from your planner without changing any habit history.")
        }
        .safeAreaInset(edge: .bottom) {
            if recentlyDeletedTask != nil {
                HStack {
                    Text("Task deleted")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Undo", action: undoTaskDeletion)
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .persistenceIssueAlert($persistenceIssue)
    }

    private var smartListPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(primarySmartLists) { list in
                    smartListButton(list)
                }

                Menu {
                    Button {
                        selectSmartList(.waiting)
                    } label: {
                        Label("Waiting", systemImage: PlannerSmartList.waiting.symbolName)
                    }
                    .accessibilityIdentifier("planner-filter-waiting")

                    Button {
                        selectSmartList(.completed)
                    } label: {
                        Label("Completed", systemImage: PlannerSmartList.completed.symbolName)
                    }
                    .accessibilityIdentifier("planner-filter-completed")
                } label: {
                    let overflow = overflowSelection
                    Group {
                        if let overflow {
                            Text(overflow.title)
                        } else {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(overflow == nil ? Color.primary : Color.indigo)
                    .padding(.horizontal, overflow == nil ? 8 : 10)
                    .frame(height: 34)
                    .background(
                        overflow == nil
                            ? Color(.secondarySystemGroupedBackground)
                            : Color.indigo.opacity(0.16),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().stroke(
                            overflow == nil ? Color.clear : Color.indigo.opacity(0.45),
                            lineWidth: 1
                        )
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("planner-filter-more")
                .accessibilityLabel(overflowSelection?.title ?? "More lists")
            }
            .padding(.horizontal, 2)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, Color(.systemGroupedBackground)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var primarySmartLists: [PlannerSmartList] {
        [.inbox, .today, .overdue, .upcoming]
    }

    private var overflowSelection: PlannerSmartList? {
        selection == .waiting || selection == .completed ? selection : nil
    }

    private func selectSmartList(_ list: PlannerSmartList) {
        isQuickTaskFocused = false
        withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
            selection = list
        }
    }

    private func smartListButton(_ list: PlannerSmartList) -> some View {
        Button {
            selectSmartList(list)
        } label: {
            Text(list.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selection == list ? list.selectionTint : Color.primary)
                .padding(.horizontal, 9)
                .frame(height: 34)
                .background(
                    selection == list
                        ? list.selectionTint.opacity(0.16)
                        : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        selection == list ? list.selectionTint.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("planner-filter-\(list.rawValue)")
        .accessibilityAddTraits(selection == list ? .isSelected : [])
    }

    private var quickCapture: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(.indigo)

            TextField("Add to Inbox", text: $quickTaskTitle)
                .focused($isQuickTaskFocused)
                .submitLabel(.done)
                .onSubmit(addQuickTask)
                .accessibilityIdentifier("planner-quick-task-field")

            Button("Add", action: addQuickTask)
                .font(.subheadline.weight(.semibold))
                .disabled(trimmedQuickTitle.isEmpty)
                .accessibilityIdentifier("planner-quick-add-button")
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private func taskSection(
        title: String,
        symbol: String,
        tasks: [PlannerTask],
        tint: Color
    ) -> some View {
        Section {
            ForEach(tasks) { task in
                PlannerSmartTaskRow(
                    task: task,
                    occurrenceDate: selection == .today
                        ? calendar.startOfDay(for: .now)
                        : nil,
                    habit: habits.first(where: { $0.id == task.habitID }),
                    showsStatus: selection.showsStatus(task.status),
                    showsScheduledDate: selection == .upcoming
                        || selection == .completed
                        || selection == .overdue
                        || title == "Overdue"
                        || title == "Unfinished",
                    onOpen: { openEditor(for: task) },
                    onToggle: { toggleCompletion(task) },
                    onSetStatus: { setStatus($0, for: task) },
                    onDelete: { taskPendingDeletion = task }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        toggleCompletion(task)
                    } label: {
                        Label(
                            task.status == .completed ? "Reopen" : "Complete",
                            systemImage: task.status == .completed ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    .tint(task.status == .completed ? .indigo : .teal)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        taskPendingDeletion = task
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        openEditor(for: task)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
            }
        } header: {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(tint)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plannerEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selection.symbolName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(selection.tint)
            Text(selection.emptyTitle)
                .font(.headline)
            Text(selection.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var trimmedQuickTitle: String {
        quickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addQuickTask() {
        guard !trimmedQuickTitle.isEmpty else { return }
        let task = PlannerTask(
            title: trimmedQuickTitle,
            scheduledDay: .now,
            scheduleKind: PlannerScheduleKind.none,
            position: PlannerTaskManager.inbox(from: tasks).count,
            status: .inbox
        )
        modelContext.insert(task)

        do {
            try modelContext.save()
            withAnimation(SinceMotion.quick(reduceMotion: reduceMotion)) {
                quickTaskTitle = ""
                isQuickTaskFocused = false
            }
            playSuccessFeedback()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Task Could Not Be Added", error: error)
        }
    }

    private func toggleCompletion(_ task: PlannerTask) {
        if selection == .today {
            PlannerTaskManager.setCompletion(
                !PlannerTaskManager.isCompleted(task, on: .now, calendar: calendar),
                for: task,
                on: .now,
                calendar: calendar
            )
            if saveChanges(title: "Task Could Not Be Updated") {
                playSuccessFeedback()
            }
        } else {
            let newStatus: PlannerTaskStatus = task.status == .completed ? .planned : .completed
            setStatus(newStatus, for: task)
        }
    }

    private func setStatus(_ status: PlannerTaskStatus, for task: PlannerTask) {
        withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
            PlannerTaskManager.setStatus(status, for: task)
        }
        if saveChanges(title: "Task Could Not Be Updated") {
            playSuccessFeedback()
        }
    }

    private func openEditor(for task: PlannerTask) {
        isQuickTaskFocused = false
        editingTask = task
    }

    private func deletePendingTask() {
        guard let taskPendingDeletion else { return }
        let snapshot = PlannerDeletedTaskSnapshot(task: taskPendingDeletion)
        modelContext.delete(taskPendingDeletion)
        self.taskPendingDeletion = nil

        do {
            try modelContext.save()
            withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
                recentlyDeletedTask = snapshot
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard recentlyDeletedTask?.id == snapshot.id else { return }
                withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
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
            withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
                recentlyDeletedTask = nil
            }
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Task Could Not Be Restored", error: error)
        }
    }

    @discardableResult
    private func saveChanges(title: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: title, error: error)
            return false
        }
    }

    private func playSuccessFeedback() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

private enum PlannerSmartList: String, CaseIterable, Identifiable {
    case inbox
    case today
    case overdue
    case upcoming
    case waiting
    case completed

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var sectionTitle: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .overdue: "Overdue"
        case .upcoming: "Scheduled"
        case .waiting: "Waiting"
        case .completed: "Recently completed"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .overdue: "exclamationmark.circle"
        case .upcoming: "calendar.badge.clock"
        case .waiting: "pause.circle"
        case .completed: "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .inbox: .indigo
        case .today: .orange
        case .overdue: .red
        case .upcoming: .blue
        case .waiting: .purple
        case .completed: .teal
        }
    }

    var selectionTint: Color {
        self == .overdue ? .red : .indigo
    }

    var newTaskStatus: PlannerTaskStatus {
        switch self {
        case .inbox: .inbox
        case .today, .overdue, .upcoming: .planned
        case .waiting: .waiting
        case .completed: .inbox
        }
    }

    var newTaskDay: Date {
        switch self {
        case .upcoming:
            Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .inbox, .today, .overdue, .waiting, .completed:
            .now
        }
    }

    func showsStatus(_ status: PlannerTaskStatus) -> Bool {
        switch self {
        case .inbox:
            status != .inbox
        case .waiting:
            status != .waiting
        case .completed:
            status != .completed
        case .overdue:
            status != .planned
        case .today, .upcoming:
            status == .inProgress
        }
    }

    var emptyTitle: String {
        switch self {
        case .inbox: "Inbox cleared"
        case .today: "A clear day"
        case .overdue: "Nothing overdue"
        case .upcoming: "Nothing scheduled"
        case .waiting: "Nothing waiting"
        case .completed: "No completed tasks yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .inbox: "Quickly capture an idea above, then organize it when you are ready."
        case .today: "Add a manageable next action when something needs your attention."
        case .overdue: "Tasks past their deadlines will appear here."
        case .upcoming: "Tasks planned for future dates will collect here."
        case .waiting: "Tasks paused for someone or something else will appear here."
        case .completed: "Finished work will remain available here instead of disappearing."
        }
    }
}

private struct PlannerSmartTaskRow: View {
    let task: PlannerTask
    let occurrenceDate: Date?
    let habit: Habit?
    let showsStatus: Bool
    let showsScheduledDate: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onSetStatus: (PlannerTaskStatus) -> Void
    let onDelete: () -> Void

    private var isCompleted: Bool {
        guard let occurrenceDate else { return task.status == .completed }
        return PlannerTaskManager.isCompleted(task, on: occurrenceDate)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? .teal : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.body.weight(task.priority == .important ? .semibold : .regular))
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)

                    if showsScheduledDate, let relevantDate {
                        Label(
                            relevantDate.formatted(
                                .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("planner-scheduled-date-\(task.id)")
                    }

                    if hasPropertyPills {
                        AdaptiveFlowLayout(horizontalSpacing: 6, verticalSpacing: 5) {
                            ForEach(Array(metadataItems.prefix(2))) { item in
                                PlannerPropertyPill(
                                    title: item.title,
                                    symbol: item.symbol,
                                    tint: item.tint
                                )
                            }
                        }
                    }

                    if !task.taskNotes.isEmpty {
                        Text(task.taskNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Section("Status") {
                    ForEach(PlannerTaskStatus.allCases) { status in
                        Button {
                            onSetStatus(status)
                        } label: {
                            Label(status.title, systemImage: status.symbolName)
                        }
                    }
                }

                Button(action: onOpen) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Options for \(task.title)")
        }
        .padding(.vertical, 3)
    }

    private var hasPropertyPills: Bool {
        !metadataItems.isEmpty
    }

    private var relevantDate: Date? {
        if task.status == .completed { return task.completedAt ?? task.scheduledDay }
        return PlannerTaskManager.nextRelevantDate(for: task, onOrAfter: .now)
            ?? task.dueDate
            ?? (task.scheduleKind == .none ? nil : task.scheduledDay)
    }

    private var metadataItems: [PlannerRowMetadata] {
        var items: [PlannerRowMetadata] = []

        if let dueDate = task.dueDate, isOverdue && !isCompleted {
            items.append(
                PlannerRowMetadata(
                    id: "overdue",
                    title: dueTitle(dueDate),
                    symbol: "flag.fill",
                    tint: .red
                )
            )
        }

        if task.priority != .normal {
            items.append(
                PlannerRowMetadata(
                    id: "priority",
                    title: task.priority.title,
                    symbol: task.priority.symbolName,
                    tint: priorityTint
                )
            )
        }

        if let dueDate = task.dueDate, !isOverdue || isCompleted {
            items.append(
                PlannerRowMetadata(
                    id: "due",
                    title: dueTitle(dueDate),
                    symbol: "flag",
                    tint: .secondary
                )
            )
        }

        if showsStatus {
            items.append(
                PlannerRowMetadata(
                    id: "status",
                    title: task.status.title,
                    symbol: task.status.symbolName,
                    tint: statusTint
                )
            )
        }

        if task.scheduleKind == .multipleDays || task.scheduleKind == .repeating {
            items.append(
                PlannerRowMetadata(
                    id: "schedule",
                    title: PlannerTaskManager.scheduleSummary(for: task),
                    symbol: task.scheduleKind == .repeating ? "repeat" : "calendar.badge.clock",
                    tint: .indigo
                )
            )
        }

        if let habit {
            items.append(
                PlannerRowMetadata(
                    id: "habit",
                    title: habit.name,
                    symbol: habit.symbolName,
                    tint: habit.tint.color
                )
            )
        }

        return items
    }

    private func dueTitle(_ dueDate: Date) -> String {
        let dateText = dueDate.formatted(.dateTime.month(.abbreviated).day())
        if let dueTime = task.dueTime {
            return "Due \(dateText), \(dueTime.formatted(date: .omitted, time: .shortened))"
        }
        return "Due \(dateText)"
    }

    private var isOverdue: Bool {
        if let dueTime = task.dueTime { return dueTime < .now }
        guard let dueDate = task.dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    private var statusTint: Color {
        switch task.status {
        case .inbox: .indigo
        case .planned: .blue
        case .inProgress: .orange
        case .waiting: .purple
        case .completed: .teal
        }
    }

    private var priorityTint: Color {
        switch task.priority {
        case .normal: .secondary
        case .low: .blue
        case .medium: .orange
        case .important: .red
        }
    }
}

private struct PlannerPropertyPill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PlannerRowMetadata: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
}

private struct PlannerDeletedTaskSnapshot {
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
