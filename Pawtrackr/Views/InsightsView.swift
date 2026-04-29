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
