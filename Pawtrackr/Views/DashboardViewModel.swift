//
//  DashboardViewModel.swift
//  Pawtrackr
//
//  Created by mac on 9/11/25.
//

import Foundation
import SwiftData
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class DashboardViewModel: ObservableObject {
  struct KPI {
    var appointmentsToday: Int = 0
    var inProgressCount: Int = 0
    var revenueToday: Decimal = .zero
    var completedToday: Int = 0

    var appointmentsTodayText: String { "\(appointmentsToday)" }
    @MainActor
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

    #if canImport(UIKit)
    var uiImage: UIImage? {
      guard let imageData else { return nil }
      return ImageCache.shared.image(data: imageData, maxDimension: 300)
    }
    #elseif canImport(AppKit)
    var nsImage: NSImage? {
      guard let imageData else { return nil }
      return ImageCache.shared.image(data: imageData, maxDimension: 300)
    }
    #endif
  }

  @Published var kpi = KPI()
  @Published var activeVisits: [Visit] = []
  @Published var recentClients: [Client] = []
  @Published var revenueSeries: [RevenuePoint] = []
  @Published var gallery: [GalleryItem] = []

  private let modelContext: ModelContext
  private var cancellables: Set<AnyCancellable> = []

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    // Auto-refresh dashboard when a checkout completes
    NotificationCenter.default.publisher(for: .visitDidComplete)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [weak self] in
          await self?.refresh()
        }
      }
      .store(in: &cancellables)

    // Also refresh when model context saves (client/pet changes)
    NotificationCenter.default.publisher(for: ModelContext.didSave)
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [weak self] in
          await self?.refresh()
        }
      }
      .store(in: &cancellables)
  }

  deinit {
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()
  }

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

      // Get today's summary for revenue and completed count using a range match (avoids exact-date equality issues)
      let summaryDesc = FetchDescriptor<DaySummary>(
        predicate: #Predicate { summary in summary.day >= start && summary.day < end },
        sortBy: [SortDescriptor(\.day, order: .reverse)]
      )
      let summary = try modelContext.fetch(summaryDesc).first

      kpi = KPI(
        appointmentsToday: todays.count,
        inProgressCount: inProg.count,
        revenueToday: summary?.revenue ?? .zero,
        completedToday: summary?.visitCount ?? 0
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
      // Fetch the 5 most recently active clients.
      var descriptor = FetchDescriptor<Client>(
        sortBy: [SortDescriptor(\.lastVisitDate, order: .reverse)]
      )
      descriptor.fetchLimit = 5
      recentClients = try modelContext.fetch(descriptor)
    } catch {
      recentClients = []
    }
  }

  private func buildRevenueSeries(days: Int) async {
    let cal = Calendar.current
    let end = cal.startOfDay(for: .now)
    let start = cal.date(byAdding: .day, value: -days + 1, to: end)!

    do {
        // Fetch pre-aggregated summaries instead of all visits
        let desc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in
                summary.day >= start && summary.day <= end
            },
            sortBy: [SortDescriptor(\.day)]
        )
        let summaries = try modelContext.fetch(desc)
        
        // Create a dictionary for quick lookups
        let bucket = summaries.reduce(into: [Date: Decimal]()) { dict, summary in
            dict[summary.day] = summary.revenue
        }
        
        // Build the series, filling in missing days with zero
        revenueSeries = (0..<days).map { i in
            let date = cal.date(byAdding: .day, value: -((days - 1) - i), to: end)!
            return RevenuePoint(date: date, amount: bucket[date, default: .zero])
        }
    } catch {
        revenueSeries = []
    }
  }

  private func buildGallery(days: Int) async {
    let cal = Calendar.current
    let end = cal.startOfDay(for: .now)
    guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return }

    do {
      let desc = FetchDescriptor<Visit>(
        predicate: #Predicate { v in v.startedAt >= start && v.startedAt < end },
        sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
      )
      let visits = try modelContext.fetch(desc)
      let photos = visits.compactMap { $0.afterPhotoData ?? $0.beforePhotoData }
      gallery = photos.prefix(12).map { GalleryItem(imageData: $0) }
    } catch {
      gallery = []
    }
  }
}
