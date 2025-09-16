
import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

@Observable
@MainActor
final class InsightsViewModel {
    // State
    var scope: Scope = .week { didSet { fetchAndProcessData() } }
    var customStartDate: Date = .now.addingTimeInterval(-7*24*60*60)
    var customEndDate: Date = .now
    var customDraftStart: Date = .now.addingTimeInterval(-7*24*60*60)
    var customDraftEnd: Date = .now
    var configuration: AnalyticsConfiguration = .default {
        didSet {
            guard configuration != oldValue else { return }
            fetchAndProcessData()
        }
    }

    // Outputs
    private(set) var kpis: KpiSet = .empty
    private(set) var metricTiles: [MetricTile] = []
    #if canImport(Charts)
    private(set) var revenueSeries: [RevenuePoint] = []
    #endif
    private(set) var serviceLeaders: [ServiceLeader] = []
    private(set) var packageLeaders: [PackageLeader] = []
    private(set) var categoryTotals: [CategoryTotal] = []
    var isLoading: Bool = false

    // Internal
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        NotificationCenter.default.addObserver(forName: .visitDidComplete, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if let payload = note.visitDidCompletePayload,
               self.shouldIgnore(payload: payload) {
                return
            }
            self.fetchAndProcessData()
        }
        fetchAndProcessData()
    }

    func fetchAndProcessData() {
        isLoading = true
        let (start, end) = dateRange(for: scope)

        // Day summaries for revenue + visits
        let dayPred = #Predicate<DaySummary> { s in (start == nil || s.day >= start!) && (end == nil || s.day < end!) }
        let dayDesc = FetchDescriptor<DaySummary>(predicate: dayPred, sortBy: [SortDescriptor(\.day, order: .forward)])
        let days = (try? modelContext.fetch(dayDesc)) ?? []

        // Aggregated services
        var svcCounts: [String:Int] = [:]
        let svcPred = #Predicate<ServiceDaySummary> { s in (start == nil || s.day >= start!) && (end == nil || s.day < end!) }
        if let svcRows = try? modelContext.fetch(FetchDescriptor<ServiceDaySummary>(predicate: svcPred)) {
            for r in svcRows { svcCounts[r.serviceName, default: 0] += r.count }
        }
        // Aggregated categories
        var catCounts: [String:Int] = [:]
        let catPred = #Predicate<CategoryDaySummary> { s in (start == nil || s.day >= start!) && (end == nil || s.day < end!) }
        if let catRows = try? modelContext.fetch(FetchDescriptor<CategoryDaySummary>(predicate: catPred)) {
            for r in catRows { catCounts[r.categoryRaw, default: 0] += r.count }
        }

        // Apply results
        let totalRevenue = days.reduce(Decimal.zero) { $0 + $1.revenue }
        let totalCount = days.reduce(0) { $0 + $1.visitCount }
        let metrics = configuration.orderedMetrics

        var avgDurationString = "—"
        if metrics.contains(.averageDuration) {
            let visitDescriptor = FetchDescriptor<Visit>(predicate: makeVisitPredicate(start: start, end: end))
            if let visits = try? modelContext.fetch(visitDescriptor) {
                let durations = visits.compactMap { visit -> TimeInterval? in
                    guard let ended = visit.endedAt else { return nil }
                    return max(0, ended.timeIntervalSince(visit.startedAt))
                }
                if !durations.isEmpty {
                    let totalSeconds = durations.reduce(0, +)
                    let averageSeconds = Int((totalSeconds / Double(durations.count)).rounded())
                    avgDurationString = Formatters.durationString(seconds: averageSeconds)
                }
            }
        }

        #if canImport(Charts)
        self.revenueSeries = days.map { RevenuePoint(label: $0.day.formatted(date: .abbreviated, time: .omitted), date: $0.day, amount: $0.revenue) }
        #endif

        let averageOrderValue = totalCount > 0 ? (totalRevenue / Decimal(totalCount)) : .zero
        self.kpis = KpiSet(
            revenueString: Formatters.currency.string(from: NSDecimalNumber(decimal: totalRevenue)) ?? "$0.00",
            count: totalCount,
            aovString: Formatters.currency.string(from: NSDecimalNumber(decimal: averageOrderValue)) ?? "$0.00",
            avgDurationString: avgDurationString
        )

        var tiles: [MetricTile] = []
        for metric in metrics {
            switch metric {
            case .revenue:
                let value = Formatters.currency.string(from: NSDecimalNumber(decimal: totalRevenue)) ?? "$0.00"
                tiles.append(MetricTile(metric: .revenue, value: value))
            case .visitCount:
                let value = NumberFormatter.localizedString(from: NSNumber(value: totalCount), number: .decimal)
                tiles.append(MetricTile(metric: .visitCount, value: value))
            case .averageOrderValue:
                let value = Formatters.currency.string(from: NSDecimalNumber(decimal: averageOrderValue)) ?? "$0.00"
                tiles.append(MetricTile(metric: .averageOrderValue, value: value))
            case .averageDuration:
                tiles.append(MetricTile(metric: .averageDuration, value: avgDurationString))
            }
        }
        self.metricTiles = tiles
        // Services
        let serviceArray = svcCounts.map { ServiceLeader(name: $0.key, count: $0.value) }
        let sortedServices = serviceArray.sorted { (l, r) -> Bool in
            if l.count == r.count { return l.name < r.name }
            return l.count > r.count
        }
        self.serviceLeaders = Array(sortedServices.prefix(10))

        // Categories
        let categoryArray: [CategoryTotal] = catCounts.compactMap { (raw, c) in
            Service.Category(rawValue: raw).map { CategoryTotal(category: $0, count: c) }
        }
        let sortedCategories = categoryArray.sorted { (l, r) -> Bool in
            if l.count == r.count { return l.category.rawValue < r.category.rawValue }
            return l.count > r.count
        }
        self.categoryTotals = sortedCategories

        // Packages (derived from services labeled as packages)
        let pkg = sortedServices.filter { $0.name.localizedCaseInsensitiveContains("package") }
        self.packageLeaders = pkg.map { PackageLeader(name: $0.name, count: $0.count) }

        isLoading = false
    }

    func applyCustomDates() { customStartDate = customDraftStart; customEndDate = customDraftEnd; fetchAndProcessData() }

    func toggleMetric(_ metric: Metric) {
        setMetric(metric, enabled: !configuration.isMetricEnabled(metric))
    }

    func setMetric(_ metric: Metric, enabled: Bool) {
        var next = configuration
        next.setMetric(metric, enabled: enabled)
        if next != configuration {
            configuration = next
        }
    }

    var exportCSV: String {
        let (start, end) = dateRange(for: scope)
        let dayPred = #Predicate<DaySummary> { s in (start == nil || s.day >= start!) && (end == nil || s.day < end!) }
        let dayDesc = FetchDescriptor<DaySummary>(predicate: dayPred, sortBy: [SortDescriptor(\.day, order: .forward)])
        let rows = (try? modelContext.fetch(dayDesc)) ?? []
        var out = "Date,Revenue,Visits\n"
        for r in rows {
            out += "\(r.day.formatted(date: .abbreviated, time: .omitted)),\(NSDecimalNumber(decimal: r.revenue).stringValue),\(r.visitCount)\n"
        }
        return out
    }

    private func shouldIgnore(payload: VisitDidCompleteNotification.Payload) -> Bool {
        guard let endedAt = payload.endedAt else { return false }
        let (start, end) = dateRange(for: scope)
        if let start, endedAt < start { return true }
        if let end, endedAt >= end { return true }
        return false
    }

    private func dateRange(for scope: Scope) -> (Date?, Date?) {
        let now = Date(); let cal = Calendar.current
        switch scope {
        case .today:
            let s = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: 1, to: s) else { return (s, nil) }
            return (s, end)
        case .week:
            guard let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear,.weekOfYear], from: now)),
                  let end = cal.date(byAdding: .day, value: 7, to: s) else {
                return (nil, nil)
            }
            return (s, end)
        case .month:
            guard let s = cal.date(from: cal.dateComponents([.year,.month], from: now)),
                  let end = cal.date(byAdding: .month, value: 1, to: s) else {
                return (nil, nil)
            }
            return (s, end)
        case .all:
            return (nil,nil)
        case .custom:
            let s = cal.startOfDay(for: customStartDate)
            guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEndDate)) else { return (s, nil) }
            return (s, end)
        }
    }

    private func makeVisitPredicate(start: Date?, end: Date?) -> Predicate<Visit> {
        let lower = start
        let upper = end
        return #Predicate<Visit> { visit in
            guard let ended = visit.endedAt else { return false }
            if let lower, ended < lower { return false }
            if let upper, ended >= upper { return false }
            return true
        }
    }
}

extension InsightsViewModel {
    enum Scope: String, CaseIterable, Identifiable { case today, week, month, all, custom; var id:String { rawValue }; var title:String { rawValue.capitalized } }

    enum Metric: String, CaseIterable, Identifiable {
        case revenue
        case visitCount
        case averageOrderValue
        case averageDuration

        var id: String { rawValue }

        fileprivate var sortIndex: Int {
            switch self {
            case .revenue: return 0
            case .visitCount: return 1
            case .averageOrderValue: return 2
            case .averageDuration: return 3
            }
        }

        static var defaultOrder: [Metric] { [.revenue, .visitCount, .averageOrderValue, .averageDuration] }
    }

    struct AnalyticsConfiguration: Equatable {
        private(set) var orderedMetrics: [Metric]

        init(metrics: [Metric]) {
            let normalized = metrics.isEmpty ? Metric.defaultOrder : metrics
            self.orderedMetrics = normalized.sorted { $0.sortIndex < $1.sortIndex }
        }

        mutating func setMetric(_ metric: Metric, enabled: Bool) {
            if enabled {
                if !orderedMetrics.contains(metric) {
                    orderedMetrics.append(metric)
                    orderedMetrics.sort { $0.sortIndex < $1.sortIndex }
                }
            } else {
                guard orderedMetrics.count > 1 else { return }
                orderedMetrics.removeAll { $0 == metric }
            }
        }

        func isMetricEnabled(_ metric: Metric) -> Bool {
            orderedMetrics.contains(metric)
        }

        static let `default` = AnalyticsConfiguration(metrics: Metric.defaultOrder)
    }

    struct MetricTile: Identifiable {
        let metric: Metric
        let value: String
        var id: Metric { metric }
    }

    struct KpiSet { let revenueString:String; let count:Int; let aovString:String; let avgDurationString:String; static let empty = KpiSet(revenueString: "$0.00", count: 0, aovString: "$0.00", avgDurationString: "—") }
    #if canImport(Charts)
    struct RevenuePoint: Identifiable { let label:String; let date:Date; let amount:Decimal; var id:Date { date } }
    #endif
    struct ServiceLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct PackageLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct CategoryTotal: Identifiable { let category: Service.Category; let count:Int; var id:String { category.rawValue }; var name:String { category.rawValue } }
}
