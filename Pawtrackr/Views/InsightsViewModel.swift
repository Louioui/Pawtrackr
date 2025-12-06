import SwiftUI
import SwiftData
import Combine

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - Nested Types

    struct KPISnapshot {
        var revenue: Decimal = .zero
        var count: Int = 0
        var averageOrderValue: Decimal = .zero
        var averageDurationSeconds: TimeInterval = 0

        static let empty = KPISnapshot()

        @MainActor
        var revenueString: String { revenue.moneyString }

        @MainActor
        var aovString: String {
            count > 0 ? averageOrderValue.moneyString : Decimal.zero.moneyString
        }
    }

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
        case last7Days
        case last30Days
        case thisMonth
        case yearToDate
        case custom

        var id: String { title }

        var title: String {
            switch self {
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

    // Comparison properties
    var enableComparison: Bool = false { didSet { scopeDidChange(oldValue: scope) } }
    var comparisonScope: Scope = .last30Days
    var comparisonCustomDraftStart: Date
    var comparisonCustomDraftEnd: Date

    private(set) var kpis: KPISnapshot = .empty
    private(set) var comparisonKpis: KPISnapshot = .empty

    private(set) var revenueSeries: [RevenuePoint] = []
    private(set) var comparisonRevenueSeries: [RevenuePoint] = []

    private(set) var serviceLeaders: [CountRow] = []
    private(set) var packageLeaders: [CountRow] = []
    private(set) var packageMix: [CountRow] = []
    private(set) var exportCSV: String = ""
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    // MARK: - Private state

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var customAppliedStart: Date?
    @ObservationIgnored private var customAppliedEndExclusive: Date?
    @ObservationIgnored private var comparisonCustomAppliedStart: Date?
    @ObservationIgnored private var comparisonCustomAppliedEndExclusive: Date?
    

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

        // Comparison dates
        let compDraftEnd = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let compDraftStart = calendar.date(byAdding: .day, value: -59, to: today) ?? today
        self.comparisonCustomDraftEnd = compDraftEnd
        self.comparisonCustomDraftStart = compDraftStart
        self.comparisonCustomAppliedStart = compDraftStart
        self.comparisonCustomAppliedEndExclusive = calendar.date(byAdding: .day, value: 1, to: compDraftEnd)


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

    func applyComparisonCustomDates() {
        guard comparisonCustomDraftEnd >= comparisonCustomDraftStart else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: comparisonCustomDraftStart)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: comparisonCustomDraftEnd))
        comparisonCustomAppliedStart = start
        comparisonCustomAppliedEndExclusive = endExclusive
        if comparisonScope != .custom {
            comparisonScope = .custom
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
                let summaries = try fetchDaySummaries(bounds: bounds)
                let visits = try fetchVisits(bounds: bounds)
                self.apply(visits: visits, summaries: summaries, bounds: bounds)

                if self.enableComparison {
                    let comparisonBounds = self.dateBounds(for: self.comparisonScope, customStart: self.comparisonCustomAppliedStart, customEnd: self.comparisonCustomAppliedEndExclusive)
                    let comparisonSummaries = try self.fetchDaySummaries(bounds: comparisonBounds)
                    let comparisonVisits = try self.fetchVisits(bounds: comparisonBounds)
                    self.applyComparison(visits: comparisonVisits, summaries: comparisonSummaries, bounds: comparisonBounds)
                } else {
                    self.clearComparison()
                }

            } catch {
                self.errorMessage = "Failed to load insights. \(error.localizedDescription)"
                self.apply(visits: [], summaries: [], bounds: bounds)
                self.clearComparison()
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

    private func apply(visits: [Visit], summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) {
        defer { isLoading = false }
        kpis = Self.computeKPIs(visits: visits, summaries: summaries)
        let serviceSummary = Self.computeServiceSummaries(visits: visits)
        serviceLeaders = serviceSummary.topServices
        packageLeaders = serviceSummary.topPackages
        packageMix = serviceSummary.packageMix
        revenueSeries = Self.buildRevenueSeries(visits: visits, summaries: summaries, bounds: bounds)
        exportCSV = Self.buildCSV(visits: visits, bounds: bounds)
    }

    private func applyComparison(visits: [Visit], summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) {
        comparisonKpis = Self.computeKPIs(visits: visits, summaries: summaries)
        comparisonRevenueSeries = Self.buildRevenueSeries(visits: visits, summaries: summaries, bounds: bounds)
    }

    private func clearComparison() {
        comparisonKpis = .empty
        comparisonRevenueSeries = []
    }

    private func fetchVisits(bounds: (start: Date?, endExclusive: Date?)) throws -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(
            predicate: Self.makePredicate(start: bounds.start, endExclusive: bounds.endExclusive),
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchDaySummaries(bounds: (start: Date?, endExclusive: Date?)) throws -> [DaySummary] {
        let lowerBound = bounds.start ?? Date.distantPast
        let upperBound = bounds.endExclusive ?? Date.distantFuture
        let predicate = #Predicate<DaySummary> { summary in
            summary.day >= lowerBound && summary.day < upperBound
        }
        let descriptor = FetchDescriptor<DaySummary>(predicate: predicate, sortBy: [SortDescriptor(\.day, order: .forward)])
        return try modelContext.fetch(descriptor)
    }

    private func dateBounds(for scope: Scope, customStart: Date?, customEnd: Date?) -> (start: Date?, endExclusive: Date?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch scope {
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
            let start = calendar.date(from: comps)
            let endExclusive = calendar.date(byAdding: .month, value: 1, to: start ?? today)
            return (start, endExclusive)
        case .yearToDate:
            let comps = calendar.dateComponents([.year], from: today)
            let start = calendar.date(from: comps)
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
            visit.endedAt != nil ? (visit.endedAt! >= lowerBound && visit.endedAt! < upperBound) : false
        }
    }

    private static func computeKPIs(visits: [Visit], summaries: [DaySummary]) -> KPISnapshot {
        let summaryRevenue = summaries.reduce(Decimal.zero) { $0 +~ $1.revenue }
        let summaryCount = summaries.reduce(0) { $0 + $1.visitCount }
        let visitRevenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }
        let visitCount = visits.count

        let revenue = summaryRevenue > .zero ? summaryRevenue : visitRevenue
        let count = summaryCount > 0 ? summaryCount : visitCount
        if count == 0 { return .empty }

        let durations: TimeInterval = visits.reduce(0) { $0 + $1.duration }
        let averageOrderValue: Decimal = {
            guard count > 0 else { return .zero }
            var numerator = revenue
            var denominator = Decimal(count)
            var result = Decimal()
            NSDecimalDivide(&result, &numerator, &denominator, .bankers)
            return result.roundedMoney()
        }()
        let averageDuration = visitCount > 0 ? durations / Double(visitCount) : 0
        return KPISnapshot(
            revenue: revenue.roundedMoney(),
            count: count,
            averageOrderValue: averageOrderValue,
            averageDurationSeconds: averageDuration
        )
    }

    private static func computeServiceSummaries(visits: [Visit]) -> (topServices: [CountRow], topPackages: [CountRow], packageMix: [CountRow]) {
        guard !visits.isEmpty else { return ([], [], []) }
        var serviceCounts: [String: Int] = [:]
        var packageCounts: [String: Int] = [:]

        for visit in visits {
            for item in visit.items {
                let name = (item.service?.name ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let quantity = max(1, item.quantity)
                serviceCounts[name, default: 0] += quantity

                if isPackage(item: item) {
                    packageCounts[name, default: 0] += quantity
                }
            }
        }

        let topServices = serviceCounts
            .sorted(by: Self.sortCounts)
            .prefix(5)
            .map { CountRow(name: $0.key, count: $0.value) }

        let sortedPackages = packageCounts.sorted(by: Self.sortCounts)
        let topPackages = sortedPackages.prefix(5).map { CountRow(name: $0.key, count: $0.value) }

        let packageMix = Self.buildPackageMix(from: sortedPackages)
        return (topServices, topPackages, packageMix)
    }

    private static func buildPackageMix(from sortedPackages: [(key: String, value: Int)]) -> [CountRow] {
        guard !sortedPackages.isEmpty else { return [] }
        if sortedPackages.count <= 6 {
            return sortedPackages.map { CountRow(name: $0.key, count: $0.value) }
        }
        let topFive = sortedPackages.prefix(5)
        let otherTotal = sortedPackages.dropFirst(5).reduce(0) { $0 + $1.value }
        var rows = topFive.map { CountRow(name: $0.key, count: $0.value) }
        rows.append(CountRow(name: NSLocalizedString("Other", comment: "Other packages bucket"), count: otherTotal))
        return rows
    }

    private static func buildRevenueSeries(visits: [Visit], summaries: [DaySummary], bounds: (start: Date?, endExclusive: Date?)) -> [RevenuePoint] {
        if !summaries.isEmpty {
            let calendar = Calendar.current
            let sorted = summaries.sorted { $0.day < $1.day }
            let start = bounds.start.map { calendar.startOfDay(for: $0) } ?? sorted.first?.day ?? calendar.startOfDay(for: Date())
            let endExclusive = bounds.endExclusive ?? calendar.date(byAdding: .day, value: 1, to: (sorted.last?.day ?? start))

            var bucket: [Date: Decimal] = [:]
            for s in sorted { bucket[s.day] = s.revenue }

            guard let endExclusive else {
                return sorted.map { RevenuePoint(date: $0.day, amount: $0.revenue.roundedMoney()) }
            }

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

        guard !visits.isEmpty else { return [] }
        let calendar = Calendar.current
        var bucket: [Date: Decimal] = [: ]
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

    private static func buildCSV(visits: [Visit], bounds: (start: Date?, endExclusive: Date?)) -> String {
        guard !visits.isEmpty else { return "" }
        var lines: [String] = []

        if let start = bounds.start {
            let calendar = Calendar.current
            let inclusiveEnd = bounds.endExclusive.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
            let startString = Formatters.dateOnly.string(from: start)
            let endString = inclusiveEnd.map { Formatters.dateOnly.string(from: $0) } ?? Formatters.dateOnly.string(from: start)
            lines.append("Date Range,\(startString) – \(endString)")
            lines.append("")
        }

        lines.append("VisitID,Date,Pet,Owner,Services,Revenue,DurationMinutes")
        let sorted = visits.sorted { lhs, rhs in
            let lDate = lhs.endedAt ?? lhs.startedAt
            let rDate = rhs.endedAt ?? rhs.startedAt
            return lDate > rDate
        }

        for visit in sorted {
            let visitDate = visit.endedAt ?? visit.startedAt
            let services = visit.items
                .map { $0.displayName.csvEscaped }
                .joined(separator: "; ")
            let revenue = visit.total.moneyString
            let durationMinutes = max(0, Int((visit.endedAt ?? visit.startedAt).timeIntervalSince(visit.startedAt) / 60))
            let row: [String] = [
                visit.uuid.uuidString,
                Formatters.iso8601.string(from: visitDate),
                visit.pet.name.csvEscaped,
                visit.pet.owner?.fullName.csvEscaped ?? "",
                services,
                revenue.csvEscaped,
                "\(durationMinutes)"
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func sortCounts(_ lhs: (key: String, value: Int), _ rhs: (key: String, value: Int)) -> Bool {
        if lhs.value == rhs.value {
            return lhs.key < rhs.key
        }
        return lhs.value > rhs.value
    }

    private static func isPackage(item: VisitItem) -> Bool {
        if let service = item.service {
            if service.isPackage { return true }
            if let category = service.category, category == .package { return true }
        }
        let name = item.name.lowercased()
        return name.contains("package") || name.contains("bundle")
    }
}
