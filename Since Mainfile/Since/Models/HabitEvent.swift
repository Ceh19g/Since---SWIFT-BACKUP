import Foundation
import SwiftData

enum HabitEventKind: String, Codable, CaseIterable {
    case started
    case completed
    case slip
    case reset
    case paused
    case resumed
    case note

    var title: String {
        switch self {
        case .started: "Started"
        case .completed: "Completed"
        case .slip: "Slip recorded"
        case .reset: "Streak restarted"
        case .paused: "Paused"
        case .resumed: "Resumed"
        case .note: "Note"
        }
    }
}

@Model
final class HabitEvent {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var occurredAt: Date
    var endedAt: Date?
    var note: String
    var restartsStreak: Bool
    var measurementValue: Double?
    var measurementSourceID: String?
    var measurementName: String?
    var measurementUnit: String?
    var measurementValueKindRawValue: String?
    var timezoneIdentifier: String
    var createdAt: Date
    var habit: Habit?

    var kind: HabitEventKind {
        get { HabitEventKind(rawValue: kindRawValue) ?? .note }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: HabitEventKind,
        occurredAt: Date,
        endedAt: Date? = nil,
        note: String = "",
        restartsStreak: Bool = false,
        measurementValue: Double? = nil,
        measurementSourceID: String? = nil,
        measurementName: String? = nil,
        measurementUnit: String? = nil,
        measurementValueKindRawValue: String? = nil,
        timezoneIdentifier: String = TimeZone.current.identifier,
        createdAt: Date = .now,
        habit: Habit? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.occurredAt = occurredAt
        self.endedAt = endedAt
        self.note = note
        self.restartsStreak = restartsStreak
        self.measurementValue = measurementValue
        self.measurementSourceID = measurementSourceID
        self.measurementName = measurementName
        self.measurementUnit = measurementUnit
        self.measurementValueKindRawValue = measurementValueKindRawValue
        self.timezoneIdentifier = timezoneIdentifier
        self.createdAt = createdAt
        self.habit = habit
    }
}
