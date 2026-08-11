import Combine
import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    enum AccessState: Equatable {
        case unavailable
        case notRequested
        case ready
        case failed(String)
    }

    @Published private(set) var accessState: AccessState
    @Published private(set) var stepTotals: [Date: Int] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private let healthStore: HKHealthStore
    private let calendar: Calendar
    private let usesMockStepData: Bool
    private let authorizationFlag = "SinceHealthKitAuthorizationRequested"
    private let refreshFreshnessWindow: TimeInterval = 30
    private var activeRefreshRange: DateInterval?
    private var pendingRefreshRanges: [DateInterval] = []
    private var recentRefreshes: [CompletedRefresh] = []
    private var refreshDrainTask: Task<Void, Never>?

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
        self.usesMockStepData = CommandLine.arguments.contains("--ui-testing-health-steps")

        if usesMockStepData {
            accessState = .ready
            let today = calendar.startOfDay(for: .now)
            stepTotals[today] = 6_842
        } else if !HKHealthStore.isHealthDataAvailable() {
            accessState = .unavailable
        } else if UserDefaults.standard.bool(forKey: authorizationFlag) {
            accessState = .ready
        } else {
            accessState = .notRequested
        }
    }

    var hasRequestedAccess: Bool {
        accessState != .notRequested && accessState != .unavailable
    }

    func steps(on date: Date) -> Int? {
        stepTotals[calendar.startOfDay(for: date)]
    }

    func requestStepAccess() async {
        if usesMockStepData {
            accessState = .ready
            lastUpdated = .now
            return
        }

        guard HKHealthStore.isHealthDataAvailable(), let stepType else {
            accessState = .unavailable
            return
        }

        do {
            _ = try await requestAuthorization(reading: [stepType])
            UserDefaults.standard.set(true, forKey: authorizationFlag)
            accessState = .ready
        } catch {
            accessState = .failed(error.localizedDescription)
        }
    }

    func refreshRecentDays(_ numberOfDays: Int = 90) async {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(max(1, numberOfDays) - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        await refresh(from: start, to: end)
    }

    func refreshMonth(containing date: Date) async {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return }
        await refresh(from: interval.start, to: interval.end)
    }

    func refreshDay(containing date: Date) async {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        await refresh(from: start, to: end)
    }

    func refresh(from start: Date, to end: Date) async {
        guard canRefresh, start < end else { return }

        let request = DateInterval(
            start: calendar.startOfDay(for: start),
            end: end
        )
        guard request.start < request.end else { return }

        discardExpiredRefreshes()
        guard !isFresh(request) else { return }

        if usesMockStepData {
            lastUpdated = .now
            recordCompletedRefresh(request)
            return
        }
        guard let stepType else {
            accessState = .unavailable
            return
        }

        if let activeRefreshRange,
           contains(activeRefreshRange, request),
           let refreshDrainTask {
            await refreshDrainTask.value
            return
        }

        enqueue(request)
        if let refreshDrainTask {
            await refreshDrainTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainRefreshQueue(stepType: stepType)
            self.refreshDrainTask = nil
        }
        refreshDrainTask = task
        await task.value
    }

    private func drainRefreshQueue(stepType: HKQuantityType) async {
        isRefreshing = true
        defer {
            activeRefreshRange = nil
            isRefreshing = false
        }

        while !pendingRefreshRanges.isEmpty {
            let request = pendingRefreshRanges.removeFirst()
            discardExpiredRefreshes()
            guard !isFresh(request) else { continue }
            activeRefreshRange = request

            do {
                let totals = try await queryDailyTotals(
                    type: stepType,
                    from: request.start,
                    to: request.end
                )
                stepTotals = stepTotals.filter { day, _ in
                    day < request.start || day >= request.end
                }
                stepTotals.merge(totals) { _, new in new }
                lastUpdated = .now
                accessState = .ready
                recordCompletedRefresh(request)
            } catch {
                accessState = .failed(error.localizedDescription)
                break
            }

            activeRefreshRange = nil
        }
    }

    private func enqueue(_ request: DateInterval) {
        let sorted = (pendingRefreshRanges + [request]).sorted { $0.start < $1.start }
        pendingRefreshRanges = sorted.reduce(into: []) { merged, candidate in
            guard let last = merged.last else {
                merged.append(candidate)
                return
            }

            if candidate.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, candidate.end)
                )
            } else {
                merged.append(candidate)
            }
        }
    }

    private func isFresh(_ request: DateInterval) -> Bool {
        let mergedFreshRanges = recentRefreshes
            .map(\.range)
            .sorted { $0.start < $1.start }
            .reduce(into: [DateInterval]()) { merged, candidate in
                guard let last = merged.last else {
                    merged.append(candidate)
                    return
                }

                if candidate.start <= last.end {
                    merged[merged.count - 1] = DateInterval(
                        start: last.start,
                        end: max(last.end, candidate.end)
                    )
                } else {
                    merged.append(candidate)
                }
            }

        return mergedFreshRanges.contains { contains($0, request) }
    }

    private func contains(_ container: DateInterval, _ request: DateInterval) -> Bool {
        container.start <= request.start && container.end >= request.end
    }

    private func recordCompletedRefresh(_ range: DateInterval) {
        let completedAt = Date.now
        recentRefreshes.removeAll { contains(range, $0.range) }
        recentRefreshes.append(CompletedRefresh(range: range, completedAt: completedAt))
        discardExpiredRefreshes(now: completedAt)
    }

    private func discardExpiredRefreshes(now: Date = .now) {
        recentRefreshes.removeAll {
            now.timeIntervalSince($0.completedAt) >= refreshFreshnessWindow
        }
    }

    private var stepType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .stepCount)
    }

    private var canRefresh: Bool {
        switch accessState {
        case .ready, .failed:
            return true
        case .unavailable, .notRequested:
            return false
        }
    }

    private func requestAuthorization(reading types: Set<HKObjectType>) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: types) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func queryDailyTotals(
        type: HKQuantityType,
        from start: Date,
        to end: Date
    ) async throws -> [Date: Int] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        var interval = DateComponents()
        interval.day = 1

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: interval
            )
            query.initialResultsHandler = { [calendar] _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var result: [Date: Int] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let day = calendar.startOfDay(for: statistics.startDate)
                    result[day] = Int(quantity.doubleValue(for: .count()).rounded())
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
    }
}

private struct CompletedRefresh {
    let range: DateInterval
    let completedAt: Date
}
