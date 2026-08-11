import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct SinceBackupArchive: Codable {
    static let currentVersion = 5
    static let oldestSupportedVersion = 1

    let version: Int
    let exportedAt: Date
    let habits: [HabitBackupRecord]
    let plannerTasks: [PlannerTaskBackupRecord]
}

nonisolated struct HabitBackupRecord: Codable {
    let id: UUID
    let name: String
    let habitDescription: String
    let typeRawValue: String
    let tintRawValue: String
    let symbolName: String
    let startAt: Date
    let customMilestoneDays: Int?
    let healthMetricRawValue: String?
    let healthGoalValue: Double?
    let healthGoalWeekdaysRawValue: String?
    let healthGoalHistoryData: Data?
    let measurementTemplateRawValue: String?
    let measurementCustomName: String?
    let measurementCustomUnit: String?
    let measurementCustomValueKindRawValue: String?
    let measurementDefaultValue: Double?
    let isPinned: Bool
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let events: [HabitEventBackupRecord]

    init(
        id: UUID,
        name: String,
        habitDescription: String,
        typeRawValue: String,
        tintRawValue: String,
        symbolName: String,
        startAt: Date,
        customMilestoneDays: Int?,
        healthMetricRawValue: String? = nil,
        healthGoalValue: Double? = nil,
        healthGoalWeekdaysRawValue: String? = nil,
        healthGoalHistoryData: Data? = nil,
        measurementTemplateRawValue: String? = nil,
        measurementCustomName: String? = nil,
        measurementCustomUnit: String? = nil,
        measurementCustomValueKindRawValue: String? = nil,
        measurementDefaultValue: Double? = nil,
        isPinned: Bool,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date,
        events: [HabitEventBackupRecord]
    ) {
        self.id = id
        self.name = name
        self.habitDescription = habitDescription
        self.typeRawValue = typeRawValue
        self.tintRawValue = tintRawValue
        self.symbolName = symbolName
        self.startAt = startAt
        self.customMilestoneDays = customMilestoneDays
        self.healthMetricRawValue = healthMetricRawValue
        self.healthGoalValue = healthGoalValue
        self.healthGoalWeekdaysRawValue = healthGoalWeekdaysRawValue
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
    }
}

nonisolated struct HabitEventBackupRecord: Codable {
    let id: UUID
    let kindRawValue: String
    let occurredAt: Date
    let endedAt: Date?
    let note: String
    let restartsStreak: Bool
    let timezoneIdentifier: String
    let createdAt: Date
    let measurementValue: Double?
    let measurementSourceID: String?
    let measurementName: String?
    let measurementUnit: String?
    let measurementValueKindRawValue: String?

    init(
        id: UUID,
        kindRawValue: String,
        occurredAt: Date,
        endedAt: Date?,
        note: String,
        restartsStreak: Bool,
        timezoneIdentifier: String,
        createdAt: Date,
        measurementValue: Double? = nil,
        measurementSourceID: String? = nil,
        measurementName: String? = nil,
        measurementUnit: String? = nil,
        measurementValueKindRawValue: String? = nil
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.occurredAt = occurredAt
        self.endedAt = endedAt
        self.note = note
        self.restartsStreak = restartsStreak
        self.timezoneIdentifier = timezoneIdentifier
        self.createdAt = createdAt
        self.measurementValue = measurementValue
        self.measurementSourceID = measurementSourceID
        self.measurementName = measurementName
        self.measurementUnit = measurementUnit
        self.measurementValueKindRawValue = measurementValueKindRawValue
    }
}

nonisolated struct PlannerTaskBackupRecord: Codable {
    let id: UUID
    let title: String
    let taskNotes: String
    let scheduledDay: Date
    let dueDate: Date?
    let dueTime: Date?
    let timeModeRawValue: String
    let scheduledTime: Date?
    let daySectionRawValue: String?
    let scheduleKindRawValue: String?
    let scheduleEndDate: Date?
    let scheduleWeekdaysRawValue: String?
    let plannedDurationMinutes: Int?
    let customWorkSessionsData: Data?
    let repeatFrequencyRawValue: String?
    let repeatInterval: Int?
    let repeatEndModeRawValue: String?
    let repeatEndDate: Date?
    let repeatCount: Int?
    let completedOccurrenceDaysData: Data?
    let excludedOccurrenceDaysData: Data?
    let isCompleted: Bool
    let completedAt: Date?
    let position: Int
    let priorityRawValue: String
    let statusRawValue: String?
    let habitID: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        title: String,
        taskNotes: String,
        scheduledDay: Date,
        dueDate: Date?,
        dueTime: Date? = nil,
        timeModeRawValue: String,
        scheduledTime: Date?,
        daySectionRawValue: String?,
        scheduleKindRawValue: String? = nil,
        scheduleEndDate: Date? = nil,
        scheduleWeekdaysRawValue: String? = nil,
        plannedDurationMinutes: Int? = nil,
        customWorkSessionsData: Data? = nil,
        repeatFrequencyRawValue: String? = nil,
        repeatInterval: Int? = nil,
        repeatEndModeRawValue: String? = nil,
        repeatEndDate: Date? = nil,
        repeatCount: Int? = nil,
        completedOccurrenceDaysData: Data? = nil,
        excludedOccurrenceDaysData: Data? = nil,
        isCompleted: Bool,
        completedAt: Date?,
        position: Int,
        priorityRawValue: String,
        statusRawValue: String?,
        habitID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.taskNotes = taskNotes
        self.scheduledDay = scheduledDay
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.timeModeRawValue = timeModeRawValue
        self.scheduledTime = scheduledTime
        self.daySectionRawValue = daySectionRawValue
        self.scheduleKindRawValue = scheduleKindRawValue
        self.scheduleEndDate = scheduleEndDate
        self.scheduleWeekdaysRawValue = scheduleWeekdaysRawValue
        self.plannedDurationMinutes = plannedDurationMinutes
        self.customWorkSessionsData = customWorkSessionsData
        self.repeatFrequencyRawValue = repeatFrequencyRawValue
        self.repeatInterval = repeatInterval
        self.repeatEndModeRawValue = repeatEndModeRawValue
        self.repeatEndDate = repeatEndDate
        self.repeatCount = repeatCount
        self.completedOccurrenceDaysData = completedOccurrenceDaysData
        self.excludedOccurrenceDaysData = excludedOccurrenceDaysData
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.position = position
        self.priorityRawValue = priorityRawValue
        self.statusRawValue = statusRawValue
        self.habitID = habitID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct SinceBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archive: SinceBackupArchive

    init(archive: SinceBackupArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw SinceBackupError.unreadableFile
        }
        archive = try SinceBackupCoding.decoder.decode(SinceBackupArchive.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try SinceBackupCoding.encoder.encode(archive))
    }
}

nonisolated enum SinceBackupCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated enum SinceBackupError: LocalizedError {
    case unreadableFile
    case unsupportedVersion(Int)
    case invalidReference

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected file could not be read."
        case let .unsupportedVersion(version):
            "This backup uses unsupported format version \(version)."
        case .invalidReference:
            "The backup contains a planner task linked to a habit that is not included."
        }
    }
}
