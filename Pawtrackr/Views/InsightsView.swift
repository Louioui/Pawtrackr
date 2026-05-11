//
//  InsightsView.swift
//  Pawtrackr
//

import SwiftUI
import Charts
import SwiftData
import CoreTransferable

struct InsightsView: View {
    @Environment(DataStoreService.self) private var dataStore
    @Environment(GlobalEventBus.self) private var eventBus
    @State private var viewModel: InsightsViewModel?
    @State private var reportPDFData: Data?
    @State private var isPreparingReport = false

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
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
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
        .background(DS.ColorToken.background)
        .navigationTitle("Insights")
        .refreshable {
            await viewModel?.refresh()
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
                monthlyPerformanceCard(vm)
                serviceRevenueCard(vm)
                paymentMixCard(vm)
                categoryCard(vm)
                retentionCard(vm)
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
                title: "Revenue",
                value: vm.totalRevenue.moneyString,
                icon: "dollarsign.circle.fill",
                color: DS.ColorToken.primary,
                accessibilityIdentifier: "insights.kpi.revenue"
            )
            kpiTile(
                title: "Avg Visit",
                value: vm.averageVisitValue > 0 ? vm.averageVisitValue.moneyString : "—",
                icon: "chart.line.uptrend.xyaxis",
                color: DS.ColorToken.success,
                accessibilityIdentifier: "insights.kpi.avgVisit"
            )
            kpiTile(
                title: "Retention",
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Revenue

    private func revenueCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Revenue")
                            .font(.headline)
                        Text("\(vm.revenuePeriodDays)-day window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            x: .value("Day", data.date, unit: .day),
                            y: .value("Revenue", (data.amount as NSDecimalNumber).doubleValue)
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
                        Label("\(vm.totalVisitsInPeriod) visits", systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("Avg \(vm.averageVisitValue.moneyString)", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
                    Task { await vm.refreshRevenue() }
                } label: {
                    Text("\(period)D")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(minWidth: 34)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(isSelected ? DS.ColorToken.primary : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.ColorToken.surface, in: Capsule())
    }

    // MARK: - Monthly Performance

    private func monthlyPerformanceCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Monthly Performance").font(.headline)

                if vm.monthlyGrowth.isEmpty {
                    emptyState(icon: "chart.line.uptrend.xyaxis", message: "No monthly data yet")
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
                                Text("\(data.visitCount) visits").font(.caption2).foregroundStyle(.secondary)
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
                Text("Top Services").font(.headline)

                if vm.serviceDistribution.isEmpty {
                    emptyState(icon: "scissors", message: "No service data yet")
                } else {
                    let top5 = Array(vm.serviceDistribution.prefix(5))
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
    }

    private func paymentMixCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Payment Mix").font(.headline)

                if vm.paymentMethodDistribution.isEmpty {
                    emptyState(icon: "creditcard", message: "No payments recorded yet")
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
    }

    private func categoryCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Visits by Category").font(.headline)

                if vm.categoryDistribution.isEmpty {
                    emptyState(icon: "square.grid.2x2", message: "No category data yet")
                } else {
                    Chart(vm.categoryDistribution) { data in
                        SectorMark(
                            angle: .value("Count", data.count),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Category", data.name))
                    }
                    .frame(height: 155)
                    .chartLegend(.hidden)
                    .overlay {
                        VStack {
                            Text("\(vm.categoryDistribution.reduce(0, { $0 + $1.count }))").font(.headline)
                            Text("visits").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func retentionCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Client Retention").font(.headline)

                if vm.retentionSeries.isEmpty {
                    emptyState(icon: "person.2", message: "Not enough client data yet")
                } else {
                    HStack(spacing: 30) {
                        Chart(vm.retentionSeries) { data in
                            SectorMark(angle: .value("Value", data.value), innerRadius: .ratio(0.7))
                                .foregroundStyle(data.label == "Recurring" ? DS.ColorToken.primary : Color.gray.opacity(0.2))
                        }
                        .frame(width: 100, height: 100)
                        .chartLegend(.hidden)
                        .overlay {
                            Text("\(Int(vm.retentionRate * 100))%").font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            metricLabel(title: "Retention Rate", value: "\(Int(vm.retentionRate * 100))%", color: DS.ColorToken.primary)
                            metricLabel(title: "Churn Risk", value: "\(vm.churnRiskCount) clients", color: DS.ColorToken.warning)
                        }
                    }
                }
            }
        }
    }

    private func topClientsCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Top Clients").font(.headline)

                if vm.topClients.isEmpty {
                    emptyState(icon: "person.crop.circle", message: "No client data yet")
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
    }

    private func metricLabel(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    private var reportButton: some View {
        Group {
            if let pdfData = reportPDFData {
                let doc = ReportDocument(pdfData: pdfData, filename: "Report.pdf")
                ShareLink(item: doc, preview: SharePreview("Report", image: Image(systemName: "doc.pdf"))) {
                    Label("Export", systemImage: "doc.badge.arrow.up")
                }
            } else {
                Button {
                    isPreparingReport = true
                    Task {
                        if let vm = viewModel {
                            let summary = await vm.generateReportSummary()
                            reportPDFData = await BusinessReportService.shared.generateMonthlyReportAsync(summary: summary)
                        }
                        isPreparingReport = false
                    }
                } label: {
                    if isPreparingReport { ProgressView() } else { Label("Export", systemImage: "doc.badge.arrow.up") }
                }
                .disabled(isPreparingReport)
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
