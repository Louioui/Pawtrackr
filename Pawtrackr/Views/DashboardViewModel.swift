//
//  DashboardViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import OSLog

private let dashboardLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Dashboard")

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
    private let revenueWindowDays = 7
    private let galleryWindowDays = 14
    private let recentClientLimit = 5
    private let overduePetLimit  = 5

    private var dataStore: DataStoreService
    private var eventBus: GlobalEventBus
    private var observationTask: Task<Void, Never>?

    init(dataStore: DataStoreService, eventBus: GlobalEventBus) {
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.repository = DashboardRepository(modelContainer: dataStore.container)

        // Use [weak self] so the for-await loop does not retain the VM.
        // The eventBus stream never terminates on its own; the loop exits
        // naturally when self deallocates and the next event arrives.
        self.observationTask = Task { [weak self] in
            for await event in eventBus.stream {
                guard let self else { return }
                switch event {
                case .checkoutCompleted(_), .refreshRequired:
                    await self.refresh()
                default:
                    break
                }
            }
        }

        Task { [weak self] in await self?.refresh() }
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
            let visitRepo = VisitRepository(modelContainer: repository.modelContext.container, eventBus: eventBus)
            _ = try await visitRepo.checkIn(from: appointment)
            await refresh()
        } catch {
            setDashboardError(error, source: #function)
        }
    }

    func checkInPet(_ pet: Pet) async {
        guard pet.activeVisit == nil else { return }

        do {
            let visitRepo = VisitRepository(modelContainer: repository.modelContext.container, eventBus: eventBus)
            _ = try await visitRepo.checkIn(pet: pet, date: Date.now)
            await refresh()
        } catch {
            setDashboardError(error, source: #function)
        }
    }

    // MARK: - Private fetches

    private func fetchUpcomingAppointments() async {
        do {
            upcomingAppointments = try await repository.fetchUpcomingAppointments(limit: 5)
        } catch {
            setDashboardError(error, source: #function)
            upcomingAppointments = []
        }
    }

    private func fetchOverduePets() async {
        do {
            overduePets = try await repository.fetchOverduePets(limit: overduePetLimit)
        } catch {
            setDashboardError(error, source: #function)
            overduePets = []
        }
    }

    private func setDashboardError(_ error: Error, source: String = #function) {
        // Log the underlying error so we can identify which fetch failed
        // (the alert message from SwiftData is unhelpful by itself).
        dashboardLog.error("[\(source)] \(String(describing: error))")
        // Don't surface partial fetch failures as a blocking alert — sections
        // that fail simply render empty. We still log so issues are visible.
        // If you want to re-enable the alert for a specific source, uncomment:
        // appError = .database("\(source): \(error.localizedDescription)")
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
            setDashboardError(error, source: #function)
            kpi = KPI()
        }
    }

    private func fetchActiveVisits() async {
        do {
            activeVisits = try await repository.fetchActiveVisits()
        } catch {
            setDashboardError(error, source: #function)
            activeVisits = []
        }
    }

    private func fetchRecentClients() async {
        do {
            recentClients = try await repository.fetchRecentClients(limit: recentClientLimit)
        } catch {
            setDashboardError(error, source: #function)
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
            setDashboardError(error, source: #function)
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
            setDashboardError(error, source: #function)
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
