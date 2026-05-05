//
//  InsightsView.swift
//  Pawtrackr
//

import SwiftUI
import Charts
import SwiftData
import CoreTransferable

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var reportPDFData: Data?
    @State private var isPreparingReport = false
    @State private var revenuePeriod: Int = 30

    var body: some View {
        Group {
            if let vm = viewModel, vm.hasLoadedOnce {
                mainContent(vm)
            } else {
                ProgressView("Loading Insights…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.ColorToken.background)
        .navigationTitle("Insights")
        .task {
            guard viewModel == nil else { return }
            let vm = InsightsViewModel(modelContext: modelContext)
            viewModel = vm
            await vm.refresh()
        }
        .refreshable {
            await viewModel?.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                reportButton
            }
        }
        .onChange(of: viewModel?.totalRevenue) { _, _ in
            reportPDFData = nil
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
                categoryCard(vm)
                retentionCard(vm)
                topClientsCard(vm)
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - KPI summary strip

    private func kpiSummaryRow(_ vm: InsightsViewModel) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            kpiTile(
                title: "Revenue",
                value: vm.totalRevenue.moneyString,
                icon: "dollarsign.circle.fill",
                color: DS.ColorToken.primary
            )
            kpiTile(
                title: "Avg Visit",
                value: vm.averageVisitValue > 0 ? vm.averageVisitValue.moneyString : "—",
                icon: "chart.line.uptrend.xyaxis",
                color: DS.ColorToken.success
            )
            kpiTile(
                title: "Retention",
                value: "\(Int(vm.retentionRate * 100))%",
                icon: "person.2.fill",
                color: DS.ColorToken.warning
            )
        }
    }

    private func kpiTile(title: String, value: String, icon: String, color: Color) -> some View {
        Card(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                        Text("Revenue").font(.headline)
                        Text("\(revenuePeriod)-day window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Period", selection: $revenuePeriod) {
                        Text("7D").tag(7)
                        Text("30D").tag(30)
                        Text("90D").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 126)
                    .onChange(of: revenuePeriod) { _, days in
                        guard let vm = viewModel else { return }
                        vm.revenuePeriodDays = days
                        Task { await vm.refreshRevenue() }
                    }
                }

                Text(vm.totalRevenue.moneyString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.ColorToken.primary)

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
                        AxisMarks(values: .stride(by: .day,
                                                  count: revenuePeriod <= 7 ? 1 : revenuePeriod <= 30 ? 5 : 15)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                        }
                    }
                    .frame(height: 155)

                    HStack {
                        Label("\(vm.totalVisitsInPeriod) visit\(vm.totalVisitsInPeriod == 1 ? "" : "s")",
                              systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if vm.averageVisitValue > 0 {
                            Label("Avg \(vm.averageVisitValue.moneyString)",
                                  systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Monthly Performance

    private func monthlyPerformanceCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Monthly Performance").font(.headline)

                let hasData = vm.monthlyGrowth.contains { $0.revenue > .zero }
                if !hasData {
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
                        .symbolSize(36)

                        AreaMark(
                            x: .value("Month", data.month),
                            y: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue)
                        )
                        .foregroundStyle(DS.ColorToken.primary.opacity(0.08))
                    }
                    .frame(height: 155)

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(vm.monthlyGrowth.suffix(3)) { data in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(data.month)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(data.revenue.moneyString)
                                    .font(.subheadline.weight(.bold))
                                Text("\(data.visitCount) visits")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Services").font(.headline)
                    Text("Last 30 days by revenue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(data.revenue.moneyString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(top5.count) * 44)
                }
            }
        }
    }

    // MARK: - Category Distribution

    private func categoryCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Visits by Category").font(.headline)

                if vm.categoryDistribution.isEmpty {
                    emptyState(icon: "square.grid.2x2", message: "No category data yet")
                } else {
                    let totalCount = vm.categoryDistribution.reduce(0) { $0 + $1.count }

                    Chart(vm.categoryDistribution) { data in
                        SectorMark(
                            angle: .value("Count", data.count),
                            innerRadius: .ratio(0.60),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Category", data.name))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 155)
                    .overlay(alignment: .center) {
                        VStack(spacing: 1) {
                            Text("\(totalCount)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("visits")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Text-only legend (chart assigns its own colors internally)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.categoryDistribution.prefix(5)) { data in
                            HStack {
                                Text(data.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(data.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Retention

    private func retentionCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Client Retention").font(.headline)

                if vm.retentionSeries.isEmpty {
                    emptyState(icon: "person.2", message: "Not enough client data yet")
                } else {
                    HStack(alignment: .center, spacing: DS.Spacing.xl) {
                        ZStack {
                            Chart(vm.retentionSeries) { data in
                                SectorMark(
                                    angle: .value("Value", data.value),
                                    innerRadius: .ratio(0.65)
                                )
                                .foregroundStyle(
                                    data.label == "Recurring"
                                        ? DS.ColorToken.primary
                                        : Color.secondary.opacity(0.22)
                                )
                            }
                            .chartLegend(.hidden)
                            .frame(width: 120, height: 120)

                            VStack(spacing: 1) {
                                Text("\(Int(vm.retentionRate * 100))%")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.ColorToken.primary)
                                Text("retained")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Retention Rate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(vm.retentionRate * 100))%")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(DS.ColorToken.primary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Churn Risk")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(vm.churnRiskCount) clients")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DS.ColorToken.warning)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Top Clients

    private func topClientsCard(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text("Top Clients").font(.headline)
                    Spacer()
                    Text("All time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vm.topClients.isEmpty {
                    emptyState(icon: "person.crop.circle", message: "Complete a paid visit to see top clients")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.topClients.enumerated()), id: \.element.id) { index, client in
                            HStack(spacing: 10) {
                                rankBadge(index + 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(client.visitCount) visit\(client.visitCount == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(client.totalSpent.moneyString)
                                    .font(.subheadline.weight(.bold))
                            }
                            .padding(.vertical, 8)

                            if index < vm.topClients.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Report toolbar button

    @ViewBuilder
    private var reportButton: some View {
        if let vm = viewModel, vm.hasLoadedOnce {
            if let pdfData = reportPDFData {
                ShareLink(
                    item: ReportDocument(
                        pdfData: pdfData,
                        filename: "Pawtrackr_Report_\(Date().formatted(.dateTime.month().year())).pdf"
                    ),
                    preview: SharePreview("Monthly Report", image: Image(systemName: "doc.pdf"))
                ) {
                    Label("Export Report", systemImage: "doc.badge.arrow.up")
                }
            } else {
                Button {
                    guard !isPreparingReport else { return }
                    isPreparingReport = true
                    Task {
                        let summary = await vm.generateReportSummary()
                        let data = await BusinessReportService.shared.generateMonthlyReportAsync(summary: summary)
                        reportPDFData = data
                        isPreparingReport = false
                    }
                } label: {
                    if isPreparingReport {
                        ProgressView()
                    } else {
                        Label("Export Report", systemImage: "doc.badge.arrow.up")
                    }
                }
                .disabled(isPreparingReport)
            }
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.35))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
    }

    private func rankBadge(_ rank: Int) -> some View {
        let bg: Color = switch rank {
        case 1:  Color(red: 1.0,  green: 0.78, blue: 0.0)
        case 2:  Color(white: 0.70)
        case 3:  Color(red: 0.80, green: 0.50, blue: 0.20)
        default: Color.secondary.opacity(0.12)
        }
        let fg: Color = rank <= 3 ? .white : .secondary

        return Text("\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(fg)
            .frame(width: 24, height: 24)
            .background(bg, in: Circle())
    }
}
