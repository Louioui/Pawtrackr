//
//  DashboardViewModel.swift
//  Pawtrackr
//
//  Created by mac on 9/11/25.
//

import Foundation
import SwiftData
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
  struct KPI {
    var appointmentsToday: Int = 0
    var inProgressCount: Int = 0
    var revenueToday: Decimal = .zero
    var completedToday: Int = 0

    var appointmentsTodayText: String { "\(appointmentsToday)" }
    var revenueTodayString: String { revenueToday.moneyString }
  }

  struct RevenuePoint: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Decimal
    var amountDouble: Double { (amount as NSDecimalNumber).doubleValue }
  }

  struct GalleryItem: Identifiable {
    let id = UUID()
    let imageData: Data?
    var uiImage: UIImage? {
      #if os(iOS)
      guard let imageData else { return nil }
      return UIImage(data: imageData)
      #else
      return nil
      #endif
    }
  }

  @Published var kpi = KPI()
  @Published var activeVisits: [Visit] = []
  @Published var recentClients: [Client] = []
  @Published var revenueSeries: [RevenuePoint] = []
  @Published var gallery: [GalleryItem] = []

  private let modelContext: ModelContext
  init(modelContext: ModelContext) { self.modelContext = modelContext }

  func refresh() async {
    await fetchKPIs()
    await fetchActiveVisits()
    await fetchRecentClients()
    await buildRevenueSeries(days: 7)
    await buildGallery(days: 14)
  }

  // MARK: - Fetches

  private func fetchKPIs() async {
    let cal = Calendar.current
    let start = cal.startOfDay(for: .now)
    let end   = cal.date(byAdding: .day, value: 1, to: start)!

    do {
      // Today’s visits by start date
      let todayDesc = FetchDescriptor<Visit>(
        predicate: #Predicate { v in v.startedAt >= start && v.startedAt < end },
        sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
      )
      let todays = try modelContext.fetch(todayDesc)

      let inProg = try modelContext.fetch(FetchDescriptor<Visit>(
        predicate: #Predicate { v in v.endedAt == nil },
        sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
      ))

      let completedToday = todays.filter { $0.endedAt != nil }
      let revenue = completedToday.reduce(Decimal.zero) { sum, v in sum +~ v.total }

      kpi = KPI(
        appointmentsToday: todays.count,
        inProgressCount: inProg.count,
        revenueToday: revenue,
        completedToday: completedToday.count
      )
    } catch {
      kpi = KPI()
      // You can log with OSLog here
    }
  }

  private func fetchActiveVisits() async {
    do {
      activeVisits = try modelContext.fetch(FetchDescriptor<Visit>(
        predicate: #Predicate { v in v.endedAt == nil },
        sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
      ))
    } catch {
      activeVisits = []
    }
  }

  private func fetchRecentClients() async {
    do {
      // Simple heuristic: alphabetic; replace with “by last visit” if you track it
      recentClients = try modelContext.fetch(FetchDescriptor<Client>(
        sortBy: [SortDescriptor(\.lastName, order: .forward)]
      ))
    } catch {
      recentClients = []
    }
  }

  private func buildRevenueSeries(days: Int) async {
    let cal = Calendar.current
    let end = cal.startOfDay(for: .now)
    let start = cal.date(byAdding: .day, value: -days + 1, to: end)!

    do {
      let desc = FetchDescriptor<Visit>(
        predicate: #Predicate { v in
          v.endedAt != nil &&
          v.sortKeyDate >= start &&
          v.sortKeyDate < cal.date(byAdding: .day, value: 1, to: end)!
        },
        sortBy: [SortDescriptor(\.sortKeyDate, order: .reverse)]
      )
      let visits = try modelContext.fetch(desc)

      var bucket: [Date: Decimal] = [:]
      for v in visits {
        let day = cal.startOfDay(for: v.sortKeyDate)
        bucket[day, default: .zero] = bucket[day, default: .zero] +~ v.total
      }
      revenueSeries = (0..<days).compactMap { i in
        let d = cal.date(byAdding: .day, value: -((days - 1) - i), to: end)!
        return RevenuePoint(date: d, amount: bucket[d, default: .zero])
      }
    } catch {
      revenueSeries = []
    }
  }

  private func buildGallery(days: Int) async {
    let cal = Calendar.current
    let end = cal.startOfDay(for: .now)
    let start = cal.date(byAdding: .day, value: -days, to: end)!

    do {
      let desc = FetchDescriptor<Visit>(
        predicate: #Predicate { v in v.sortKeyDate >= start && v.sortKeyDate < end },
        sortBy: [SortDescriptor(\.sortKeyDate, order: .reverse)]
      )
      let visits = try modelContext.fetch(desc)
      let photos = visits.compactMap { $0.afterPhotoData ?? $0.beforePhotoData }
      gallery = photos.prefix(12).map { GalleryItem(imageData: $0) }
    } catch {
      gallery = []
    }
  }
}
