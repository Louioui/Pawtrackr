//
//  InsightsView.swift
//  Pawtrackr
//

import SwiftUI
import Charts
import SwiftData
import CoreTransferable

private struct InsightsDrilldown: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let summary: String
    let rows: [InsightsDrilldownRow]
}

private struct InsightsDrilldownRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let trailing: String
}

struct InsightsView: View {
    @Environment(DataStoreService.self) private var dataStore
    @Environment(GlobalEventBus.self) private var eventBus
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var reportPDFData: Data?
    @State private var reportCSVDocument: ExportDocument?
    @State private var isPreparingReport = false
    @State private var selectedDrilldown: InsightsDrilldown?

    var body: some View {
        Group {
            if let vm = viewModel {
                switch vm.state {
                case .loading:
                    loadingContent
                        .transition(.opacity)
                case .loaded:
                    mainContent(vm)
                        .transition(.opacity)
                case .error(let message):
                    ContentUnavailableView(
                        NSLocalizedString("common.error", comment: ""),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            } else {
                Color.clear
                    .task {
                        guard viewModel == nil else { return }
                        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
                        viewModel = vm
                        await vm.refresh()
                    }
            }
        }
        .background {
            InsightsMeshBackground()
                .allowsHitTesting(false)
        }
        .navigationTitle(NSLocalizedString("insights.title", value: "Insights", comment: ""))
        .refreshable {
            await viewModel?.refresh()
        }
        .sheet(item: $selectedDrilldown) { drilldown in
            drilldownSheet(drilldown)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                reportButton
            }
        }
    }

    // MARK: - Main content

    private func mainContent(_ vm: InsightsViewModel) -> some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                kpiSummaryRow(vm)
                revenueCard(vm)
                if !vm.dataQualityIssues.isEmpty {
                    dataQualityCard(vm)
                }
                monthlyPerformanceCard(vm)
                serviceRevenueCard(vm)
                paymentMixCard(vm)
                categoryCard(vm)
                retentionCard(vm)
            }
            .padding(DS.Spacing.lg)
            .accessibilityIdentifier("insights.mainScroll.content")
        }
        .accessibilityIdentifier("insights.mainScroll")
    }

    // MARK: - KPI summary strip

    private func kpiSummaryRow(_ vm: InsightsViewModel) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            kpiTile(
                title: NSLocalizedString("insights.revenue", comment: ""),
                value: vm.totalRevenue.moneyString,
                icon: "dollarsign.circle.fill",
                color: DS.ColorToken.primary,
                accessibilityIdentifier: "insights.kpi.revenue"
            )
            kpiTile(
                title: localized("insights.avg_visit", value: "Avg Visit"),
                value: vm.averageVisitValue > 0 ? vm.averageVisitValue.moneyString : "—",
                icon: "chart.line.uptrend.xyaxis",
                color: DS.ColorToken.success,
                accessibilityIdentifier: "insights.kpi.avgVisit"
            )
            kpiTile(
                title: NSLocalizedString("insights.retention", comment: ""),
                value: "\(Int(vm.retentionRate * 100))%",
                icon: "person.2.fill",
                color: DS.ColorToken.warning,
                accessibilityIdentifier: "insights.kpi.retention"
            )
        }
    }

    private func kpiTile(
        title: String,
        value: String,
        icon: String,
        color: Color,
        accessibilityIdentifier: String
    ) -> some View {
        Card(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    // MARK: - Data Quality

    private func dataQualityCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Label(localized("insights.data_quality.title", value: "Data Quality"), systemImage: "checklist.checked")
                    .font(.headline)

                ForEach(vm.dataQualityIssues.prefix(4)) { issue in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: dataQualityIcon(for: issue.severity))
                            .foregroundStyle(dataQualityColor(for: issue.severity))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.subheadline.weight(.semibold))
                            Text(issue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Text("\(issue.count)")
                            .font(.headline)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("insights.section.dataQuality")
    }

    // MARK: - Revenue

    private func revenueCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("insights.revenue", comment: ""))
                            .font(.headline)
                        Text(String(format: localized("insights.window_days_fmt", value: "%d-day window"), vm.revenuePeriodDays))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("insights.revenue.window")
                            .accessibilityValue(String(format: localized("insights.window_days_fmt", value: "%d-day window"), vm.revenuePeriodDays))
                    }
                    Spacer()
                    revenuePeriodSelector(vm)
                }

                Text(vm.totalRevenue.moneyString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.ColorToken.primary)
                    .contentTransition(.numericText())

                if vm.revenueSeries.isEmpty || vm.totalRevenue == .zero {
                    emptyState(icon: "chart.bar.xaxis", message: "No revenue recorded in this period")
                } else {
                    Chart(vm.revenueSeries) { data in
                        BarMark(
                            x: .value(localized("insights.chart.day", value: "Day"), data.date, unit: .day),
                            y: .value(NSLocalizedString("insights.revenue", comment: ""), (data.amount as NSDecimalNumber).doubleValue)
                        )
                        .foregroundStyle(DS.ColorToken.primary.gradient)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: vm.revenuePeriodDays <= 7 ? 1 : vm.revenuePeriodDays <= 30 ? 5 : 15)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                            AxisGridLine()
                        }
                    }
                    .frame(height: 155)
                    .animation(.spring(), value: vm.revenueSeries.count)

                    HStack {
                        Label(String(format: localized("insights.visits_count_fmt", value: "%d visits"), vm.totalVisitsInPeriod), systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(
                            String(format: localized("insights.avg_money_fmt", value: "Avg %@"), vm.averageVisitValue.moneyString),
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("insights.section.revenue")
    }

    private func revenuePeriodSelector(_ vm: InsightsViewModel) -> some View {
        let periods: [Int] = [7, 30, 90]
        return HStack(spacing: 4) {
            ForEach(periods, id: \.self) { period in
                let isSelected = vm.revenuePeriodDays == period
                Button {
                    guard vm.revenuePeriodDays != period else { return }
                    withAnimation(Animations.responsiveSpringSoft) {
                        vm.revenuePeriodDays = period
                    }
                    reportPDFData = nil
                    reportCSVDocument = nil
                    Task { await vm.refreshRevenue() }
                } label: {
                    Text("\(period)D")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(minWidth: 34)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(isSelected ? DS.ColorToken.primary : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityIdentifier("insights.period.\(period)")
            }
        }
        .padding(4)
        .background(DS.ColorToken.surface, in: Capsule())
    }

    // MARK: - Monthly Performance

    private func monthlyPerformanceCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text(localized("insights.monthly_performance", value: "Monthly Performance")).font(.headline)

                if vm.monthlyGrowth.isEmpty {
                    emptyState(icon: "chart.line.uptrend.xyaxis", message: localized("insights.monthly.empty", value: "No monthly data yet"))
                } else {
                    Chart(vm.monthlyGrowth) { data in
                        LineMark(
                            x: .value("Month", data.month),
                            y: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue)
                        )
                        .foregroundStyle(DS.ColorToken.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .symbol(Circle().strokeBorder(lineWidth: 2))
                        
                        AreaMark(
                            x: .value("Month", data.month),
                            y: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue)
                        )
                        .foregroundStyle(DS.ColorToken.primary.opacity(0.1))
                    }
                    .frame(height: 155)

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(vm.monthlyGrowth.suffix(3)) { data in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(data.month).font(.caption2).foregroundStyle(.secondary)
                                Text(data.revenue.moneyString).font(.subheadline.weight(.bold))
                                Text(String(format: localized("insights.visits_count_fmt", value: "%d visits"), data.visitCount)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Service Revenue

    private func serviceRevenueCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.topServices", label: NSLocalizedString("insights.top_services", comment: ""))
                Text(localized("insights.service_profitability", value: "Service Profitability")).font(.headline)

                if vm.serviceProfitability.isEmpty && vm.serviceDistribution.isEmpty {
                    emptyState(icon: "scissors", message: localized("insights.service_profitability.empty", value: "No service data yet"))
                } else {
                    let top5 = Array((vm.serviceProfitability.isEmpty ? vm.serviceDistribution : vm.serviceProfitability.map {
                        InsightsViewModel.DistributionData(name: $0.name, count: $0.count, revenue: $0.revenue)
                    }).prefix(5))
                    Chart(top5) { data in
                        BarMark(
                            x: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue),
                            y: .value("Service", data.name)
                        )
                        .foregroundStyle(DS.ColorToken.success.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(top5.count) * 44)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.topServices")
    }

    private func paymentMixCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.paymentMix", label: localized("insights.payment_mix", value: "Payment Mix"))
                Text(localized("insights.payment_mix", value: "Payment Mix")).font(.headline)

                if vm.paymentMethodDistribution.isEmpty {
                    emptyState(icon: "creditcard", message: localized("insights.payment_mix.empty", value: "No payments recorded yet"))
                } else {
                    ForEach(vm.paymentMethodDistribution) { item in
                        HStack(spacing: 12) {
                            Label(item.method.displayName, systemImage: item.method.systemImage)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.amount.moneyString).font(.subheadline.weight(.bold))
                                Text(paymentCountText(item.count)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.paymentMix")
    }

    private func categoryCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.category", label: localized("insights.visits_by_category", value: "Visits by Category"))
                Text(localized("insights.visits_by_category", value: "Visits by Category")).font(.headline)

                if vm.categoryDistribution.isEmpty {
                    emptyState(icon: "square.grid.2x2", message: localized("insights.category.empty", value: "No category data yet"))
                } else {
                    Chart(vm.categoryDistribution) { data in
                        SectorMark(
                            angle: .value(localized("insights.chart.count", value: "Count"), data.count),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(categoryColor(for: data.name))
                    }
                    .frame(height: 155)
                    .chartLegend(.hidden)
                    .overlay {
                        VStack {
                            Text("\(vm.totalCategoryVisits)").font(.headline)
                            Text(localized("insights.visits_lowercase", value: "visits")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(spacing: 0) {
                        ForEach(Array(vm.categoryDistribution.enumerated()), id: \.element.id) { index, item in
                            categoryBreakdownRow(item, total: vm.totalCategoryVisits)
                            if index < vm.categoryDistribution.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.category")
    }

    private func retentionCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.retention", label: NSLocalizedString("insights.retention", comment: ""))
                Text(NSLocalizedString("insights.retention", comment: "")).font(.headline)

                if vm.retentionSeries.isEmpty {
                    emptyState(icon: "person.2", message: localized("insights.retention.empty", value: "Not enough client data yet"))
                } else {
                    HStack(spacing: 30) {
                        Chart(vm.retentionSeries) { data in
                            SectorMark(angle: .value("Value", data.value), innerRadius: .ratio(0.7))
                                .foregroundStyle(data.label == localized("insights.retention.recurring", value: "Recurring") ? DS.ColorToken.primary : Color.gray.opacity(0.2))
                        }
                        .frame(width: 100, height: 100)
                        .chartLegend(.hidden)
                        .overlay {
                            Text("\(Int(vm.retentionRate * 100))%").font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            metricLabel(title: NSLocalizedString("insights.retention_rate", comment: ""), value: "\(Int(vm.retentionRate * 100))%", color: DS.ColorToken.primary)
                            metricLabel(title: NSLocalizedString("insights.churn_risk", comment: ""), value: String(format: localized("insights.clients_count_fmt", value: "%d clients"), vm.churnRiskCount), color: DS.ColorToken.warning)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.retention")
    }

    private func metricLabel(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    private func categoryBreakdownRow(_ item: InsightsViewModel.DistributionData, total: Int) -> some View {
        let percent = total > 0 ? Int((Double(item.count) / Double(total) * 100).rounded()) : 0
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(categoryColor(for: item.name))
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(String(format: localized("insights.category.row_detail_fmt", value: "%d%% of categorized visit line items"), percent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: localized("insights.visits_count_fmt", value: "%d visits"), item.count))
                .font(.subheadline.weight(.bold))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func categoryColor(for name: String) -> Color {
        switch name {
        case Service.Category.package.rawValue:
            return DS.ColorToken.info
        case Service.Category.addOn.rawValue:
            return DS.ColorToken.warning
        case Service.Category.groom.rawValue:
            return DS.ColorToken.success
        case Service.Category.care.rawValue:
            return Color.purple
        default:
            return Color.gray
        }
    }

    private func paymentCountText(_ count: Int) -> String {
        count == 1 ? "1 payment" : "\(count) payments"
    }

    private func lowerSectionAccessibilityAnchor(identifier: String, label: String) -> some View {
        Color.primary.opacity(0.001)
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }

    private var reportButton: some View {
        Group {
            if let pdfData = reportPDFData, let csvDoc = reportCSVDocument {
                Menu {
                    let pdfDoc = ReportDocument(pdfData: pdfData, filename: "Report.pdf")
                    ShareLink(item: pdfDoc, preview: SharePreview(localized("insights.export.pdf_report", value: "PDF Report"), image: Image(systemName: "doc.pdf"))) {
                        Label(localized("insights.export.pdf_report", value: "PDF Report"), systemImage: "doc.richtext")
                    }
                    ShareLink(item: csvDoc, preview: SharePreview(localized("insights.export.csv", value: "Insights CSV"), image: Image(systemName: "tablecells"))) {
                        Label(localized("insights.export.csv_data", value: "CSV Data"), systemImage: "tablecells")
                    }
                } label: {
                    Label(NSLocalizedString("common.export", comment: ""), systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(localized("insights.export.share_report", value: "Share Report"))
                .accessibilityIdentifier("insights.shareReport")
            } else {
                Button {
                    isPreparingReport = true
                    Task {
                        if let vm = viewModel {
                            let summary = await vm.generateReportSummary()
                            async let pdfData = BusinessReportService.shared.generateMonthlyReportAsync(summary: summary)
                            let csvDoc = await vm.generateInsightsCSVDocument()
                            reportPDFData = await pdfData
                            reportCSVDocument = csvDoc
                        }
                        isPreparingReport = false
                    }
                }
 label: {
                    if isPreparingReport { ProgressView() } else { Label(NSLocalizedString("common.export", comment: ""), systemImage: "doc.badge.arrow.up") }
                }
                .disabled(isPreparingReport)
                .accessibilityLabel(localized("insights.export.export_report", value: "Export Report"))
                .accessibilityIdentifier("insights.exportReport")
            }
        }
    }

    private func drilldownSheet(_ drilldown: InsightsDrilldown) -> some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(drilldown.summary)
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text(localized("insights.drilldown.what_this_means", value: "What this means"))
                }

                Section {
                    if drilldown.rows.isEmpty {
                        ContentUnavailableView(
                            localized("insights.drilldown.no_rows_title", value: "No Rows"),
                            systemImage: "list.bullet.rectangle",
                            description: Text(localized("insights.drilldown.no_rows_message", value: "There is no supporting data for this selection yet."))
                        )
                    } else {
                        ForEach(drilldown.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(row.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.trailing)
                                    .font(.subheadline.bold())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: {
                    Text(drilldown.subtitle)
                }
            }
            .navigationTitle(drilldown.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.done", comment: "")) { selectedDrilldown = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(.secondary.opacity(0.3))
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 120)
    }

    private func showRevenueDrilldown(_ vm: InsightsViewModel) {
        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.revenue_title", value: "Revenue Detail"),
            subtitle: String(format: localized("insights.window_days_fmt", value: "%d-day window"), vm.revenuePeriodDays),
            summary: localized(
                "insights.drilldown.revenue_summary",
                value: "This lists the completed visits included in the selected revenue window. Use it to reconcile cash, card, and checkout history."
            ),
            rows: visitDrilldownRows(vm.revenueDrilldown)
        )
    }

    private func showRevenueDrilldown(for date: Date, vm: InsightsViewModel) {
        let rows = vm.revenueDrilldown.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        selectedDrilldown = InsightsDrilldown(
            title: date.formatted(date: .abbreviated, time: .omitted),
            subtitle: rows.isEmpty
                ? localized("insights.drilldown.no_visits_for_day", value: "No visits recorded for this day")
                : localized("insights.drilldown.chart_bar_visits", value: "Visits behind this chart bar"),
            summary: localized(
                "insights.drilldown.revenue_day_summary",
                value: "This view opens the visits behind one chart bar so the team can verify exactly which checkouts created the total."
            ),
            rows: visitDrilldownRows(rows.isEmpty ? vm.revenueDrilldown : rows)
        )
    }

    private func showAverageVisitDrilldown(_ vm: InsightsViewModel) {
        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.average_visit_title", value: "Average Visit Detail"),
            subtitle: localized("insights.drilldown.average_visit_subtitle", value: "Highest-value visits in the selected revenue window"),
            summary: String(
                format: localized(
                    "insights.drilldown.average_visit_summary_fmt",
                    value: "Average visit is total revenue divided by completed visits. Current average: %@ across %d visits."
                ),
                vm.averageVisitValue.moneyString,
                vm.totalVisitsInPeriod
            ),
            rows: visitDrilldownRows(vm.revenueDrilldown.sorted { $0.total > $1.total })
        )
    }

    private func showRetentionDrilldown(_ vm: InsightsViewModel) {
        let explainerRow = InsightsDrilldownRow(
            title: localized("insights.drilldown.retention_what_title", value: "What this measures"),
            subtitle: localized(
                "insights.drilldown.retention_what_message",
                value: "Share of clients who returned for another visit within the last 90 days. Higher means more repeat customers."
            ),
            trailing: "\(Int(vm.retentionRate * 100))%"
        )
        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.retention_title", value: "Client Retention"),
            subtitle: localized("insights.drilldown.retention_subtitle", value: "How retention is calculated"),
            summary: localized(
                "insights.drilldown.retention_summary",
                value: "Retention shows how many clients returned for another visit within the last 90 days. Churn risk is the client count that has not returned on schedule."
            ),
            rows: [explainerRow]
        )
    }

    private func showCategoryDrilldown(_ vm: InsightsViewModel) {
        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.category_title", value: "Visit Category Detail"),
            subtitle: localized("insights.drilldown.category_subtitle", value: "Category share for completed visit line items"),
            summary: localized(
                "insights.drilldown.category_summary",
                value: "This breaks down which types of services are driving completed visits. A category can count more than once when a checkout includes multiple line items."
            ),
            rows: categoryDrilldownRows(vm.categoryDistribution, total: vm.totalCategoryVisits)
        )
    }

    private func categoryDrilldownRows(_ rows: [InsightsViewModel.DistributionData], total: Int) -> [InsightsDrilldownRow] {
        rows.map { item in
            let percent = total > 0 ? Int((Double(item.count) / Double(total) * 100).rounded()) : 0
            return InsightsDrilldownRow(
                title: item.name,
                subtitle: String(format: localized("insights.category.row_detail_fmt", value: "%d%% of categorized visit line items"), percent),
                trailing: String(format: localized("insights.visits_count_fmt", value: "%d visits"), item.count)
            )
        }
    }

    private func visitDrilldownRows(_ rows: [InsightsViewModel.RevenueVisitData]) -> [InsightsDrilldownRow] {
        rows.map {
            InsightsDrilldownRow(
                title: "\($0.petName) • \($0.clientName)",
                subtitle: "\($0.date.formatted(date: .abbreviated, time: .omitted)) • \($0.serviceSummary) • \($0.paymentMethod)",
                trailing: $0.total.moneyString
            )
        }
    }

    private func percentString(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))%"
    }

    private func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }

    private func dataQualityIcon(for severity: InsightsViewModel.DataQualityIssue.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func dataQualityColor(for severity: InsightsViewModel.DataQualityIssue.Severity) -> Color {
        switch severity {
        case .info: return DS.ColorToken.primary
        case .warning: return DS.ColorToken.warning
        case .critical: return DS.ColorToken.danger
        }
    }

    // MARK: - Skeleton / Loading

    private var loadingContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(0..<3) { _ in SkeletonRect().frame(height: 90) }
                }
                
                // Chart Skeletons
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonRect().frame(width: 150, height: 20)
                    SkeletonChart(type: .bar).frame(height: 160)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonRect().frame(width: 180, height: 20)
                    SkeletonChart(type: .line).frame(height: 160)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SkeletonRect().frame(width: 140, height: 20)
                    SkeletonChart(type: .pie).frame(height: 160)
                }
            }
            .padding(DS.Spacing.lg)
        }
    }
}

enum SkeletonChartType { case bar, line, pie }

struct SkeletonChart: View {
    let type: SkeletonChartType

    // Fixed heights so the skeleton is stable across re-renders.
    // CGFloat.random in a view body causes layout thrashing on every redraw.
    private static let barHeights: [CGFloat] = [85, 55, 110, 70, 95, 45, 120, 65, 80, 50]

    var body: some View {
        Card {
            HStack(alignment: .bottom, spacing: 8) {
                if type == .bar {
                    ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { _, height in
                        SkeletonRect()
                            .frame(height: height)
                    }
                } else if type == .line {
                    ZStack {
                        SkeletonRect().opacity(0.1)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 100))
                            path.addLine(to: CGPoint(x: 50, y: 40))
                            path.addLine(to: CGPoint(x: 100, y: 80))
                            path.addLine(to: CGPoint(x: 150, y: 20))
                            path.addLine(to: CGPoint(x: 200, y: 60))
                        }
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    }
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 20)
                        .frame(width: 100, height: 100)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
        }
    }
}
