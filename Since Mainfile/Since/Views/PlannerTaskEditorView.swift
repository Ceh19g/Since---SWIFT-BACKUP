import SwiftData
import SwiftUI

struct PlannerTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var allTasks: [PlannerTask]

    let task: PlannerTask?
    let initialDay: Date
    let initialStatus: PlannerTaskStatus

    @State private var title: String
    @State private var taskNotes: String
    @State private var status: PlannerTaskStatus
    @State private var scheduleKind: PlannerScheduleKind
    @State private var scheduledDay: Date
    @State private var scheduleEndDate: Date
    @State private var selectedWorkdays: Set<Int>
    @State private var timeMode: PlannerTimeMode
    @State private var scheduledTime: Date
    @State private var daySection: PlannerDaySection
    @State private var hasDuration: Bool
    @State private var durationMinutes: Int
    @State private var customizeEachDay: Bool
    @State private var customSessions: [PlannerWorkSession]
    @State private var repeatFrequency: PlannerRepeatFrequency
    @State private var repeatInterval: Int
    @State private var repeatEndMode: PlannerRepeatEndMode
    @State private var repeatEndDate: Date
    @State private var repeatCount: Int
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasDueTime: Bool
    @State private var dueTime: Date
    @State private var priority: PlannerTaskPriority
    @State private var habitID: UUID?
    @State private var showsMoreOptions: Bool
    @State private var saveErrorMessage = ""
    @State private var isShowingSaveError = false
    @FocusState private var isTextInputFocused: Bool

    private let calendar = Calendar.autoupdatingCurrent
    private let durationOptions = [15, 30, 45, 60, 90, 120, 180, 240]

    private var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    private var selectableHabits: [Habit] {
        guard let habitID,
              let linkedHabit = habits.first(where: { $0.id == habitID }),
              linkedHabit.isArchived else { return activeHabits }
        return activeHabits + [linkedHabit]
    }

    init(
        task: PlannerTask? = nil,
        scheduledDay: Date,
        initialStatus: PlannerTaskStatus = .planned
    ) {
        let calendar = Calendar.autoupdatingCurrent
        let baseDay = task?.scheduledDay ?? scheduledDay
        let endDay = task?.scheduleEndDate
            ?? calendar.date(byAdding: .day, value: 3, to: baseDay)
            ?? baseDay
        let storedSessions = PlannerTaskManager.decodedSessions(task?.customWorkSessionsData)
        let resolvedKind = task?.scheduleKind
            ?? ((initialStatus == .inbox || initialStatus == .waiting) ? .none : .once)

        self.task = task
        self.initialDay = scheduledDay
        self.initialStatus = initialStatus
        _title = State(initialValue: task?.title ?? "")
        _taskNotes = State(initialValue: task?.taskNotes ?? "")
        _status = State(initialValue: task?.status ?? initialStatus)
        _scheduleKind = State(initialValue: resolvedKind)
        _scheduledDay = State(initialValue: baseDay)
        _scheduleEndDate = State(initialValue: endDay)
        _selectedWorkdays = State(
            initialValue: PlannerTaskManager.decodedWeekdays(task?.scheduleWeekdaysRawValue)
        )
        _timeMode = State(initialValue: task?.timeMode ?? .anytime)
        _scheduledTime = State(initialValue: task?.scheduledTime ?? baseDay)
        _daySection = State(initialValue: task?.daySection ?? .morning)
        _hasDuration = State(initialValue: task?.plannedDurationMinutes != nil)
        _durationMinutes = State(initialValue: task?.plannedDurationMinutes ?? 60)
        _customizeEachDay = State(initialValue: resolvedKind == .multipleDays && !storedSessions.isEmpty)
        _customSessions = State(initialValue: storedSessions)
        _repeatFrequency = State(initialValue: task?.repeatFrequency ?? .weekly)
        _repeatInterval = State(initialValue: max(1, task?.repeatInterval ?? 1))
        _repeatEndMode = State(initialValue: task?.repeatEndMode ?? .never)
        _repeatEndDate = State(
            initialValue: task?.repeatEndDate
                ?? calendar.date(byAdding: .month, value: 1, to: baseDay)
                ?? baseDay
        )
        _repeatCount = State(initialValue: max(1, task?.repeatCount ?? 10))
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? baseDay)
        _hasDueTime = State(initialValue: task?.dueTime != nil)
        _dueTime = State(initialValue: task?.dueTime ?? baseDay)
        _priority = State(initialValue: task?.priority ?? .normal)
        _habitID = State(initialValue: task?.habitID)
        _showsMoreOptions = State(initialValue: task != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                taskSection
                planWorkSection
                moreOptionsSection
                if showsMoreOptions {
                    workflowSection
                    deadlineSection
                    detailsSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save", action: save)
                        .accessibilityIdentifier("save-planner-task-button")
                        .disabled(trimmedTitle.isEmpty || !scheduleIsValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .alert("Task Could Not Be Saved", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var taskSection: some View {
        Section {
            TextField("Task name", text: $title)
                .focused($isTextInputFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit { isTextInputFocused = false }
                .accessibilityIdentifier("planner-task-title-field")
        } header: {
            Text("Task")
        } footer: {
            Text("Capture the action first. Scheduling and deadlines stay independent.")
        }
    }

    private var moreOptionsSection: some View {
        Section {
            Button {
                if reduceMotion {
                    showsMoreOptions.toggle()
                } else {
                    withAnimation(SinceMotion.standard(reduceMotion: false)) {
                        showsMoreOptions.toggle()
                    }
                }
            } label: {
                HStack {
                    Label(
                        showsMoreOptions ? "Hide options" : "More options",
                        systemImage: "slider.horizontal.3"
                    )
                    Spacer()
                    Image(systemName: showsMoreOptions ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("planner-more-options-button")
        } footer: {
            if !showsMoreOptions {
                Text("Status, deadlines, priority, notes, and habit links are optional.")
            }
        }
    }

    private var workflowSection: some View {
        Section("Workflow") {
            Picker("Status", selection: $status) {
                ForEach(PlannerTaskStatus.allCases) { option in
                    Label(option.title, systemImage: option.symbolName).tag(option)
                }
            }
        }
    }

    private var planWorkSection: some View {
        Section {
            Picker("Schedule", selection: $scheduleKind) {
                ForEach(PlannerScheduleKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .accessibilityIdentifier("planner-schedule-picker")

            if scheduleKind != .none {
                DatePicker(
                    scheduleKind == .repeating ? "Starts" : "Planned",
                    selection: $scheduledDay,
                    displayedComponents: .date
                )

                if scheduleKind == .multipleDays {
                    DatePicker(
                        "Ends",
                        selection: $scheduleEndDate,
                        in: calendar.startOfDay(for: scheduledDay)...,
                        displayedComponents: .date
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Work days")
                            .font(.subheadline)
                        WeekdaySelector(selection: $selectedWorkdays)
                    }
                    .padding(.vertical, 4)
                }

                if scheduleKind == .repeating {
                    repeatControls
                }

                timeControls

                if scheduleKind == .multipleDays && timeMode == .exactTime {
                    Toggle("Customize each day", isOn: $customizeEachDay)
                        .onChange(of: customizeEachDay) { _, enabled in
                            if enabled { refreshCustomSessions() }
                        }

                    if customizeEachDay {
                        customSessionControls
                    }
                }
            }
        } header: {
            Text("Plan Work")
        } footer: {
            Text(planFooter)
        }
        .onChange(of: scheduledDay) { _, _ in refreshCustomSessionsIfNeeded() }
        .onChange(of: scheduleEndDate) { _, _ in refreshCustomSessionsIfNeeded() }
        .onChange(of: selectedWorkdays) { _, _ in refreshCustomSessionsIfNeeded() }
    }

    @ViewBuilder
    private var repeatControls: some View {
        Picker("Frequency", selection: $repeatFrequency) {
            ForEach(PlannerRepeatFrequency.allCases) { frequency in
                Text(frequency.title).tag(frequency)
            }
        }

        if repeatFrequency == .daily || repeatFrequency == .weekly || repeatFrequency == .monthly {
            Stepper(value: $repeatInterval, in: 1...30) {
                LabeledContent("Interval", value: repeatIntervalDescription)
            }
        }

        if repeatFrequency == .custom {
            VStack(alignment: .leading, spacing: 10) {
                Text("Repeats on")
                    .font(.subheadline)
                WeekdaySelector(selection: $selectedWorkdays)
            }
            .padding(.vertical, 4)
        }

        Picker("Ends", selection: $repeatEndMode) {
            ForEach(PlannerRepeatEndMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        if repeatEndMode == .onDate {
            DatePicker(
                "End date",
                selection: $repeatEndDate,
                in: calendar.startOfDay(for: scheduledDay)...,
                displayedComponents: .date
            )
        } else if repeatEndMode == .afterCount {
            Stepper(value: $repeatCount, in: 1...999) {
                LabeledContent("Occurrences", value: "\(repeatCount)")
            }
        }
    }

    @ViewBuilder
    private var timeControls: some View {
        Picker("When", selection: $timeMode) {
            Text("Anytime").tag(PlannerTimeMode.anytime)
            Text("Part of day").tag(PlannerTimeMode.daySection)
            Text("Exact time").tag(PlannerTimeMode.exactTime)
        }

        if timeMode == .daySection {
            Picker("Part of day", selection: $daySection) {
                ForEach(PlannerDaySection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName).tag(section)
                }
            }
        } else if timeMode == .exactTime {
            DatePicker("Start time", selection: $scheduledTime, displayedComponents: .hourAndMinute)
            Toggle("Add duration", isOn: $hasDuration)
            if hasDuration {
                Picker("Duration", selection: $durationMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text(durationDescription(minutes)).tag(minutes)
                    }
                }
            }
        }
    }

    private var customSessionControls: some View {
        ForEach($customSessions) { $session in
            VStack(alignment: .leading, spacing: 8) {
                Text(session.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { session.startTime ?? session.day },
                        set: { session.startTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Picker(
                    "Duration",
                    selection: Binding(
                        get: { session.durationMinutes ?? durationMinutes },
                        set: { session.durationMinutes = $0 }
                    )
                ) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text(durationDescription(minutes)).tag(minutes)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var deadlineSection: some View {
        Section {
            Toggle("Add deadline", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                Toggle("Add due time", isOn: $hasDueTime)
                if hasDueTime {
                    DatePicker("Due time", selection: $dueTime, displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("Deadline")
        } footer: {
            Text("The deadline appears on the calendar even when this task is not planned.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Notes (optional)", text: $taskNotes, axis: .vertical)
                .focused($isTextInputFocused)
                .lineLimit(2...4)

            Picker("Priority", selection: $priority) {
                ForEach(PlannerTaskPriority.allCases) { option in
                    Label(option.title, systemImage: option.symbolName).tag(option)
                }
            }
            Picker("Supports a habit", selection: $habitID) {
                Text("No habit").tag(UUID?.none)
                if let habitID, !habits.contains(where: { $0.id == habitID }) {
                    Text("Habit removed").tag(Optional(habitID))
                }
                ForEach(selectableHabits) { habit in
                    Label(
                        habit.isArchived ? "\(habit.name) — Archived" : habit.name,
                        systemImage: habit.symbolName
                    )
                    .tag(Optional(habit.id))
                }
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scheduleIsValid: Bool {
        scheduleKind != .multipleDays || scheduleEndDate >= calendar.startOfDay(for: scheduledDay)
    }

    private var planFooter: String {
        switch scheduleKind {
        case .none: "This task stays out of the daily schedule unless it has a deadline."
        case .once: "Choose when you intend to work on this task."
        case .multipleDays: "These work sessions belong to one overall task."
        case .repeating: "Each occurrence can be completed independently."
        }
    }

    private var repeatIntervalDescription: String {
        let unit: String
        switch repeatFrequency {
        case .daily: unit = repeatInterval == 1 ? "day" : "days"
        case .weekly: unit = repeatInterval == 1 ? "week" : "weeks"
        case .monthly: unit = repeatInterval == 1 ? "month" : "months"
        case .weekdays, .custom: unit = ""
        }
        return repeatInterval == 1 ? "Every \(unit)" : "Every \(repeatInterval) \(unit)"
    }

    private func durationDescription(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours) hr \(remainder) min"
    }

    private func selectedSessionDates() -> [Date] {
        let start = calendar.startOfDay(for: scheduledDay)
        let end = max(start, calendar.startOfDay(for: scheduleEndDate))
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            if selectedWorkdays.contains(calendar.component(.weekday, from: cursor)) {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates.isEmpty ? [start] : dates
    }

    private func refreshCustomSessionsIfNeeded() {
        guard customizeEachDay, scheduleKind == .multipleDays else { return }
        refreshCustomSessions()
    }

    private func refreshCustomSessions() {
        let existing = Dictionary(uniqueKeysWithValues: customSessions.map {
            (calendar.startOfDay(for: $0.day), $0)
        })
        customSessions = selectedSessionDates().map { day in
            if let session = existing[day] { return session.moved(to: day, calendar: calendar) }
            return makeBaseSession(on: day)
        }
    }

    private func makeBaseSession(on day: Date) -> PlannerWorkSession {
        PlannerWorkSession(
            day: day,
            timeMode: timeMode,
            startTime: timeMode == .exactTime ? combinedTime(scheduledTime, on: day) : nil,
            daySection: timeMode == .daySection ? daySection : nil,
            durationMinutes: timeMode == .exactTime && hasDuration ? durationMinutes : nil,
            calendar: calendar
        )
    }

    private func combinedTime(_ time: Date, on day: Date) -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: calendar.startOfDay(for: day)
        )
    }

    private func save() {
        let day = calendar.startOfDay(for: scheduledDay)
        let normalizedDueDate = hasDueDate ? calendar.startOfDay(for: dueDate) : nil
        let normalizedDueTime = hasDueDate && hasDueTime ? combinedTime(dueTime, on: dueDate) : nil
        let exactTime = timeMode == .exactTime ? combinedTime(scheduledTime, on: day) : nil
        let selectedSection = timeMode == .daySection ? daySection : nil
        let normalizedDuration = timeMode == .exactTime && hasDuration ? durationMinutes : nil
        let sessionsData: Data?
        if scheduleKind == .multipleDays {
            if customizeEachDay {
                sessionsData = PlannerTaskManager.encodedSessions(customSessions)
            } else {
                sessionsData = nil
            }
        } else {
            sessionsData = nil
        }

        if let task {
            let changedDay = !calendar.isDate(task.scheduledDay, inSameDayAs: day)
            task.title = trimmedTitle
            task.taskNotes = taskNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.scheduleKind = scheduleKind
            task.scheduledDay = day
            task.scheduleEndDate = scheduleKind == .multipleDays
                ? calendar.startOfDay(for: scheduleEndDate)
                : nil
            task.scheduleWeekdaysRawValue = PlannerTaskManager.encodedWeekdays(selectedWorkdays)
            task.timeMode = timeMode
            task.scheduledTime = exactTime
            task.daySection = selectedSection
            task.plannedDurationMinutes = normalizedDuration
            task.customWorkSessionsData = sessionsData
            task.repeatFrequency = repeatFrequency
            task.repeatInterval = repeatInterval
            task.repeatEndMode = repeatEndMode
            task.repeatEndDate = repeatEndMode == .onDate ? calendar.startOfDay(for: repeatEndDate) : nil
            task.repeatCount = repeatEndMode == .afterCount ? repeatCount : nil
            task.dueDate = normalizedDueDate
            task.dueTime = normalizedDueTime
            task.priority = priority
            task.habitID = habitID
            PlannerTaskManager.setStatus(status, for: task)
            if changedDay { task.position = PlannerTaskManager.nextPosition(for: allTasks, on: day) }
        } else {
            modelContext.insert(
                PlannerTask(
                    title: trimmedTitle,
                    taskNotes: taskNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                    scheduledDay: day,
                    dueDate: normalizedDueDate,
                    dueTime: normalizedDueTime,
                    timeMode: timeMode,
                    scheduledTime: exactTime,
                    daySection: selectedSection,
                    scheduleKind: scheduleKind,
                    scheduleEndDate: scheduleKind == .multipleDays ? scheduleEndDate : nil,
                    scheduleWeekdays: selectedWorkdays,
                    plannedDurationMinutes: normalizedDuration,
                    customWorkSessionsData: sessionsData,
                    repeatFrequency: repeatFrequency,
                    repeatInterval: repeatInterval,
                    repeatEndMode: repeatEndMode,
                    repeatEndDate: repeatEndMode == .onDate ? repeatEndDate : nil,
                    repeatCount: repeatEndMode == .afterCount ? repeatCount : nil,
                    position: PlannerTaskManager.nextPosition(for: allTasks, on: day),
                    priority: priority,
                    status: status,
                    habitID: habitID
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isShowingSaveError = true
        }
    }
}
