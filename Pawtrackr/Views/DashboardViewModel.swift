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
  @Published var appError: AppError? = nil

  private let repository: DashboardRepositoryProtocol
  private var cancellables: Set<AnyCancellable> = []
  private let revenueWindowDays = 7
  private let galleryWindowDays = 14
  private let recentClientLimit = 5

  init(modelContext: ModelContext, repository: DashboardRepositoryProtocol? = nil) {
    self.repository = repository ?? DashboardRepository(modelContainer: modelContext.container)
    observeDashboardRefreshTriggers()
  }

  deinit {
    cancellables.forEach { $0.cancel() }
    cancellables.removeAll()
  }

  func refresh() async {
    appError = nil
    await fetchKPIs()
    await fetchActiveVisits()
    await fetchRecentClients()
    await buildRevenueSeries(days: revenueWindowDays)
    await buildGallery(days: galleryWindowDays)
  }

  // MARK: - Fetches

  private func observeDashboardRefreshTriggers() {
    NotificationCenter.default.publisher(for: .visitDidComplete)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.scheduleRefresh()
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: ModelContext.didSave)
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.scheduleRefresh()
      }
      .store(in: &cancellables)
  }

  private func scheduleRefresh() {
    Task { @MainActor [weak self] in
      await self?.refresh()
    }
  }

  private func setDashboardError(_ error: Error) {
    appError = .database(error.localizedDescription)
  }

  private func fetchKPIs() async {
    do {
      let stats = try await repository.fetchKPIs()
      kpi = KPI(
        appointmentsToday: stats.appointmentsToday,
        inProgressCount: stats.inProgressCount,
        revenueToday: stats.revenueToday,
        completedToday: stats.completedToday
      )
    } catch {
      setDashboardError(error)
      kpi = KPI()
    }
  }

  private func fetchActiveVisits() async {
    do {
      activeVisits = try await repository.fetchActiveVisits()
    } catch {
      setDashboardError(error)
      activeVisits = []
    }
  }

  private func fetchRecentClients() async {
    do {
      recentClients = try await repository.fetchRecentClients(limit: recentClientLimit)
    } catch {
      setDashboardError(error)
      recentClients = []
    }
  }

  private func buildRevenueSeries(days: Int) async {
    let cal = Calendar.current
    let end = cal.startOfDay(for: .now)

    do {
        let bucket = try await repository.fetchRevenueSeries(days: days)
        
        // Build the series, filling in missing days with zero
        revenueSeries = makeRevenueSeries(from: bucket, days: days, calendar: cal, end: end)
    } catch {
        setDashboardError(error)
        revenueSeries = []
    }
  }

  private func buildGallery(days: Int) async {
    do {
      let photos = try await repository.fetchGalleryImages(days: days, limit: 12)
      gallery = photos.map { GalleryItem(imageData: $0) }
    } catch {
      setDashboardError(error)
      gallery = []
    }
  }

  private func makeRevenueSeries(from bucket: [Date: Decimal], days: Int, calendar: Calendar, end: Date) -> [RevenuePoint] {
    (0..<days).map { i in
      let date = calendar.date(byAdding: .day, value: -((days - 1) - i), to: end) ?? end
      return RevenuePoint(date: date, amount: bucket[date, default: .zero])
    }
  }
}
