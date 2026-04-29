//
//  InsightsViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import Observation

@Observable
@MainActor
class InsightsViewModel {
    struct RevenueData: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Decimal
    }
    
    struct DistributionData: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        var revenue: Decimal = .zero
    }
    
    struct MonthlyGrowthData: Identifiable {
        let id = UUID()
        let month: String
        let revenue: Decimal
        let visitCount: Int
    }

    struct TopClientData: Identifiable {
        let id = UUID()
        let name: String
        let totalSpent: Decimal
        let visitCount: Int
    }

    var revenueSeries: [RevenueData] = []
    var serviceDistribution: [DistributionData] = []
    var categoryDistribution: [DistributionData] = []
    var topClients: [TopClientData] = []
    var monthlyGrowth: [MonthlyGrowthData] = []
    
    var totalRevenue: Decimal = .zero
    var averageVisitValue: Decimal = .zero
    
    private let repository: DashboardRepositoryProtocol
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.repository = DashboardRepository(modelContainer: modelContext.container)
    }

    func refresh() async {
        await fetchRevenue()
        await fetchDistributions()
        await fetchTopClients()
        await fetchMonthlyGrowth()
    }

    private func fetchRevenue() async {
        do {
            let bucket = try await repository.fetchRevenueSeries(days: 30)
            revenueSeries = bucket.map { RevenueData(date: $0.key, amount: $0.value) }.sorted { $0.date < $1.date }
            
            totalRevenue = revenueSeries.reduce(.zero) { $0 + $1.amount }
            
            _ = try await repository.fetchKPIs()
        } catch {
            print("Insights error (revenue): \(error)")
        }
    }

    private func fetchDistributions() async {
        do {
            _ = try await repository.fetchServiceDistribution(days: 30)
            
            // To get revenue per service, we need to fetch visits for the period
            let cal = Calendar.current
            let end = cal.startOfDay(for: .now).addingTimeInterval(86400)
            let start = cal.date(byAdding: .day, value: -30, to: end) ?? end
            
            let descriptor = FetchDescriptor<Visit>(
                predicate: #Predicate<Visit> { v in
                    if let endedAt = v.endedAt {
                        return endedAt >= start && endedAt < end
                    } else {
                        return false
                    }
                }
            )
            let visits = try modelContext.fetch(descriptor)
            
            var svcData: [String: (count: Int, revenue: Decimal)] = [:]
            for v in visits {
                for item in v.items {
                    svcData[item.name, default: (0, .zero)].count += 1
                    svcData[item.name, default: (0, .zero)].revenue += item.lineTotal
                }
            }
            
            serviceDistribution = svcData.map { name, stats in
                DistributionData(name: name, count: stats.count, revenue: stats.revenue)
            }.sorted { $0.revenue > $1.revenue }
            
            let cat = try await repository.fetchCategoryDistribution(days: 30)
            categoryDistribution = cat.map { DistributionData(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        } catch {
            print("Insights error (dist): \(error)")
        }
    }

    private func fetchTopClients() async {
        let descriptor = FetchDescriptor<Client>()
        do {
            let clients = try modelContext.fetch(descriptor)
            topClients = clients.map { client in
                let visits = client.pets.flatMap { $0.visits }.filter { $0.isCompleted }
                let spent = visits.reduce(Decimal.zero) { $0 + $1.total }
                return TopClientData(name: client.fullName, totalSpent: spent, visitCount: visits.count)
            }
            .filter { $0.totalSpent > 0 }
            .sorted { $0.totalSpent > $1.totalSpent }
            .prefix(10)
            .map { $0 }
        } catch {
            print("Insights error (top clients): \(error)")
        }
    }
    
    private func fetchMonthlyGrowth() async {
        let cal = Calendar.current
        let now = Date()
        var growth: [MonthlyGrowthData] = []
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        
        for i in (0..<6).reversed() {
            guard let monthDate = cal.date(byAdding: .month, value: -i, to: now),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
                  let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { continue }
            
            let descriptor = FetchDescriptor<Visit>(
                predicate: #Predicate<Visit> { v in
                    if let endedAt = v.endedAt {
                        return endedAt >= monthStart && endedAt < monthEnd
                    } else {
                        return false
                    }
                }
            )
            
            do {
                let visits = try modelContext.fetch(descriptor)
                let revenue = visits.reduce(Decimal.zero) { $0 + $1.total }
                growth.append(MonthlyGrowthData(
                    month: monthFormatter.string(from: monthStart),
                    revenue: revenue,
                    visitCount: visits.count
                ))
            } catch {
                print("Insights error (monthly growth): \(error)")
            }
        }
        self.monthlyGrowth = growth
    }
}
