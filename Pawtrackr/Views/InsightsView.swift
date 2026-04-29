//
//  InsightsView.swift
//  Pawtrackr
//

import SwiftUI
import Charts
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let vm = viewModel {
                    revenueSection(vm)
                    retentionSection(vm)
                    growthSection(vm)
                    serviceRevenueSection(vm)
                    categorySection(vm)
                    topClientsSection(vm)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .background(DS.ColorToken.background)
        .navigationTitle("Insights")
        .task {
            if viewModel == nil {
                let vm = InsightsViewModel(modelContext: modelContext)
                await vm.refresh()
                viewModel = vm
            }
        }
        .refreshable {
            await viewModel?.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let vm = viewModel {
                    ShareLink(item: ReportDocument(
                        pdfData: BusinessReportService.shared.generateMonthlyReport(summary: vm.generateReportSummary()),
                        filename: "Pawtrackr_Report_\(Date().formatted(.dateTime.month().year())).pdf"
                    )) {
                        Label("Export Report", systemImage: "doc.badge.arrow.up")
                    }
                }
            }
        }
    }

    private func revenueSection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Revenue (Last 30 Days)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(vm.totalRevenue.moneyString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                
                Chart(vm.revenueSeries) { data in
                    BarMark(
                        x: .value("Day", data.date, unit: .day),
                        y: .value("Revenue", (data.amount as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .frame(height: 180)
            }
        }
    }

    private func retentionSection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("insights.retention", comment: "")).font(.headline)
                
                HStack(spacing: 24) {
                    Chart(vm.retentionSeries) { data in
                        SectorMark(
                            angle: .value("Value", data.value),
                            innerRadius: .ratio(0.7)
                        )
                        .foregroundStyle(by: .value("Type", data.label))
                    }
                    .frame(width: 120, height: 120)
                    .chartLegend(.hidden)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("insights.retention_rate", comment: "")).font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(vm.retentionRate * 100))%").font(.title2.weight(.bold)).foregroundStyle(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("insights.churn_risk", comment: "")).font(.caption).foregroundStyle(.secondary)
                            Text("\(vm.churnRiskCount) clients").font(.title3.weight(.bold)).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func growthSection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monthly Performance").font(.headline)
                
                Chart(vm.monthlyGrowth) { data in
                    LineMark(
                        x: .value("Month", data.month),
                        y: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(.blue)
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                    
                    AreaMark(
                        x: .value("Month", data.month),
                        y: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                .frame(height: 180)
                
                HStack(spacing: 20) {
                    ForEach(vm.monthlyGrowth.suffix(3)) { data in
                        VStack(alignment: .leading) {
                            Text(data.month).font(.caption).foregroundStyle(.secondary)
                            Text(data.revenue.moneyString).font(.subheadline.weight(.bold))
                            Text("\(data.visitCount) visits").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func serviceRevenueSection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top Services by Revenue").font(.headline)
                
                Chart(vm.serviceDistribution.prefix(5)) { data in
                    BarMark(
                        x: .value("Revenue", (data.revenue as NSDecimalNumber).doubleValue),
                        y: .value("Service", data.name)
                    )
                    .foregroundStyle(.green.gradient)
                }
                .frame(height: 200)
            }
        }
    }

    private func categorySection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Visits by Category").font(.headline)
                
                Chart(vm.categoryDistribution) { data in
                    SectorMark(
                        angle: .value("Count", data.count),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .cornerRadius(5)
                    .foregroundStyle(by: .value("Category", data.name))
                }
                .frame(height: 200)
            }
        }
    }

    private func topClientsSection(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Clients").font(.headline)
                
                let clients = vm.topClients
                VStack(spacing: 0) {
                    ForEach(clients) { client in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(client.name).font(.subheadline.weight(.semibold))
                                Text("\(client.visitCount) visits").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(client.totalSpent.moneyString).font(.subheadline.weight(.bold))
                        }
                        .padding(.vertical, 8)
                        
                        if client.id != clients.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
