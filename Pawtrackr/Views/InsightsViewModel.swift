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
    }

    // MARK: - Published state

    var scope: Scope = .last30Days { didSet { scopeDidChange(oldValue: oldValue) } }
    var customDraftStart: Date
    var customDraftEnd: Date

    private(set) var revenueSeries: [RevenuePoint] = []
    private(set) var totalRevenue: Decimal = .zero
    @MainActor var totalRevenueString: String { totalRevenue.moneyString }
    private(set) var revenueToday: Decimal = .zero
    private(set) var revenueYesterday: Decimal = .zero
    @MainActor var revenueTodayString: String { revenueToday.moneyString }
    @MainActor var revenueYesterdayString: String { revenueYesterday.moneyString }
    private(set) var serviceLeaders: [CountRow] = []
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
            let visits = fetchVisits(bounds: bounds)
            self.apply(visits: visits, bounds: bounds)
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

    private func apply(visits: [Visit], bounds: (start: Date?, endExclusive: Date?)) {
        defer { isLoading = false }
        serviceLeaders = Self.computeTopServices(visits: visits)
        let series = Self.buildRevenueSeries(visits: visits, bounds: bounds)
        self.revenueSeries = series
        self.totalRevenue = series.reduce(Decimal.zero) { $0 + $1.amount }
        updateHeadlineDailyRevenue()
    }

    private func fetchVisits(bounds: (start: Date?, endExclusive: Date?)) -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(
            predicate: Self.makePredicate(start: bounds.start, endExclusive: bounds.endExclusive),
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Insights fetchVisits failed: \(String(describing: error))")
            return []
        }
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
            guard let start = calendar.date(from: comps),
                  let endExclusive = calendar.date(byAdding: .month, value: 1, to: start) else {
                return (nil, nil)
            }
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

    private static func makePredicate(start: Date?, endExclusive: Date?) -> Predicate<Visit> {
        let lowerBound = start ?? Date.distantPast
        let upperBound = endExclusive ?? Date.distantFuture
        return #Predicate<Visit> { visit in
            visit.endedAt != nil && visit.endedAt! >= lowerBound && visit.endedAt! < upperBound
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
        let start = calendar.startOfDay(for: day)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: start) else { return .zero }

        // Use visits as the source of truth; fall back to payments if there are no completed visits.
        let visitDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { visit in
                visit.endedAt != nil && visit.endedAt! >= start && visit.endedAt! < endExclusive
            }
        )
        let visits: [Visit]
        do {
            visits = try modelContext.fetch(visitDesc)
        } catch {
            logger.error("Insights daily visit fetch failed for \(start): \(String(describing: error))")
            visits = []
        }
        let visitRevenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }
        if visitRevenue > .zero { return visitRevenue.roundedMoney() }

        let paymentDesc = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.paidAt >= start && $0.paidAt < endExclusive }
        )
        let payments: [Payment]
        do {
            payments = try modelContext.fetch(paymentDesc)
        } catch {
            logger.error("Insights daily payment fetch failed for \(start): \(String(describing: error))")
            payments = []
        }
        let paymentRevenue = payments.reduce(Decimal.zero) { $0 +~ $1.amount }
        return paymentRevenue.roundedMoney()
    }

    private static func computeTopServices(visits: [Visit]) -> [CountRow] {
        guard !visits.isEmpty else { return [] }
        var serviceCounts: [String: Int] = [:]

        for visit in visits {
            for item in visit.items {
                let name = (item.service?.name ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let quantity = max(1, item.quantity)
                serviceCounts[name, default: 0] += quantity
            }
        }

        return serviceCounts
            .sorted(by: Self.sortCounts)
            .prefix(5)
            .map { CountRow(name: $0.key, count: $0.value) }
    }

    private static func buildRevenueSeries(visits: [Visit], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        guard !visits.isEmpty else { return [] }
        let calendar = Calendar.current
        var bucket: [Date: Decimal] = [:]
        for visit in visits {
            let day = calendar.startOfDay(for: visit.endedAt ?? visit.startedAt)
            bucket[day, default: .zero] = bucket[day, default: .zero] +~ visit.total
        }

        let sortedDays = bucket.keys.sorted()
        guard let firstDay = sortedDays.first else { return [] }
        let start = bounds.start.map { calendar.startOfDay(for: $0) } ?? firstDay
        let endExclusive = bounds.endExclusive ?? calendar.date(byAdding: .day, value: 1, to: (sortedDays.last ?? start))

        guard let endExclusive else { return bucket.keys.sorted().map { RevenuePoint(date: $0, amount: bucket[$0] ?? .zero) } }

        var points: [RevenuePoint] = []
        var cursor = start
        while cursor < endExclusive {
            let amount = bucket[cursor] ?? .zero
            points.append(RevenuePoint(date: cursor, amount: amount.roundedMoney()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private static func sortCounts(_ lhs: (key: String, value: Int), _ rhs: (key: String, value: Int)) -> Bool {
        if lhs.value == rhs.value {
            return lhs.key < rhs.key
        }
        return lhs.value > rhs.value
    }
}
