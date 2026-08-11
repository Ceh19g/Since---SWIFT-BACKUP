import Foundation

enum HabitMeasurementValueKind: String, Codable, CaseIterable, Identifiable {
    case wholeNumber
    case decimal
    case currency
    case durationMinutes
    case ratingFive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wholeNumber: "Whole number"
        case .decimal: "Decimal"
        case .currency: "Money"
        case .durationMinutes: "Minutes"
        case .ratingFive: "Rating from 1–5"
        }
    }

    var symbolName: String {
        switch self {
        case .wholeNumber: "number"
        case .decimal: "point.3.connected.trianglepath.dotted"
        case .currency: "dollarsign.circle"
        case .durationMinutes: "clock"
        case .ratingFive: "star"
        }
    }

    var suggestedStep: Double {
        switch self {
        case .decimal, .currency: 0.5
        case .wholeNumber, .durationMinutes, .ratingFive: 1
        }
    }

    var maximumValue: Double {
        self == .ratingFive ? 5 : 1_000_000
    }
}

enum HabitMeasurementTemplate: String, Codable, CaseIterable, Identifiable {
    case times
    case drinks
    case cigarettes
    case servings
    case pages
    case glasses
    case sessions
    case purchases
    case moneySpent
    case minutes
    case miles
    case kilometers
    case rating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .times: "Times"
        case .drinks: "Drinks"
        case .cigarettes: "Cigarettes"
        case .servings: "Servings"
        case .pages: "Pages"
        case .glasses: "Glasses"
        case .sessions: "Sessions"
        case .purchases: "Purchases"
        case .moneySpent: "Money spent"
        case .minutes: "Minutes"
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        case .rating: "Rating"
        }
    }

    var unit: String {
        switch self {
        case .times: "times"
        case .drinks: "drinks"
        case .cigarettes: "cigarettes"
        case .servings: "servings"
        case .pages: "pages"
        case .glasses: "glasses"
        case .sessions: "sessions"
        case .purchases: "purchases"
        case .moneySpent: "spent"
        case .minutes: "minutes"
        case .miles: "miles"
        case .kilometers: "kilometers"
        case .rating: "of 5"
        }
    }

    var valueKind: HabitMeasurementValueKind {
        switch self {
        case .times, .cigarettes, .pages, .glasses, .sessions, .purchases:
            .wholeNumber
        case .drinks, .servings, .miles, .kilometers:
            .decimal
        case .moneySpent:
            .currency
        case .minutes:
            .durationMinutes
        case .rating:
            .ratingFive
        }
    }

    var symbolName: String {
        switch self {
        case .times: "number.circle"
        case .drinks: "wineglass"
        case .cigarettes: "smoke"
        case .servings: "fork.knife"
        case .pages: "book.pages"
        case .glasses: "drop"
        case .sessions: "repeat.circle"
        case .purchases: "bag"
        case .moneySpent: "dollarsign.circle"
        case .minutes: "clock"
        case .miles, .kilometers: "figure.walk"
        case .rating: "star"
        }
    }

    var definition: HabitMeasurementDefinition {
        HabitMeasurementDefinition(
            sourceID: rawValue,
            name: title,
            unit: unit,
            valueKind: valueKind,
            symbolName: symbolName
        )
    }

    static func recommended(for type: HabitType) -> [HabitMeasurementTemplate] {
        switch type {
        case .abstinence, .frequency, .count, .duration:
            [.times, .drinks, .cigarettes, .moneySpent, .minutes]
        case .positiveStreak:
            [.minutes, .pages, .glasses, .sessions, .servings]
        case .event:
            [.times, .rating, .minutes, .moneySpent, .servings]
        case .sinceDate, .countdown:
            []
        }
    }
}

struct HabitMeasurementDefinition: Hashable, Identifiable {
    let sourceID: String
    let name: String
    let unit: String
    let valueKind: HabitMeasurementValueKind
    let symbolName: String

    var id: String { identityKey }

    var identityKey: String {
        [sourceID, name.lowercased(), unit.lowercased(), valueKind.rawValue]
            .joined(separator: "|")
    }

    var entryPrompt: String {
        switch valueKind {
        case .currency:
            "How much was spent?"
        case .durationMinutes:
            "How many minutes?"
        case .ratingFive:
            "What rating?"
        case .wholeNumber, .decimal:
            "How many \(unit)?"
        }
    }

    func formatted(_ value: Double) -> String {
        switch valueKind {
        case .currency:
            let code = Locale.current.currency?.identifier ?? "USD"
            return value.formatted(.currency(code: code))
        case .ratingFive:
            return "\(numberString(value)) of 5"
        case .durationMinutes:
            return "\(numberString(value)) \(value == 1 ? "minute" : "minutes")"
        case .wholeNumber, .decimal:
            return "\(numberString(value)) \(displayUnit(for: value))"
        }
    }

    func compactFormatted(_ value: Double) -> String {
        formatted(value)
    }

    private func numberString(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func displayUnit(for value: Double) -> String {
        guard value == 1,
              let template = HabitMeasurementTemplate(rawValue: sourceID) else {
            return unit
        }

        return switch template {
        case .times: "time"
        case .drinks: "drink"
        case .cigarettes: "cigarette"
        case .servings: "serving"
        case .pages: "page"
        case .glasses: "glass"
        case .sessions: "session"
        case .purchases: "purchase"
        case .minutes: "minute"
        case .miles: "mile"
        case .kilometers: "kilometer"
        case .moneySpent, .rating: unit
        }
    }
}

struct HabitMeasurementStatistics: Equatable {
    let definition: HabitMeasurementDefinition
    let total: Double
    let average: Double
    let maximum: Double
    let measuredCount: Int
    let missingCount: Int
}

enum HabitMeasurementManager {
    static let customSourceID = "custom"

    static func relevantEvents(for habit: Habit) -> [HabitEvent] {
        habit.events.filter { event in
            switch habit.type {
            case .abstinence, .frequency, .count, .duration:
                event.kind == .slip
            case .positiveStreak, .event:
                event.kind == .completed
            case .sinceDate, .countdown:
                false
            }
        }
    }

    static func applyDefaultMeasurement(to event: HabitEvent, for habit: Habit) {
        guard let definition = habit.measurementDefinition,
              let value = habit.measurementDefaultValue,
              value > 0 else { return }
        apply(value: value, definition: definition, to: event)
    }

    static func initialEntryValue(for habit: Habit) -> Double? {
        guard let definition = habit.measurementDefinition else { return nil }
        if let defaultValue = habit.measurementDefaultValue, defaultValue > 0 {
            return min(defaultValue, definition.valueKind.maximumValue)
        }
        return definition.valueKind == .ratingFive ? 3 : 1
    }

    static func apply(
        value: Double?,
        definition: HabitMeasurementDefinition?,
        to event: HabitEvent
    ) {
        guard let value, value > 0, let definition else {
            event.measurementValue = nil
            event.measurementSourceID = nil
            event.measurementName = nil
            event.measurementUnit = nil
            event.measurementValueKindRawValue = nil
            return
        }

        event.measurementValue = min(value, definition.valueKind.maximumValue)
        event.measurementSourceID = definition.sourceID
        event.measurementName = definition.name
        event.measurementUnit = definition.unit
        event.measurementValueKindRawValue = definition.valueKind.rawValue
    }

    static func statistics(
        for habit: Habit,
        from start: Date? = nil,
        to endExclusive: Date? = nil
    ) -> HabitMeasurementStatistics? {
        guard let definition = habit.measurementDefinition else { return nil }
        let events = relevantEvents(for: habit).filter { event in
            (start.map { event.occurredAt >= $0 } ?? true)
                && (endExclusive.map { event.occurredAt < $0 } ?? true)
        }
        let matchingValues = events.compactMap { event -> Double? in
            guard let value = event.measurementValue else { return nil }
            guard let snapshot = event.measurementDefinition else { return nil }
            return snapshot.identityKey == definition.identityKey ? value : nil
        }
        guard !matchingValues.isEmpty else { return nil }
        let missing = events.filter { $0.measurementValue == nil }.count
        let total = matchingValues.reduce(0, +)
        return HabitMeasurementStatistics(
            definition: definition,
            total: total,
            average: total / Double(matchingValues.count),
            maximum: matchingValues.max() ?? 0,
            measuredCount: matchingValues.count,
            missingCount: missing
        )
    }

    static func customDefinitions(from habits: [Habit]) -> [HabitMeasurementDefinition] {
        var seen = Set<String>()
        return habits
            .compactMap(\.measurementDefinition)
            .filter { $0.sourceID == customSourceID }
            .filter { seen.insert($0.identityKey).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func summary(for events: [HabitEvent]) -> String? {
        let measured = events.compactMap { event -> (HabitMeasurementDefinition, Double)? in
            guard let definition = event.measurementDefinition,
                  let value = event.measurementValue else { return nil }
            return (definition, value)
        }
        guard let first = measured.first,
              measured.allSatisfy({ $0.0.identityKey == first.0.identityKey })
        else { return nil }
        return first.0.compactFormatted(measured.reduce(0) { $0 + $1.1 })
    }
}

extension Habit {
    var supportsManualMeasurement: Bool {
        guard !isHealthPowered else { return false }
        switch type {
        case .abstinence, .positiveStreak, .event, .frequency, .count, .duration:
            return true
        case .sinceDate, .countdown:
            return false
        }
    }

    var measurementDefinition: HabitMeasurementDefinition? {
        guard supportsManualMeasurement, let rawValue = measurementTemplateRawValue else { return nil }
        if let template = HabitMeasurementTemplate(rawValue: rawValue) {
            return template.definition
        }
        guard rawValue == HabitMeasurementManager.customSourceID,
              let name = measurementCustomName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let unit = measurementCustomUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !unit.isEmpty,
              let kind = measurementCustomValueKindRawValue.flatMap(HabitMeasurementValueKind.init(rawValue:))
        else { return nil }
        return HabitMeasurementDefinition(
            sourceID: HabitMeasurementManager.customSourceID,
            name: name,
            unit: unit,
            valueKind: kind,
            symbolName: kind.symbolName
        )
    }
}

extension HabitEvent {
    var measurementDefinition: HabitMeasurementDefinition? {
        guard let sourceID = measurementSourceID,
              let name = measurementName,
              let unit = measurementUnit,
              let kind = measurementValueKindRawValue.flatMap(HabitMeasurementValueKind.init(rawValue:))
        else { return nil }
        return HabitMeasurementDefinition(
            sourceID: sourceID,
            name: name,
            unit: unit,
            valueKind: kind,
            symbolName: kind.symbolName
        )
    }

    var formattedMeasurement: String? {
        guard let measurementValue, let measurementDefinition else { return nil }
        return measurementDefinition.formatted(measurementValue)
    }
}
