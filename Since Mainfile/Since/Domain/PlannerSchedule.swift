import Foundation

enum PlannerScheduleKind: String, CaseIterable, Codable, Identifiable {
    case none
    case once
    case multipleDays
    case repeating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Not planned"
        case .once: "Once"
        case .multipleDays: "Multiple days"
        case .repeating: "Repeating"
        }
    }
}

enum PlannerRepeatFrequency: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekdays
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom: "Custom weekdays"
        }
    }
}

enum PlannerRepeatEndMode: String, CaseIterable, Codable, Identifiable {
    case never
    case onDate
    case afterCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .onDate: "On date"
        case .afterCount: "After occurrences"
        }
    }
}

struct PlannerWorkSession: Codable, Equatable, Identifiable {
    var id: UUID
    var day: Date
    var timeModeRawValue: String
    var startTime: Date?
    var daySectionRawValue: String?
    var durationMinutes: Int?

    var timeMode: PlannerTimeMode {
        PlannerTimeMode(rawValue: timeModeRawValue) ?? .anytime
    }

    var daySection: PlannerDaySection? {
        daySectionRawValue.flatMap(PlannerDaySection.init(rawValue:))
    }

    init(
        id: UUID = UUID(),
        day: Date,
        timeMode: PlannerTimeMode = .anytime,
        startTime: Date? = nil,
        daySection: PlannerDaySection? = nil,
        durationMinutes: Int? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.day = calendar.startOfDay(for: day)
        self.timeModeRawValue = timeMode.rawValue
        self.startTime = startTime
        self.daySectionRawValue = daySection?.rawValue
        self.durationMinutes = durationMinutes
    }

    func moved(to date: Date, calendar: Calendar = .current) -> PlannerWorkSession {
        let targetDay = calendar.startOfDay(for: date)
        let movedStart: Date?
        if let startTime {
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            movedStart = calendar.date(
                bySettingHour: components.hour ?? 0,
                minute: components.minute ?? 0,
                second: 0,
                of: targetDay
            )
        } else {
            movedStart = nil
        }

        return PlannerWorkSession(
            id: id,
            day: targetDay,
            timeMode: timeMode,
            startTime: movedStart,
            daySection: daySection,
            durationMinutes: durationMinutes,
            calendar: calendar
        )
    }
}

enum PlannerCalendarReason: String, Hashable {
    case planned
    case due
    case completed
}

struct PlannerDayTask: Identifiable {
    let task: PlannerTask
    let date: Date
    let reasons: Set<PlannerCalendarReason>
    let session: PlannerWorkSession?
    let isCompleted: Bool

    var id: UUID { task.id }
    var isPlanned: Bool { reasons.contains(.planned) }
    var isDue: Bool { reasons.contains(.due) }
    var wasCompletedOnDate: Bool { reasons.contains(.completed) }
}
