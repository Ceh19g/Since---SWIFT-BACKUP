import Foundation
import SwiftData
import SwiftUI

enum HabitType: String, CaseIterable, Codable, Identifiable {
    case abstinence
    case positiveStreak
    case frequency
    case count
    case duration
    case event
    case sinceDate
    case countdown

    var id: String { rawValue }

    static let supportedCases: [HabitType] = [
        .abstinence,
        .positiveStreak,
        .event,
        .sinceDate,
        .countdown
    ]

    var title: String {
        switch self {
        case .abstinence: "Stop a habit"
        case .positiveStreak: "Build a daily habit"
        case .frequency: "Reach a frequency"
        case .count: "Reach a count"
        case .duration: "Track time spent"
        case .event: "Track the last time"
        case .sinceDate: "Remember a meaningful date"
        case .countdown: "Countdown to a date"
        }
    }

    var explanation: String {
        switch self {
        case .abstinence: "Count exact time since you stopped."
        case .positiveStreak: "Check in once each day and build a streak."
        case .frequency: "Complete a goal several times per period."
        case .count: "Add units toward a recurring target."
        case .duration: "Log or time focused sessions."
        case .event: "Remember when something last happened."
        case .sinceDate: "Count exact time since an anniversary or important moment."
        case .countdown: "See the exact time remaining until something you are anticipating."
        }
    }

    var symbolName: String {
        switch self {
        case .abstinence: "hand.raised.fill"
        case .positiveStreak: "checkmark.circle.fill"
        case .frequency: "repeat.circle.fill"
        case .count: "number.circle.fill"
        case .duration: "timer"
        case .event: "arrow.clockwise.circle.fill"
        case .sinceDate: "heart.circle.fill"
        case .countdown: "calendar.badge.clock"
        }
    }

    var dateSectionTitle: String {
        switch self {
        case .abstinence: "Stopped"
        case .positiveStreak: "Begin tracking"
        case .event: "Last happened"
        case .sinceDate: "Meaningful date"
        case .countdown: "Target date"
        case .frequency, .count, .duration: "Started"
        }
    }
}

enum HabitTint: String, CaseIterable, Codable, Identifiable {
    case indigo
    case teal
    case orange
    case rose
    case blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .teal: .teal
        case .orange: .orange
        case .rose: .pink
        case .blue: .blue
        }
    }
}

enum HabitAppearanceOptions {
    static let symbols = [
        "leaf.fill",
        "drop.fill",
        "heart.fill",
        "moon.stars.fill",
        "figure.walk",
        "book.fill",
        "cup.and.saucer.fill",
        "dumbbell.fill",
        "brain.head.profile.fill",
        "sparkles"
    ]
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var habitDescription: String
    var typeRawValue: String
    var tintRawValue: String
    var symbolName: String
    var startAt: Date
    var customMilestoneDays: Int?
    var healthMetricRawValue: String?
    var healthGoalValue: Double?
    var healthGoalWeekdaysRawValue: String?
    var healthGoalHistoryData: Data?
    var measurementTemplateRawValue: String?
    var measurementCustomName: String?
    var measurementCustomUnit: String?
    var measurementCustomValueKindRawValue: String?
    var measurementDefaultValue: Double?
    var isPinned: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HabitEvent.habit)
    var events: [HabitEvent]

    var type: HabitType {
        get { HabitType(rawValue: typeRawValue) ?? .abstinence }
        set { typeRawValue = newValue.rawValue }
    }

    var tint: HabitTint {
        get { HabitTint(rawValue: tintRawValue) ?? .indigo }
        set { tintRawValue = newValue.rawValue }
    }

    var healthMetric: HealthMetric? {
        get { healthMetricRawValue.flatMap(HealthMetric.init(rawValue:)) }
        set { healthMetricRawValue = newValue?.rawValue }
    }

    var isHealthPowered: Bool {
        healthMetric != nil
    }

    var trackingTitle: String {
        healthMetric?.title ?? type.title
    }

    init(
        id: UUID = UUID(),
        name: String,
        habitDescription: String = "",
        type: HabitType = .abstinence,
        tint: HabitTint = .indigo,
        symbolName: String = "leaf.fill",
        startAt: Date,
        customMilestoneDays: Int? = nil,
        healthMetric: HealthMetric? = nil,
        healthGoalValue: Double? = nil,
        healthGoalWeekdays: Set<Int> = HealthGoalManager.everyDay,
        healthGoalHistoryData: Data? = nil,
        measurementTemplateRawValue: String? = nil,
        measurementCustomName: String? = nil,
        measurementCustomUnit: String? = nil,
        measurementCustomValueKindRawValue: String? = nil,
        measurementDefaultValue: Double? = nil,
        isPinned: Bool = true,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        events: [HabitEvent] = []
    ) {
        self.id = id
        self.name = name
        self.habitDescription = habitDescription
        self.typeRawValue = type.rawValue
        self.tintRawValue = tint.rawValue
        self.symbolName = symbolName
        self.startAt = startAt
        self.customMilestoneDays = customMilestoneDays
        self.healthMetricRawValue = healthMetric?.rawValue
        self.healthGoalValue = healthGoalValue
        self.healthGoalWeekdaysRawValue = healthMetric == nil
            ? nil
            : HealthGoalManager.encodedWeekdays(healthGoalWeekdays)
        self.healthGoalHistoryData = healthGoalHistoryData
        self.measurementTemplateRawValue = measurementTemplateRawValue
        self.measurementCustomName = measurementCustomName
        self.measurementCustomUnit = measurementCustomUnit
        self.measurementCustomValueKindRawValue = measurementCustomValueKindRawValue
        self.measurementDefaultValue = measurementDefaultValue
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.events = events

        if healthMetric != nil, let healthGoalValue, healthGoalHistoryData == nil {
            HealthGoalManager.recordGoal(
                for: self,
                target: healthGoalValue,
                activeWeekdays: healthGoalWeekdays,
                effectiveAt: startAt
            )
        }
    }
}
