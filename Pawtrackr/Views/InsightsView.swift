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
    @State private var scheduleConfirmation = ""
    @State private var showingScheduleConfirmation = false
    @State private var isSchedulingRecall = false

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
        .alert(localized("insights.recall.alert_title", value: "Appointment Scheduled"), isPresented: $showingScheduleConfirmation) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(scheduleConfirmation)
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
                forecastCard(vm)
                comparisonCard(vm)
                if !vm.dataQualityIssues.isEmpty {
                    dataQualityCard(vm)
                }
                monthlyPerformanceCard(vm)
                serviceRevenueCard(vm)
                paymentMixCard(vm)
                categoryCard(vm)
                retentionCard(vm)
                lapsedClientsCard(vm)
                topClientsCard(vm)
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
            ) {
                showRevenueDrilldown(vm)
            }
            kpiTile(
                title: localized("insights.avg_visit", value: "Avg Visit"),
                value: vm.averageVisitValue > 0 ? vm.averageVisitValue.moneyString : "—",
                icon: "chart.line.uptrend.xyaxis",
                color: DS.ColorToken.success,
                accessibilityIdentifier: "insights.kpi.avgVisit"
            ) {
                showAverageVisitDrilldown(vm)
            }
            kpiTile(
                title: NSLocalizedString("insights.retention", comment: ""),
                value: "\(Int(vm.retentionRate * 100))%",
                icon: "person.2.fill",
                color: DS.ColorToken.warning,
                accessibilityIdentifier: "insights.kpi.retention"
            ) {
                showRetentionDrilldown(vm)
            }
        }
    }

    private func kpiTile(
        title: String,
        value: String,
        icon: String,
        color: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
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
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    if let plotFrame = proxy.plotFrame {
                                        let frame = geo[plotFrame]
                                        let x = location.x - frame.origin.x
                                        let selectedDate: Date? = proxy.value(atX: x)
                                        if let selectedDate {
                                            showRevenueDrilldown(for: selectedDate, vm: vm)
                                        } else {
                                            showRevenueDrilldown(vm)
                                        }
                                    } else {
                                        let selectedDate: Date? = proxy.value(atX: location.x)
                                        if let selectedDate {
                                            showRevenueDrilldown(for: selectedDate, vm: vm)
                                        } else {
                                            showRevenueDrilldown(vm)
                                        }
                                    }
                                }
                        }
                    }
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

                    Button {
                        showRevenueDrilldown(vm)
                    } label: {
                        Label(localized("insights.action.view_visits", value: "View visits behind this number"), systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.semibold))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("insights.revenue.drilldown")
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

    // MARK: - Forecasting

    private func forecastCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Label(localized("insights.forecast.title", value: "30-Day Forecast"), systemImage: "wand.and.stars")
                        .font(.headline)
                    Spacer()
                    Text(vm.forecast?.confidenceLabel ?? localized("insights.forecast.no_baseline", value: "No baseline"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let forecast = vm.forecast {
                    HStack(spacing: 12) {
                        metricPill(title: localized("insights.forecast.projected", value: "Projected"), value: forecast.projectedRevenue.moneyString, tint: DS.ColorToken.primary)
                        metricPill(title: NSLocalizedString("insights.visits", value: "Visits", comment: ""), value: "\(forecast.projectedVisits)", tint: DS.ColorToken.success)
                    }

                    Text(String(format: localized("insights.forecast.daily_average_fmt", value: "%@ average daily revenue. %@."), forecast.dailyAverageRevenue.moneyString, forecast.basis))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    emptyState(icon: "chart.line.uptrend.xyaxis", message: localized("insights.forecast.empty", value: "Complete a few visits to unlock forecasting"))
                }
            }
        }
        .accessibilityIdentifier("insights.section.forecast")
    }

    private func comparisonCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text(localized("insights.comparison_windows", value: "Comparison Windows")).font(.headline)

                if vm.comparisons.isEmpty {
                    emptyState(icon: "arrow.left.arrow.right", message: localized("insights.comparison.empty", value: "No comparison data yet"))
                } else {
                    ForEach(vm.comparisons) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(String(format: localized("insights.comparison.visits_fmt", value: "%d vs %d visits"), item.currentVisits, item.previousVisits))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.currentRevenue.moneyString)
                                    .font(.subheadline.weight(.bold))
                                    .contentTransition(.numericText())
                                Text(percentString(item.percentChange))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.percentChange >= 0 ? DS.ColorToken.success : DS.ColorToken.danger)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityIdentifier("insights.section.comparisons")
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

                    if !vm.serviceProfitability.isEmpty {
                        Divider()

                        VStack(spacing: 0) {
                            ForEach(Array(vm.serviceProfitability.prefix(5).enumerated()), id: \.element.id) { index, service in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(service.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(String(format: localized("insights.service_profitability.detail_fmt", value: "%@ • %d sold • avg %@"), service.category, service.count, service.averageTicket.moneyString))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(service.revenue.moneyString)
                                            .font(.subheadline.bold())
                                        Text(percentString(service.trendPercent))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(service.trendPercent >= 0 ? DS.ColorToken.success : DS.ColorToken.danger)
                                    }
                                }
                                .padding(.vertical, 8)
                                .accessibilityElement(children: .combine)

                                if index < min(vm.serviceProfitability.count, 5) - 1 { Divider() }
                            }
                        }
                    }
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
                            Text("\(item.count)").font(.caption).foregroundStyle(.secondary)
                            Text(item.amount.moneyString).font(.subheadline.weight(.bold))
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
                        .foregroundStyle(by: .value(localized("insights.chart.category", value: "Category"), data.name))
                    }
                    .frame(height: 155)
                    .chartLegend(.hidden)
                    .overlay {
                        VStack {
                            Text("\(vm.categoryDistribution.reduce(0, { $0 + $1.count }))").font(.headline)
                            Text(localized("insights.visits_lowercase", value: "visits")).font(.caption2).foregroundStyle(.secondary)
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

    private func lapsedClientsCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.lapsedClients", label: localized("insights.lapsed_clients.title", value: "Lapsed Clients"))
                HStack {
                    Text(localized("insights.lapsed_clients.title", value: "Lapsed Clients")).font(.headline)
                    Spacer()
                    Text("\(vm.lapsedClients.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                if vm.lapsedClients.isEmpty {
                    emptyState(icon: "person.crop.circle.badge.checkmark", message: localized("insights.lapsed_clients.empty", value: "No 90-day lapsed clients"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.lapsedClients.enumerated()), id: \.element.id) { index, client in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(client.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(String(format: localized("insights.lapsed_clients.detail_fmt", value: "%@ • %d days since last visit"), client.petNames, client.daysSinceLastVisit))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    Text(client.totalSpent.moneyString)
                                        .font(.subheadline.bold())
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        messageLapsedClient(client)
                                    } label: {
                                        Label(NSLocalizedString("dashboard.message", comment: ""), systemImage: "message.fill")
                                    }
                                    .disabled(client.phone == nil)
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("insights.lapsed.message.\(index)")

                                    Button {
                                        scheduleLapsedClient(client)
                                    } label: {
                                        Label(localized("insights.action.schedule", value: "Schedule"), systemImage: "calendar.badge.plus")
                                    }
                                    .disabled(client.primaryPetUUID == nil || isSchedulingRecall)
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("insights.lapsed.schedule.\(index)")
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 10)

                            if index < vm.lapsedClients.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.lapsedClients")
    }

    private func topClientsCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                lowerSectionAccessibilityAnchor(identifier: "insights.section.topClients", label: localized("insights.top_clients", value: "Top Clients"))
                Text(localized("insights.top_clients", value: "Top Clients")).font(.headline)

                if vm.topClients.isEmpty {
                    emptyState(icon: "person.crop.circle", message: localized("insights.top_clients.empty", value: "No client data yet"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.topClients.enumerated()), id: \.element.id) { index, client in
                            HStack {
                                Text("\(index + 1)").font(.caption2.bold()).frame(width: 20)
                                Text(client.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(client.totalSpent.moneyString).font(.subheadline.bold())
                            }
                            .padding(.vertical, 8)
                            if index < vm.topClients.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.section.topClients")
    }

    private func metricLabel(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                            let csvDoc = vm.generateInsightsCSVDocument()
                            reportPDFData = await pdfData
                            reportCSVDocument = csvDoc
                        }
                        isPreparingReport = false
                    }
                } label: {
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
            rows: visitDrilldownRows(rows.isEmpty ? vm.revenueDrilldown : rows)
        )
    }

    private func showAverageVisitDrilldown(_ vm: InsightsViewModel) {
        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.average_visit_title", value: "Average Visit Detail"),
            subtitle: localized("insights.drilldown.average_visit_subtitle", value: "Highest-value visits in the selected revenue window"),
            rows: visitDrilldownRows(vm.revenueDrilldown.sorted { $0.total > $1.total })
        )
    }

    private func showRetentionDrilldown(_ vm: InsightsViewModel) {
        let lapsedRows = vm.lapsedClients.map {
            InsightsDrilldownRow(
                title: $0.name,
                subtitle: "\($0.petNames) • \($0.daysSinceLastVisit) days since last visit",
                trailing: $0.totalSpent.moneyString
            )
        }

        let rows = lapsedRows.isEmpty
            ? vm.topClients.map {
                InsightsDrilldownRow(
                    title: $0.name,
                    subtitle: "\($0.visitCount) visits",
                    trailing: $0.totalSpent.moneyString
                )
            }
            : lapsedRows

        selectedDrilldown = InsightsDrilldown(
            title: localized("insights.drilldown.retention_title", value: "Retention Detail"),
            subtitle: lapsedRows.isEmpty
                ? localized("insights.drilldown.top_recurring_clients", value: "Top recurring clients")
                : localized("insights.drilldown.clients_ready_for_recall", value: "Clients ready for recall"),
            rows: rows
        )
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

    private func messageLapsedClient(_ client: InsightsViewModel.LapsedClientData) {
        guard let phone = client.phone,
              let sms = PhoneUtils.smsURLString(phone, body: client.suggestedMessage)
        else { return }
        URLOpener.open(sms)
    }

    private func scheduleLapsedClient(_ client: InsightsViewModel.LapsedClientData) {
        guard let petUUID = client.primaryPetUUID else { return }
        guard !isSchedulingRecall else { return }

        isSchedulingRecall = true
        let container = modelContext.container
        let date = suggestedRecallDate()

        Task {
            do {
                let scheduler = await Task.detached(priority: .utility) {
                    RecallSchedulingActor(modelContainer: container)
                }.value
                let recall = try await scheduler.scheduleRecall(forPetID: petUUID, date: date)
                await MainActor.run {
                    scheduleConfirmation = String(
                        format: localized("insights.recall.scheduled_fmt", value: "%@ is scheduled for %@."),
                        recall.petName,
                        recall.date.formatted(date: .abbreviated, time: .shortened)
                    )
                    showingScheduleConfirmation = true
                    isSchedulingRecall = false
                }
            } catch {
                await MainActor.run {
                    scheduleConfirmation = String(
                        format: localized("insights.recall.error_fmt", value: "Could not schedule this appointment: %@"),
                        error.localizedDescription
                    )
                    showingScheduleConfirmation = true
                    isSchedulingRecall = false
                }
            }
        }
    }

    private func suggestedRecallDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        return calendar.nextDate(
            after: tomorrow,
            matching: DateComponents(hour: 9, minute: 0),
            matchingPolicy: .nextTime
        ) ?? tomorrow
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
    
    var body: some View {
        Card {
            HStack(alignment: .bottom, spacing: 8) {
                if type == .bar {
                    ForEach(0..<10) { i in
                        SkeletonRect()
                            .frame(height: CGFloat.random(in: 40...120))
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
