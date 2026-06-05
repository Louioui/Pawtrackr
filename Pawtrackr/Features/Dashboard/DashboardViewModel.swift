//
//  DashboardViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import OSLog
import Combine
import SwiftUI

private let dashboardLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Dashboard")

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Observable
@MainActor
final class DashboardViewModel {

    enum State: Equatable {
        case loading
        case loaded
        case error(String)
    }

    struct KPI: Sendable {
        var inProgressCount: Int = 0
        var revenueToday: Decimal = .zero
        var revenueYesterday: Decimal = .zero
        var completedToday: Int = 0

        @MainActor var revenueTodayString: String { revenueToday.moneyString }

        var revenueTrend: Double? {
            guard revenueYesterday > 0 else { return nil }
            let today    = (revenueToday    as NSDecimalNumber).doubleValue
            let yesterday = (revenueYesterday as NSDecimalNumber).doubleValue
            return (today - yesterday) / yesterday
        }
    }

    struct RevenuePoint: Identifiable, Sendable {
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

    struct ChecklistItem: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let isCompleted: Bool
    }

    // MARK: - Observable state
    var state: State = .loading
    var kpi = KPI()
    var activeVisits: [Visit] = []
    var recentClients: [Client] = []
    var overduePets: [Pet] = []
    var revenueSeries: [RevenuePoint] = []
    var gallery: [GalleryItem] = []
    var checklist: [ChecklistItem] = []
    var smartSuggestions: [SmartSuggestion] = []
    var appError: AppError? = nil

    // MARK: - Private
    private var isRefreshing = false
    private let repository: DashboardRepositoryProtocol
    private let predictiveActor: PredictiveSchedulingActor
    private let revenueWindowDays = 7
    private let galleryWindowDays = 14
    private let recentClientLimit = 5
    private let overduePetLimit  = 5

    private var dataStore: DataStoreService
    private var eventBus: GlobalEventBus
    private var observers: [AnyCancellable] = []
    private var observationTask: Task<Void, Never>?

    init(dataStore: DataStoreService, eventBus: GlobalEventBus, repository: DashboardRepositoryProtocol? = nil) {
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.repository = repository ?? DashboardRepository(modelContainer: dataStore.container)
        self.predictiveActor = PredictiveSchedulingActor(modelContainer: dataStore.container)

        setupObservers()
        
        Task { [weak self] in await self?.refresh() }
    }

    deinit {
        // Cannot touch MainActor-isolated `observationTask` from a nonisolated
        // deinit. The task uses `[weak self]` and reacquires self per iteration
        // (see setupObservers), so once the VM is released the next yielded
        // event causes the task to return on its own. The Task object lingers
        // briefly but holds no strong reference to self.
    }

    private func setupObservers() {
        // EventBus Stream
        // Capture the stream outside the Task closure so we don't hold `self`
        // strongly across the for-await suspension. The previous pattern
        // (`guard let self` outside the loop) created a retain cycle: the
        // suspended task kept `self` alive, so the VM never deallocated even
        // after the dashboard was dismissed. Now `self` is reacquired weakly
        // on every iteration.
        let stream = eventBus.stream
        observationTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .checkoutCompleted(_), .refreshRequired:
                    await self.refresh()
                default:
                    break
                }
            }
        }

        // NotificationCenter Observers
        let center = NotificationCenter.default
        let notifications = [
            Notification.Name.clientDidCreate,
            Notification.Name.visitDidStart,
            Notification.Name.visitDidComplete,
            Notification.Name.serviceDidUpdate
        ]

        for name in notifications {
            center.publisher(for: name)
                .sink { [weak self] notif in
                    dashboardLog.info("DashboardViewModel: Received notification \(notif.name.rawValue)")
                    Task { [weak self] in await self?.refresh() }
                }
                .store(in: &observers)
        }
    }

    // MARK: - Public
    func refresh() async {
        dashboardLog.info("DashboardViewModel: Refresh initiated.")
        guard !isRefreshing else {
            dashboardLog.info("DashboardViewModel: Refresh already in progress, skipping.")
            return
        }
        isRefreshing = true
        
        appError = nil

        await PerformanceMonitor.measureAsyncNoThrow(label: "Dashboard.refresh") {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchKPIs() }
                group.addTask { await self.fetchActiveVisits() }
                group.addTask { await self.fetchRecentClients() }
                group.addTask { await self.fetchOverduePets() }
                group.addTask { await self.buildRevenueSeries(days: self.revenueWindowDays) }
                group.addTask { await self.buildGallery(days: self.galleryWindowDays) }
                group.addTask { await self.fetchChecklistStatus() }
                group.addTask { await self.fetchSmartSuggestions() }
            }
        }

        if case .loading = state {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                state = .loaded
            }
        }
        
        isRefreshing = false
        dashboardLog.info("DashboardViewModel: Refresh complete.")
    }
    private func fetchChecklistStatus() async {
        // Since we are on @MainActor, we use a background task for SwiftData fetches
        // that aren't yet in the repository.
        let container = dataStore.container
        do {
            let (isBrandingComplete, isCatalogConfigured, hasClient, hasVisit) = try await Task.detached {
                let context = ModelContext(container)
                
                let configs = try context.fetch(FetchDescriptor<BusinessConfig>())
                let branding = configs.first?.isSetupComplete ?? false
                
                let services = try context.fetch(FetchDescriptor<Service>())
                let catalog = services.contains { ($0.basePrice ?? 0) > 0 }
                
                let clientCount = try context.fetchCount(FetchDescriptor<Client>())
                let visitCount = try context.fetchCount(FetchDescriptor<Visit>())
                
                return (branding, catalog, clientCount > 0, visitCount > 0)
            }.value
            
            checklist = [
                ChecklistItem(title: NSLocalizedString("checklist.branding", value: "Add Business Branding", comment: ""), isCompleted: isBrandingComplete),
                ChecklistItem(title: NSLocalizedString("checklist.catalog", value: "Configure Service Prices", comment: ""), isCompleted: isCatalogConfigured),
                ChecklistItem(title: NSLocalizedString("checklist.client", value: "Add Your First Client", comment: ""), isCompleted: hasClient),
                ChecklistItem(title: NSLocalizedString("checklist.visit", value: "Start Your First Visit", comment: ""), isCompleted: hasVisit)
            ]
        } catch {
            dashboardLog.error("Checklist fetch failed: \(error)")
        }
    }

    func checkInPet(_ pet: Pet) async {
        guard pet.activeVisit == nil else { return }

        do {
            let visitRepo = VisitRepository(modelContainer: dataStore.container, eventBus: eventBus)
            _ = try await visitRepo.checkIn(pet: pet, date: Date.now)
            await refresh()
        } catch {
            setDashboardError(error, source: #function)
        }
    }

    // MARK: - Private fetches

    private func fetchOverduePets() async {
        do {
            let ids = try await repository.fetchOverduePets(limit: overduePetLimit)
            overduePets = ids.compactMap { dataStore.container.mainContext.model(for: $0) as? Pet }
        } catch {
            setDashboardError(error, source: #function)
            overduePets = []
        }
    }

    private func setDashboardError(_ error: Error, source: String = #function) {
        dashboardLog.error("[\(source)] \(String(describing: error))")
        if let appError = error as? AppError {
            self.appError = appError
        } else {
            self.appError = .database(error.localizedDescription)
        }
    }

    private func fetchKPIs() async {
        do {
            let stats = try await repository.fetchKPIs()
            kpi = KPI(
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
            let ids = try await repository.fetchActiveVisits()
            activeVisits = ids.compactMap { dataStore.container.mainContext.model(for: $0) as? Visit }
        } catch {
            setDashboardError(error, source: #function)
            activeVisits = []
        }
    }

    private func fetchRecentClients() async {
        do {
            let ids = try await repository.fetchRecentClients(limit: recentClientLimit)
            recentClients = ids.compactMap { dataStore.container.mainContext.model(for: $0) as? Client }
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

    private func fetchSmartSuggestions() async {
        do {
            smartSuggestions = try await predictiveActor.generateSuggestions()
        } catch {
            dashboardLog.error("fetchSmartSuggestions failed: \(error)")
        }
    }

    private func makeRevenueSeries(from bucket: [Date: Decimal], days: Int, calendar: Calendar, end: Date) -> [RevenuePoint] {
        (0..<days).map { i in
            let date = calendar.date(byAdding: .day, value: -((days - 1) - i), to: end) ?? end
            return RevenuePoint(date: date, amount: bucket[date, default: .zero])
        }
    }
}
