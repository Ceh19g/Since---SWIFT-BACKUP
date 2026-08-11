import Foundation
import SwiftData

enum PlannerTimeMode: String, CaseIterable, Codable, Identifiable {
    case anytime
    case daySection
    case exactTime

    var id: String { rawValue }
}

enum PlannerDaySection: String, CaseIterable, Codable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }
}

enum PlannerTaskStatus: String, CaseIterable, Codable, Identifiable {
    case inbox
    case planned
    case inProgress
    case waiting
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "To Do"
        case .inProgress: "In Progress"
        case .waiting: "Waiting"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .planned: "calendar"
        case .inProgress: "circle.lefthalf.filled"
        case .waiting: "pause.circle"
        case .completed: "checkmark.circle.fill"
        }
    }

    var appearsOnCalendar: Bool {
        self == .planned || self == .inProgress || self == .completed
    }
}

enum PlannerTaskPriority: String, CaseIterable, Codable, Identifiable {
    case normal
    case low
    case medium
    case important

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .important: "High"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "minus"
        case .low: "flag"
        case .medium: "flag.fill"
        case .important: "exclamationmark.circle.fill"
        }
    }
}

@Model
final class PlannerTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskNotes: String
    var scheduledDay: Date
    var dueDate: Date?
    var dueTime: Date?
    var timeModeRawValue: String
    var scheduledTime: Date?
    var daySectionRawValue: String?
    var scheduleKindRawValue: String?
    var scheduleEndDate: Date?
    var scheduleWeekdaysRawValue: String?
    var plannedDurationMinutes: Int?
    var customWorkSessionsData: Data?
    var repeatFrequencyRawValue: String?
    var repeatInterval: Int?
    var repeatEndModeRawValue: String?
    var repeatEndDate: Date?
    var repeatCount: Int?
    var completedOccurrenceDaysData: Data?
    var excludedOccurrenceDaysData: Data?
    var isCompleted: Bool
    var completedAt: Date?
    var position: Int
    var priorityRawValue: String
    var statusRawValue: String = "planned"
    var habitID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var timeMode: PlannerTimeMode {
        get { PlannerTimeMode(rawValue: timeModeRawValue) ?? .anytime }
        set { timeModeRawValue = newValue.rawValue }
    }

    var daySection: PlannerDaySection? {
        get { daySectionRawValue.flatMap(PlannerDaySection.init(rawValue:)) }
        set { daySectionRawValue = newValue?.rawValue }
    }

    var scheduleKind: PlannerScheduleKind {
        get {
            if let rawValue = scheduleKindRawValue,
               let stored = PlannerScheduleKind(rawValue: rawValue) {
                return stored
            }
            return status == .inbox || status == .waiting ? .none : .once
        }
        set { scheduleKindRawValue = newValue.rawValue }
    }

    var repeatFrequency: PlannerRepeatFrequency {
        get {
            repeatFrequencyRawValue
                .flatMap(PlannerRepeatFrequency.init(rawValue:)) ?? .weekly
        }
        set { repeatFrequencyRawValue = newValue.rawValue }
    }

    var repeatEndMode: PlannerRepeatEndMode {
        get {
            repeatEndModeRawValue
                .flatMap(PlannerRepeatEndMode.init(rawValue:)) ?? .never
        }
        set { repeatEndModeRawValue = newValue.rawValue }
    }

    var priority: PlannerTaskPriority {
        get { PlannerTaskPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    var status: PlannerTaskStatus {
        get {
            if isCompleted { return .completed }
            let stored = PlannerTaskStatus(rawValue: statusRawValue) ?? .planned
            return stored == .completed ? .planned : stored
        }
        set {
            statusRawValue = newValue.rawValue
            isCompleted = newValue == .completed
            if !isCompleted {
                completedAt = nil
            } else if completedAt == nil {
                completedAt = .now
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        taskNotes: String = "",
        scheduledDay: Date,
        dueDate: Date? = nil,
        dueTime: Date? = nil,
        timeMode: PlannerTimeMode = .anytime,
        scheduledTime: Date? = nil,
        daySection: PlannerDaySection? = nil,
        scheduleKind: PlannerScheduleKind? = nil,
        scheduleEndDate: Date? = nil,
        scheduleWeekdays: Set<Int>? = nil,
        plannedDurationMinutes: Int? = nil,
        customWorkSessionsData: Data? = nil,
        repeatFrequency: PlannerRepeatFrequency = .weekly,
        repeatInterval: Int = 1,
        repeatEndMode: PlannerRepeatEndMode = .never,
        repeatEndDate: Date? = nil,
        repeatCount: Int? = nil,
        completedOccurrenceDaysData: Data? = nil,
        excludedOccurrenceDaysData: Data? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        position: Int = 0,
        priority: PlannerTaskPriority = .normal,
        status: PlannerTaskStatus? = nil,
        habitID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.taskNotes = taskNotes
        self.scheduledDay = PlannerTaskManager.startOfDay(scheduledDay)
        self.dueDate = dueDate.map { PlannerTaskManager.startOfDay($0) }
        self.dueTime = dueTime
        self.timeModeRawValue = timeMode.rawValue
        self.scheduledTime = scheduledTime
        self.daySectionRawValue = daySection?.rawValue
        let resolvedStatus = status ?? (isCompleted ? .completed : .planned)
        let resolvedScheduleKind = scheduleKind
            ?? ((resolvedStatus == .inbox || resolvedStatus == .waiting) ? .none : .once)
        self.scheduleKindRawValue = resolvedScheduleKind.rawValue
        self.scheduleEndDate = scheduleEndDate.map { PlannerTaskManager.startOfDay($0) }
        self.scheduleWeekdaysRawValue = scheduleWeekdays.map(PlannerTaskManager.encodedWeekdays)
        self.plannedDurationMinutes = plannedDurationMinutes
        self.customWorkSessionsData = customWorkSessionsData
        self.repeatFrequencyRawValue = repeatFrequency.rawValue
        self.repeatInterval = max(1, repeatInterval)
        self.repeatEndModeRawValue = repeatEndMode.rawValue
        self.repeatEndDate = repeatEndDate.map { PlannerTaskManager.startOfDay($0) }
        self.repeatCount = repeatCount
        self.completedOccurrenceDaysData = completedOccurrenceDaysData
        self.excludedOccurrenceDaysData = excludedOccurrenceDaysData
        self.isCompleted = resolvedStatus == .completed
        self.completedAt = resolvedStatus == .completed ? (completedAt ?? updatedAt) : nil
        self.position = position
        self.priorityRawValue = priority.rawValue
        self.statusRawValue = resolvedStatus.rawValue
        self.habitID = habitID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
