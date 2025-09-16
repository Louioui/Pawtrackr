
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
    var analyticsConfiguration: AnalyticsConfiguration = .default {
        didSet {
            if oldValue != analyticsConfiguration { fetchAndProcessData() }
        }
    }

    // Outputs
    private(set) var kpis: KpiSet = .empty
    #if canImport(Charts)
    private(set) var revenueSeries: [RevenuePoint] = []
    #endif
    private(set) var serviceLeaders: [ServiceLeader] = []
    private(set) var packageLeaders: [PackageLeader] = []
    private(set) var categoryTotals: [CategoryTotal] = []
    var isLoading: Bool = false

    // Internal
    private let modelContext: ModelContext
    private var workSeq = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        NotificationCenter.default.addObserver(forName: .visitDidComplete, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let metadata = note.visitDidCompleteMetadata else {
                self.fetchAndProcessData()
                return
            }
            if self.shouldRefresh(for: metadata) {
                self.fetchAndProcessData()
            }
        }
        fetchAndProcessData()
    }

    func fetchAndProcessData() {
        isLoading = true
        let seq = { workSeq &+= 1; return workSeq }()
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
        let config = analyticsConfiguration
        let totalRevenue = days.reduce(Decimal.zero) { $0 + $1.revenue }
        let totalCount = days.reduce(0) { $0 + $1.visitCount }
        #if canImport(Charts)
        if config.includeRevenueSeries {
            self.revenueSeries = days.map { RevenuePoint(label: $0.day.formatted(date: .abbreviated, time: .omitted), date: $0.day, amount: $0.revenue) }
        } else {
            self.revenueSeries = []
        }
        #endif
        self.kpis = KpiSet(
            revenueString: Formatters.currency.string(from: NSDecimalNumber(decimal: totalRevenue)) ?? "$0.00",
            count: totalCount,
            aovString: Formatters.currency.string(from: NSDecimalNumber(decimal: (totalCount > 0 ? (totalRevenue/Decimal(totalCount)) : 0))) ?? "$0.00",
            avgDurationString: self.kpis.avgDurationString
        )
        // Services
        var serviceTuples: [(name: String, count: Int)] = svcCounts.map { ($0.key, $0.value) }
        if !config.allowedServiceNames.isEmpty {
            serviceTuples = serviceTuples.filter { config.allowedServiceNames.contains($0.name) }
        }
        if !config.excludedServiceNames.isEmpty {
            serviceTuples = serviceTuples.filter { !config.excludedServiceNames.contains($0.name) }
        }
        let sortedServiceTuples = serviceTuples.sorted { (l, r) -> Bool in
            if l.count == r.count { return l.name < r.name }
            return l.count > r.count
        }
        let leaders = sortedServiceTuples.map { ServiceLeader(name: $0.name, count: $0.count) }
        if config.includeServiceLeaders {
            let limit = max(0, config.serviceLeadersLimit)
            self.serviceLeaders = limit > 0 ? Array(leaders.prefix(limit)) : []
        } else {
            self.serviceLeaders = []
        }

        // Categories
        var categoryArray: [CategoryTotal] = catCounts.compactMap { (raw, c) in
            Service.Category(rawValue: raw).map { CategoryTotal(category: $0, count: c) }
        }
        if !config.allowedCategories.isEmpty {
            categoryArray = categoryArray.filter { config.allowedCategories.contains($0.category) }
        }
        let sortedCategories = categoryArray.sorted { (l, r) -> Bool in
            if l.count == r.count { return l.category.rawValue < r.category.rawValue }
            return l.count > r.count
        }
        self.categoryTotals = config.includeCategoryTotals ? sortedCategories : []

        // Packages (derived from services labeled as packages)
        let packageCandidates = sortedServiceTuples.filter { $0.name.localizedCaseInsensitiveContains("package") }
        let packages = packageCandidates.map { PackageLeader(name: $0.name, count: $0.count) }
        if config.includePackageLeaders {
            let limit = max(0, config.packageLeadersLimit)
            self.packageLeaders = limit > 0 ? Array(packages.prefix(limit)) : []
        } else {
            self.packageLeaders = []
        }

        isLoading = false
    }

    func applyCustomDates() { customStartDate = customDraftStart; customEndDate = customDraftEnd; fetchAndProcessData() }

    func updateAnalyticsConfiguration(_ newConfig: AnalyticsConfiguration) {
        analyticsConfiguration = newConfig
    }

    private func shouldRefresh(for metadata: VisitDidCompleteMetadata) -> Bool {
        guard let endedAt = metadata.endedAt else { return true }
        return scope.contains(date: endedAt, customStart: customStartDate, customEnd: customEndDate)
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
}

extension InsightsViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case today, week, month, all, custom

        var id:String { rawValue }
        var title:String { rawValue.capitalized }

        func contains(date: Date, customStart: Date, customEnd: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
            switch self {
            case .all:
                return true
            case .today:
                return calendar.isDate(date, inSameDayAs: now)
            case .week:
                guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                      let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return true
                }
                return date >= weekStart && date < weekEnd
            case .month:
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                      let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return true
                }
                return date >= monthStart && date < monthEnd
            case .custom:
                let start = calendar.startOfDay(for: customStart)
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
                return date >= start && date < end
            }
        }
    }
    struct KpiSet { let revenueString:String; let count:Int; let aovString:String; let avgDurationString:String; static let empty = KpiSet(revenueString: "$0.00", count: 0, aovString: "$0.00", avgDurationString: "—") }
    #if canImport(Charts)
    struct RevenuePoint: Identifiable { let label:String; let date:Date; let amount:Decimal; var id:Date { date } }
    #endif
    struct ServiceLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct PackageLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct CategoryTotal: Identifiable { let category: Service.Category; let count:Int; var id:String { category.rawValue }; var name:String { category.rawValue } }
    struct AnalyticsConfiguration: Equatable {
        var includeRevenueSeries: Bool = true
        var includeServiceLeaders: Bool = true
        var includePackageLeaders: Bool = true
        var includeCategoryTotals: Bool = true
        var allowedServiceNames: Set<String> = []
        var excludedServiceNames: Set<String> = []
        var allowedCategories: Set<Service.Category> = []
        var serviceLeadersLimit: Int = 10
        var packageLeadersLimit: Int = 10

        static let `default` = AnalyticsConfiguration()
    }
}
