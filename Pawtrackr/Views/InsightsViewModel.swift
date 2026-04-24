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
    private(set) var totalVisitsInPeriod: Int = 0
    private(set) var activePeriodDays: Int = 0
    private(set) var isLoading: Bool = false
    var appError: AppError? = nil

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
        appError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.apply(bounds: bounds)
            } catch {
                self.logger.error("Insights refresh failed: \(error)")
                self.appError = .database(error.localizedDescription)
            }
        }
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
            return (today, calendar.date(byAdding: .day, value: 1, to: today))
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            return (yesterday, today)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: today)!
            return (start, calendar.date(byAdding: .day, value: 1, to: today))
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today)!
            return (start, calendar.date(byAdding: .day, value: 1, to: today))
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            return (start, calendar.date(byAdding: .day, value: 1, to: today))
        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today))!
            return (start, calendar.date(byAdding: .day, value: 1, to: today))
        case .custom:
            return (customStart, customEnd)
        }
    }

    private func apply(bounds: (start: Date?, endExclusive: Date?)) throws {
        defer { isLoading = false }
        
        let (daySummaries, serviceSummaries) = try fetchData(bounds: bounds)
        
        computeOverallStats(daySummaries: daySummaries, bounds: bounds)
        
        buildChartData(daySummaries: daySummaries, bounds: bounds)
        
        self.serviceLeaders = computeTopServices(summaries: serviceSummaries)
        
        updateHeadlineDailyRevenue()
    }

    private func fetchData(bounds: (start: Date?, endExclusive: Date?)) throws -> (daySummaries: [DaySummary], serviceSummaries: [ServiceDaySummary]) {
        let daySummaries = try fetchDaySummaries(bounds: bounds)
        let serviceSummaries = try fetchServiceDaySummaries(bounds: bounds)
        return (daySummaries, serviceSummaries)
    }

    private func computeOverallStats(daySummaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) {
        let totalVisits = daySummaries.reduce(0) { $0 + $1.visitCount }
        let totalRev = daySummaries.reduce(Decimal.zero) { $0 + $1.revenue }
        let periodDays = daysInRange(bounds)
        
        self.totalVisitsInPeriod = totalVisits
        self.totalRevenue = totalRev
        self.activePeriodDays = periodDays
    }

    private func buildChartData(daySummaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) {
        self.revenueSeries = buildRevenueSeries(summaries: daySummaries, bounds: bounds)
        self.revenueMovingAverage = buildMovingAverage(for: revenueSeries, window: min(7, max(3, revenueSeries.count)))
    }
    
    private func fetchDaySummaries(bounds: (start: Date?, endExclusive: Date?)) throws -> [DaySummary] {
        // SwiftData predicates don't support capturing tuple members, so fetch all and filter in memory
        let descriptor = FetchDescriptor<DaySummary>(sortBy: [SortDescriptor(\.day)])
        let all = try modelContext.fetch(descriptor)

        let startDate = bounds.start ?? .distantPast
        let endDate = bounds.endExclusive ?? .distantFuture

        return all.filter { $0.day >= startDate && $0.day < endDate }
    }

    private func fetchServiceDaySummaries(bounds: (start: Date?, endExclusive: Date?)) throws -> [ServiceDaySummary] {
        // SwiftData predicates don't support capturing tuple members, so fetch all and filter in memory
        let descriptor = FetchDescriptor<ServiceDaySummary>()
        let all = try modelContext.fetch(descriptor)

        let startDate = bounds.start ?? .distantPast
        let endDate = bounds.endExclusive ?? .distantFuture

        return all.filter { $0.day >= startDate && $0.day < endDate }
    }

    private func fetchVisits(bounds: (start: Date?, endExclusive: Date?)) throws -> [Visit] {
        // SwiftData predicates don't support capturing tuple members, so fetch all and filter in memory
        let descriptor = FetchDescriptor<Visit>()
        let all = try modelContext.fetch(descriptor)

        let startDate = bounds.start ?? .distantPast
        let endDate = bounds.endExclusive ?? .distantFuture

        return all.filter { visit in
            guard let endedAt = visit.endedAt else { return false }
            return endedAt >= startDate && endedAt < endDate
        }
    }
    
    private func daysInRange(_ bounds: (start: Date?, endExclusive: Date?)) -> Int {
        guard let start = bounds.start, let endExclusive = bounds.endExclusive else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: start, to: endExclusive).day ?? 0)
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
        let predicate = #Predicate<DaySummary> { $0.day == targetDay }
        let descriptor = FetchDescriptor<DaySummary>(predicate: predicate)
        do {
            let summary = try modelContext.fetch(descriptor).first
            return summary?.revenue ?? .zero
        } catch {
            logger.error("Insights daily summary fetch failed for \(targetDay): \(String(describing: error))")
            return .zero
        }
    }
}
