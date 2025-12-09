import SwiftUI
import SwiftData
import Combine
import OSLog

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - Nested Types

    struct RevenuePoint: Identifiable {
        let date: Date
        let amount: Decimal
        var id: Date { date }
        var amountDouble: Double { (amount as NSDecimalNumber).doubleValue }
    }

    struct CountRow: Identifiable {
        let name: String
        let count: Int
        let rank: Int
        var id: String { name }
        var countString: String { "\(count)x" }
    }

    struct ServiceRevenueRow: Identifiable {
        let name: String
        let revenue: Decimal
        let share: Double
        let rank: Int
        var id: String { name }
        @MainActor var revenueString: String { revenue.moneyString }
        @MainActor var shareString: String { Formatters.percentString(share, showSign: false) ?? "0%" }
    }

    struct TopClientRow: Identifiable {
        let clientName: String
        let visitCount: Int
        let totalSpent: Decimal
        let favoriteService: String?
        let rank: Int
        var id: String { clientName }
        @MainActor var totalSpentString: String { totalSpent.moneyString }
    }

    enum Scope: CaseIterable, Identifiable {
        case today
        case yesterday
        case last7Days
        case last30Days
        case thisMonth
        case yearToDate
        case custom

        var id: String { title }

        var title: String {
            switch self {
            case .today:
                return NSLocalizedString("insights.scope.today", comment: "Insights scope: today")
            case .yesterday:
                return NSLocalizedString("insights.scope.yesterday", comment: "Insights scope: yesterday")
            case .last7Days:
                return NSLocalizedString("7D", comment: "Insights scope: last 7 days")
            case .last30Days:
                return NSLocalizedString("30D", comment: "Insights scope: last 30 days")
            case .thisMonth:
                return NSLocalizedString("MTD", comment: "Insights scope: month to date")
            case .yearToDate:
                return NSLocalizedString("YTD", comment: "Insights scope: year to date")
            case .custom:
                return NSLocalizedString("Custom", comment: "Insights scope: custom range")
            }
        }

        var displayDescription: String {
            switch self {
            case .today:
                return NSLocalizedString("Today's Revenue", comment: "")
            case .yesterday:
                return NSLocalizedString("Yesterday's Revenue", comment: "")
            case .last7Days:
                return NSLocalizedString("Last 7 Days Revenue", comment: "")
            case .last30Days:
                return NSLocalizedString("Last 30 Days Revenue", comment: "")
            case .thisMonth:
                return NSLocalizedString("Month to Date Revenue", comment: "")
            case .yearToDate:
                return NSLocalizedString("Year to Date Revenue", comment: "")
            case .custom:
                return NSLocalizedString("Custom Period Revenue", comment: "")
            }
        }
    }

    // MARK: - Published state

    var scope: Scope = .today { didSet { scopeDidChange(oldValue: oldValue) } }
    var customDraftStart: Date
    var customDraftEnd: Date

    private(set) var revenueSeries: [RevenuePoint] = []
    private(set) var revenueMovingAverage: [RevenuePoint] = []
    private(set) var totalRevenue: Decimal = .zero
    @MainActor var totalRevenueString: String { totalRevenue.moneyString }
    private(set) var revenueToday: Decimal = .zero
    private(set) var revenueYesterday: Decimal = .zero
    @MainActor var revenueTodayString: String { revenueToday.moneyString }
    @MainActor var revenueYesterdayString: String { revenueYesterday.moneyString }
    private(set) var serviceLeaders: [CountRow] = []
    private(set) var topClients: [TopClientRow] = []
    private(set) var totalVisitsInPeriod: Int = 0
    private(set) var averagePerVisit: Decimal = .zero
    @MainActor var averagePerVisitString: String { averagePerVisit.moneyString }
    private(set) var averageDailyRevenue: Decimal = .zero
    @MainActor var averageDailyRevenueString: String { averageDailyRevenue.moneyString }
    private(set) var revenueChangeAmount: Decimal = .zero
    private(set) var revenueChangePercent: Double?
    @MainActor var revenueChangeAmountString: String { revenueChangeAmount.moneyString }
    @MainActor var revenueChangePercentString: String { Formatters.percentString(revenueChangePercent) ?? "—" }
    @MainActor var revenueChangeComparisonLabel: String {
        let bounds = comparisonPeriodBounds(for: scope, currentBounds: activeBounds)
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else {
            return NSLocalizedString("vs. Previous Period", comment: "Label for revenue change comparison against previous period")
        }

        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        let formatter = Formatters.dateOnly

        switch scope {
        case .thisMonth:
            return NSLocalizedString("vs. Previous Month", comment: "Label for revenue change comparison")
        case .yearToDate:
            return NSLocalizedString("vs. Previous Year", comment: "Label for revenue change comparison")
        default:
            let formattedStart = formatter.string(from: start)
            if Calendar.current.isDate(start, inSameDayAs: inclusiveEnd) {
                return NSLocalizedString("vs. \(formattedStart)", comment: "Label for revenue change comparison against a single day")
            }
        let formattedEnd = formatter.string(from: inclusiveEnd)
        return NSLocalizedString("vs. \(formattedStart) – \(formattedEnd)", comment: "Label for revenue change comparison against a date range")
        }
    }
    private(set) var bestRevenueDay: RevenuePoint?
    private(set) var activePeriodDays: Int = 0
    private(set) var topRevenueServices: [ServiceRevenueRow] = []
    @MainActor var bestRevenueDayLabel: String? {
        guard let bestRevenueDay else { return nil }
        return "\(Formatters.dateOnly.string(from: bestRevenueDay.date)) • \(bestRevenueDay.amount.moneyString)"
    }
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // MARK: - Private state

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "insights")
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var customAppliedStart: Date?
    @ObservationIgnored private var customAppliedEndExclusive: Date?
    

    // MARK: - Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Main dates
        let mainDraftEnd = today
        let mainDraftStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        self.customDraftEnd = mainDraftEnd
        self.customDraftStart = mainDraftStart
        self.customAppliedStart = mainDraftStart
        self.customAppliedEndExclusive = calendar.date(byAdding: .day, value: 1, to: mainDraftEnd)

        NotificationCenter.default.publisher(for: .visitDidComplete)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    // MARK: - Intent

    func applyCustomDates() {
        guard customDraftEnd >= customDraftStart else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: customDraftStart)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customDraftEnd))
        customAppliedStart = start
        customAppliedEndExclusive = endExclusive
        if scope != .custom {
            scope = .custom
        } else {
            refresh()
        }
    }

    func refresh() {
        let bounds = dateBounds(for: scope, customStart: customAppliedStart, customEnd: customAppliedEndExclusive)
        isLoading = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.apply(bounds: bounds)
            } catch {
                self.logger.error("Insights refresh failed: \(error)")
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private func scopeDidChange(oldValue: Scope) {
        if scope == .custom, customAppliedStart == nil {
            applyCustomDates()
        } else {
            refresh()
        }
    }

    var activeBounds: (start: Date?, endExclusive: Date?) {
        dateBounds(for: scope, customStart: customAppliedStart, customEnd: customAppliedEndExclusive)
    }

    @MainActor
    var activeRangeLabel: String {
        let bounds = activeBounds
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else { return scope.title }
        let calendar = Calendar.current
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        let formatter = Formatters.dateOnly
        if calendar.isDate(start, inSameDayAs: inclusiveEnd) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) – \(formatter.string(from: inclusiveEnd))"
    }

    private func dateBounds(for scope: Scope, customStart: Date?, customEnd: Date?) -> (start: Date?, endExclusive: Date?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch scope {
        case .today:
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: today)
            return (today, endExclusive)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: today)
            return (start, today)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: today)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: today)
            return (start, endExclusive)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: today)
            return (start, endExclusive)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: today)
            guard let start = calendar.date(from: comps) else {
                return (nil, nil)
            }
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: today)
            return (start, endExclusive)
        case .yearToDate:
            let comps = calendar.dateComponents([.year], from: today)
            guard let start = calendar.date(from: comps) else {
                return (nil, nil)
            }
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: today)
            return (start, endExclusive)
        case .custom:
            return (customStart, customEnd)
        }
    }

    private func apply(bounds: (start: Date?, endExclusive: Date?)) throws {
        defer { isLoading = false }
        
        // 1. Fetch aggregated data
        let daySummaries = try fetchDaySummaries(bounds: bounds)
        let serviceSummaries = try fetchServiceDaySummaries(bounds: bounds)
        
        // 2. Compute overall stats
        let totalVisits = daySummaries.reduce(0) { $0 + $1.visitCount }
        let totalRev = daySummaries.reduce(Decimal.zero) { $0 + $1.revenue }
        let periodDays = daysInRange(bounds)
        
        self.totalVisitsInPeriod = totalVisits
        self.totalRevenue = totalRev
        self.averagePerVisit = totalVisits > 0 ? (totalRev / Decimal(totalVisits)).roundedMoney() : .zero
        self.averageDailyRevenue = periodDays > 0 ? (totalRev / Decimal(periodDays)).roundedMoney() : .zero
        self.activePeriodDays = periodDays
        
        // 3. Build data for charts and lists
        self.revenueSeries = buildRevenueSeries(summaries: daySummaries, bounds: bounds)
        self.revenueMovingAverage = buildMovingAverage(for: revenueSeries, window: min(7, max(3, revenueSeries.count)))
        self.bestRevenueDay = revenueSeries.max(by: { $0.amount < $1.amount })
        self.serviceLeaders = computeTopServices(summaries: serviceSummaries)
        
        // 3b. Compare against a smarter, context-aware period.
        let comparisonBounds = comparisonPeriodBounds(for: scope, currentBounds: bounds)
        if let comparisonStart = comparisonBounds.start, let comparisonEnd = comparisonBounds.endExclusive, comparisonStart < comparisonEnd {
            let previousSummaries = try fetchDaySummaries(bounds: comparisonBounds)
            let previousTotal = previousSummaries.reduce(Decimal.zero) { $0 + $1.revenue }
            computeRevenueDelta(current: totalRev, previous: previousTotal)
        } else {
            revenueChangeAmount = .zero
            revenueChangePercent = nil
        }
        
        // 4. Update headline numbers
        updateHeadlineDailyRevenue()
        
        // 5. Fetch top clients and revenue by service (requires visits)
        let visits = try fetchVisits(bounds: bounds)
        self.topClients = Self.computeTopClients(visits: visits)
        self.topRevenueServices = computeTopRevenueServices(visits: visits, totalRevenue: totalRev)
    }
    
    private func fetchDaySummaries(bounds: (start: Date?, endExclusive: Date?)) throws -> [DaySummary] {
        // Fetch all and filter in memory to avoid SwiftData predicate capture issues
        let descriptor = FetchDescriptor<DaySummary>(sortBy: [SortDescriptor(\.day)])
        let all = try modelContext.fetch(descriptor)

        let start = bounds.start ?? .distantPast
        let end = bounds.endExclusive ?? .distantFuture

        return all.filter { $0.day >= start && $0.day < end }
    }

    private func fetchServiceDaySummaries(bounds: (start: Date?, endExclusive: Date?)) throws -> [ServiceDaySummary] {
        // Fetch all and filter in memory to avoid SwiftData predicate capture issues
        let descriptor = FetchDescriptor<ServiceDaySummary>()
        let all = try modelContext.fetch(descriptor)

        let start = bounds.start ?? .distantPast
        let end = bounds.endExclusive ?? .distantFuture

        return all.filter { $0.day >= start && $0.day < end }
    }

    private func fetchVisits(bounds: (start: Date?, endExclusive: Date?)) throws -> [Visit] {
        // Fetch all completed visits and filter in memory to avoid SwiftData predicate capture issues
        let descriptor = FetchDescriptor<Visit>()
        let all = try modelContext.fetch(descriptor)

        let start = bounds.start ?? .distantPast
        let end = bounds.endExclusive ?? .distantFuture

        return all.filter { visit in
            guard let endedAt = visit.endedAt else { return false }
            return endedAt >= start && endedAt < end
        }
    }
    
    private func daysInRange(_ bounds: (start: Date?, endExclusive: Date?)) -> Int {
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: start, to: endExclusive).day ?? 0)
    }
    
    private func comparisonPeriodBounds(for scope: Scope, currentBounds: (start: Date?, endExclusive: Date?)) -> (start: Date?, endExclusive: Date?) {
        let cal = Calendar.current
        guard let start = currentBounds.start, let endExclusive = currentBounds.endExclusive else { return (nil, nil) }

        switch scope {
        case .thisMonth:
            // Compare to the same date range in the previous month.
            guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: start),
                  let prevMonthEnd = cal.date(byAdding: .month, value: -1, to: endExclusive) else {
                return (nil, nil)
            }
            return (prevMonthStart, prevMonthEnd)

        case .yearToDate:
            // Compare to the same date range in the previous year.
            guard let prevYearStart = cal.date(byAdding: .year, value: -1, to: start),
                  let prevYearEnd = cal.date(byAdding: .year, value: -1, to: endExclusive) else {
                return (nil, nil)
            }
            return (prevYearStart, prevYearEnd)

        case .today, .yesterday, .last7Days, .last30Days, .custom:
            // Default behavior: compare to the immediately preceding period of the same length.
            let lengthInDays = cal.dateComponents([.day], from: start, to: endExclusive).day ?? 0
            guard lengthInDays > 0,
                  let previousStart = cal.date(byAdding: .day, value: -lengthInDays, to: start) else {
                return (nil, nil)
            }
            return (previousStart, start)
        }
    }

    private func buildRevenueSeries(summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        let periodDays = daysInRange(bounds)

        if periodDays <= 90 {
            return buildRevenueSeriesByDay(summaries: summaries, bounds: bounds)
        } else if periodDays <= 365 {
            return buildRevenueSeriesByWeek(summaries: summaries, bounds: bounds)
        } else {
            return buildRevenueSeriesByMonth(summaries: summaries, bounds: bounds)
        }
    }

    private func buildRevenueSeriesByDay(summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        guard let endExclusive = bounds.endExclusive else { return [] }
        let calendar = Calendar.current

        // Fast lookup of revenue by day
        let bucket = summaries.reduce(into: [Date: Decimal]()) { $0[$1.day] = $1.revenue }

        guard let startDate = bounds.start.map({ calendar.startOfDay(for: $0) }) ?? summaries.first?.day else {
            return []
        }

        var points: [RevenuePoint] = []
        var cursor = startDate
        while cursor < endExclusive {
            let amount = bucket[cursor] ?? .zero
            points.append(RevenuePoint(date: cursor, amount: amount.roundedMoney()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private func buildRevenueSeriesByWeek(summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else { return [] }
        let calendar = Calendar.current

        // Bucket revenue by the start of the week
        let weeklyBuckets = summaries.reduce(into: [Date: Decimal]()) { result, summary in
            guard let weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: summary.day)) else { return }
            result[weekStartDate, default: .zero] += summary.revenue
        }

        var points: [RevenuePoint] = []
        guard let iterStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) else { return [] }
        var cursor = iterStart
        while cursor < endExclusive {
            let amount = weeklyBuckets[cursor] ?? .zero
            points.append(RevenuePoint(date: cursor, amount: amount.roundedMoney()))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private func buildRevenueSeriesByMonth(summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else { return [] }
        let calendar = Calendar.current

        // Bucket revenue by the start of the month
        let monthlyBuckets = summaries.reduce(into: [Date: Decimal]()) { result, summary in
            guard let monthStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: summary.day)) else { return }
            result[monthStartDate, default: .zero] += summary.revenue
        }

        var points: [RevenuePoint] = []
        guard let iterStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) else { return [] }
        var cursor = iterStart
        while cursor < endExclusive {
            let amount = monthlyBuckets[cursor] ?? .zero
            points.append(RevenuePoint(date: cursor, amount: amount.roundedMoney()))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }
    
    private func buildMovingAverage(for points: [RevenuePoint], window: Int) -> [RevenuePoint] {
        guard window > 1, points.count >= window else { return [] }
        var result: [RevenuePoint] = []
        var running: Decimal = .zero

        for (index, point) in points.enumerated() {
            running += point.amount
            if index >= window {
                running -= points[index - window].amount
            }
            if index >= window - 1 {
                let avg = (running / Decimal(window)).roundedMoney()
                result.append(RevenuePoint(date: point.date, amount: avg))
            }
        }

        return result
    }
    
    private func computeRevenueDelta(current: Decimal, previous: Decimal) {
        revenueChangeAmount = (current - previous).roundedMoney()
        if previous > .zero {
            let delta = (current - previous) / previous
            revenueChangePercent = (delta as NSDecimalNumber).doubleValue
        } else {
            revenueChangePercent = nil
        }
    }

    private func computeTopServices(summaries: [ServiceDaySummary]) -> [CountRow] {
        let serviceCounts = summaries.reduce(into: [String: Int]()) { result, summary in
            result[summary.serviceName, default: 0] += summary.count
        }
        
        let sorted = serviceCounts.sorted(by: {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        })
        
        return sorted
            .prefix(10)
            .enumerated()
            .map { index, pair in CountRow(name: pair.key, count: pair.value, rank: index + 1) }
    }
    
    private func computeTopRevenueServices(visits: [Visit], totalRevenue: Decimal) -> [ServiceRevenueRow] {
        guard totalRevenue > .zero else { return [] }

        var revenueByService: [String: Decimal] = [:]

        for visit in visits {
            for item in visit.items {
                let name = (item.service?.name ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let lineTotal = (item.unitPrice * Decimal(item.quantity)).roundedMoney()
                revenueByService[name, default: .zero] = revenueByService[name, default: .zero] + lineTotal
            }
        }

        let sorted = revenueByService.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }

        return sorted
            .prefix(5)
            .enumerated()
            .map { idx, pair in
                let shareDecimal = pair.value / totalRevenue
                let shareDouble = (shareDecimal as NSDecimalNumber).doubleValue
                return ServiceRevenueRow(name: pair.key, revenue: pair.value, share: shareDouble, rank: idx + 1)
            }
    }
    
    private static func computeTopClients(visits: [Visit]) -> [TopClientRow] {
        guard !visits.isEmpty else { return [] }

        // Group visits by client name
        struct ClientStats {
            var visitCount: Int = 0
            var totalSpent: Decimal = .zero
            var serviceCounts: [String: Int] = [:]
        }

        var clientStats: [String: ClientStats] = [:]

        for visit in visits {
            guard let clientName = visit.pet?.owner?.fullName, !clientName.isEmpty else { continue }

            var stats = clientStats[clientName] ?? ClientStats()
            stats.visitCount += 1
            stats.totalSpent = stats.totalSpent +~ visit.total

            // Count services for this client
            for item in visit.items {
                let serviceName = (item.service?.name ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !serviceName.isEmpty else { continue }
                stats.serviceCounts[serviceName, default: 0] += 1
            }

            clientStats[clientName] = stats
        }

        // Sort by total spent (descending), then by visit count
        let sorted = clientStats.sorted { lhs, rhs in
            if lhs.value.totalSpent != rhs.value.totalSpent {
                return lhs.value.totalSpent > rhs.value.totalSpent
            }
            return lhs.value.visitCount > rhs.value.visitCount
        }

        return sorted
            .prefix(5)
            .enumerated()
            .map { index, pair in
                // Find the favorite service (most used by this client)
                let favoriteService = pair.value.serviceCounts
                    .max(by: { $0.value < $1.value })?
                    .key

                return TopClientRow(
                    clientName: pair.key,
                    visitCount: pair.value.visitCount,
                    totalSpent: pair.value.totalSpent,
                    favoriteService: favoriteService,
                    rank: index + 1
                )
            }
    }

    private func updateHeadlineDailyRevenue() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        revenueToday = revenueForDay(today)
        revenueYesterday = revenueForDay(yesterday)
    }

    private func revenueForDay(_ day: Date) -> Decimal {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: day)

        // Fetch all and filter in memory to avoid SwiftData predicate capture issues
        let desc = FetchDescriptor<DaySummary>()
        do {
            let all = try modelContext.fetch(desc)
            let summary = all.first { calendar.isDate($0.day, inSameDayAs: targetDay) }
            return summary?.revenue ?? .zero
        } catch {
            logger.error("Insights daily summary fetch failed for \(targetDay): \(String(describing: error))")
            return .zero
        }
    }
}
