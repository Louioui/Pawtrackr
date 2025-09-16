
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
        NotificationCenter.default.addObserver(forName: .visitDidComplete, object: nil, queue: .main) { [weak self] _ in
            self?.fetchAndProcessData()
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
        let totalRevenue = days.reduce(Decimal.zero) { $0 + $1.revenue }
        let totalCount = days.reduce(0) { $0 + $1.visitCount }
        #if canImport(Charts)
        self.revenueSeries = days.map { RevenuePoint(label: $0.day.formatted(date: .abbreviated, time: .omitted), date: $0.day, amount: $0.revenue) }
        #endif
        self.kpis = KpiSet(
            revenueString: Formatters.currency.string(from: NSDecimalNumber(decimal: totalRevenue)) ?? "$0.00",
            count: totalCount,
            aovString: Formatters.currency.string(from: NSDecimalNumber(decimal: (totalCount > 0 ? (totalRevenue/Decimal(totalCount)) : 0))) ?? "$0.00",
            avgDurationString: self.kpis.avgDurationString
        )
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
    enum Scope: String, CaseIterable, Identifiable { case today, week, month, all, custom; var id:String { rawValue }; var title:String { rawValue.capitalized } }
    struct KpiSet { let revenueString:String; let count:Int; let aovString:String; let avgDurationString:String; static let empty = KpiSet(revenueString: "$0.00", count: 0, aovString: "$0.00", avgDurationString: "—") }
    #if canImport(Charts)
    struct RevenuePoint: Identifiable { let label:String; let date:Date; let amount:Decimal; var id:Date { date } }
    #endif
    struct ServiceLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct PackageLeader: Identifiable { let name:String; let count:Int; var id:String { name }; var countString:String { "\(count)x" } }
    struct CategoryTotal: Identifiable { let category: Service.Category; let count:Int; var id:String { category.rawValue }; var name:String { category.rawValue } }
}
