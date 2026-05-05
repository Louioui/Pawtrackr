//
//  DashboardViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Converted from ObservableObject/@Published to @Observable so that
// @State var vm in DashboardView correctly observes property changes.
@Observable
@MainActor
final class DashboardViewModel {

    struct KPI {
        var appointmentsToday: Int = 0
        var inProgressCount: Int = 0
        var revenueToday: Decimal = .zero
        var revenueYesterday: Decimal = .zero
        var completedToday: Int = 0

        var appointmentsTodayText: String { "\(appointmentsToday)" }
        @MainActor var revenueTodayString: String { revenueToday.moneyString }

        var revenueTrend: Double? {
            guard revenueYesterday > 0 else { return nil }
            let today    = (revenueToday    as NSDecimalNumber).doubleValue
            let yesterday = (revenueYesterday as NSDecimalNumber).doubleValue
            return (today - yesterday) / yesterday
        }
    }

    struct RevenuePoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Decimal
        var amountDouble: Double { (amount as NSDecimalNumber).doubleValue }
    }

    struct GalleryItem: Identifiable, @unchecked Sendable {
        let id = UUID()
        #if canImport(UIKit)
        let uiImage: UIImage?
        #elseif canImport(AppKit)
        let nsImage: NSImage?
        #endif
    }

    // MARK: - Observable state
    var kpi = KPI()
    var activeVisits: [Visit] = []
    var upcomingAppointments: [Appointment] = []
    var recentClients: [Client] = []
    var overduePets: [Pet] = []
    var revenueSeries: [RevenuePoint] = []
    var gallery: [GalleryItem] = []
    var appError: AppError? = nil

    // MARK: - Private
    private var isRefreshing = false
    private let repository: DashboardRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = []
    private let revenueWindowDays = 7
    private let galleryWindowDays = 14
    private let recentClientLimit = 5
    private let overduePetLimit  = 5

    init(modelContext: ModelContext, repository: DashboardRepositoryProtocol? = nil) {
        self.repository = repository ?? DashboardRepository(modelContainer: modelContext.container)
        observeDashboardRefreshTriggers()
    }

    // MARK: - Public

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        appError = nil

        async let kpis:    () = fetchKPIs()
        async let active:  () = fetchActiveVisits()
        async let upcoming:() = fetchUpcomingAppointments()
        async let clients: () = fetchRecentClients()
        async let overdue: () = fetchOverduePets()
        async let revenue: () = buildRevenueSeries(days: revenueWindowDays)
        async let gallery: () = buildGallery(days: galleryWindowDays)

        _ = await [kpis, active, upcoming, clients, overdue, revenue, gallery]
    }

    func checkInFromAppointment(_ appointment: Appointment) async {
        do {
            let visitRepo = VisitRepository(modelContainer: repository.modelContext.container)
            _ = try await visitRepo.checkIn(from: appointment)
            await refresh()
        } catch {
            setDashboardError(error)
        }
    }

    // MARK: - Private fetches

    private func fetchUpcomingAppointments() async {
        do {
            upcomingAppointments = try await repository.fetchUpcomingAppointments(limit: 5)
        } catch {
            setDashboardError(error)
            upcomingAppointments = []
        }
    }

    private func fetchOverduePets() async {
        do {
            overduePets = try await repository.fetchOverduePets(limit: overduePetLimit)
        } catch {
            setDashboardError(error)
            overduePets = []
        }
    }

    private func observeDashboardRefreshTriggers() {
        NotificationCenter.default.publisher(for: .visitDidComplete)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ModelContext.didSave)
            .debounce(for: .milliseconds(750), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
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
                inProgressCount:   stats.inProgressCount,
                revenueToday:      stats.revenueToday,
                revenueYesterday:  stats.revenueYesterday,
                completedToday:    stats.completedToday
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
            guard !Task.isCancelled else { return }
            revenueSeries = makeRevenueSeries(from: bucket, days: days, calendar: cal, end: end)
        } catch {
            setDashboardError(error)
            revenueSeries = []
        }
    }

    private func buildGallery(days: Int) async {
        do {
            let photos = try await repository.fetchGalleryImages(days: days, limit: 12)
            guard !Task.isCancelled else { return }
            let items = await Task.detached(priority: .userInitiated) {
                photos.map { data -> GalleryItem in
                    let decoded = ImageCache.shared.image(data: data, maxDimension: 300)
                    #if canImport(UIKit)
                    return GalleryItem(uiImage: decoded)
                    #elseif canImport(AppKit)
                    return GalleryItem(nsImage: decoded)
                    #endif
                }
            }.value
            guard !Task.isCancelled else { return }
            gallery = items
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
