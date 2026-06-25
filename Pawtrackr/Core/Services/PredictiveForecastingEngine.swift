import Foundation
import SwiftData
import OSLog

private let forecastLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "PredictiveForecasting")

/// Predictive engine to forecast grooming shop trends.
actor PredictiveForecastingEngine {
    private let modelContainer: ModelContainer
    private static let minimumAdvancedSampleDays = 10
    private static let recentAverageWindowDays = 14
    private static let maximumForecastDays = 366
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    func analyzeGroomingTrends(over days: Int) async -> [Date: Decimal] {
        let forecastDays = max(0, min(days, Self.maximumForecastDays))
        guard forecastDays > 0 else { return [:] }

        let container = modelContainer
        return await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Visit>(sortBy: [
                SortDescriptor(\.startedAt, order: .reverse)
            ])
            descriptor.fetchLimit = 500

            do {
                let visits = try context.fetch(descriptor)
                let samples = Self.completedRevenueSamples(from: visits)
                let average = Self.forecastDailyAverage(from: samples)
                return Self.forecastSeries(days: forecastDays, dailyAmount: average)
            } catch {
                forecastLog.error("Forecast fetch failed: \(String(describing: error), privacy: .private)")
                return Self.forecastSeries(days: forecastDays, dailyAmount: .zero)
            }
        }.value
    }

    /// Returns completed visit revenue keyed by completion day, discarding invalid dates and negative totals.
    private static func completedRevenueSamples(from visits: [Visit]) -> [Date: Decimal] {
        let calendar = Calendar.current
        var totalsByDay: [Date: Decimal] = [:]

        for visit in visits where visit.isCompleted {
            guard let endedAt = visit.endedAt else { continue }
            let total = max(Decimal.zero, visit.effectiveTotal)
            let day = calendar.startOfDay(for: endedAt)
            totalsByDay[day, default: .zero] += total
        }

        return totalsByDay
    }

    /// Calculates a finite simple moving-average fallback for stores without enough history for richer forecasting.
    private static func forecastDailyAverage(from dailyTotals: [Date: Decimal]) -> Decimal {
        guard !dailyTotals.isEmpty else { return .zero }

        let sortedTotals = dailyTotals
            .sorted { $0.key < $1.key }
            .suffix(
                dailyTotals.count < minimumAdvancedSampleDays
                    ? dailyTotals.count
                    : recentAverageWindowDays
            )
            .map(\.value)

        guard !sortedTotals.isEmpty else { return .zero }
        let total = sortedTotals.reduce(Decimal.zero, +)
        return (total / Decimal(sortedTotals.count)).roundedMoney()
    }

    /// Produces one forecast value for each future calendar day so charts always receive bounded data.
    private static func forecastSeries(days: Int, dailyAmount: Decimal) -> [Date: Decimal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return Dictionary(uniqueKeysWithValues: (1...days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (day, dailyAmount)
        })
    }
}
