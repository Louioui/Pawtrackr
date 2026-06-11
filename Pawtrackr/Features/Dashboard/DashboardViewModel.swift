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
    var checklist: [ChecklistItem] = []
    var smartSuggestions: [SmartSuggestion] = []
    var appError: AppError? = nil

    // MARK: - Private
    private var isRefreshing = false
    private let repository: DashboardRepositoryProtocol
    private let predictiveActor: PredictiveSchedulingActor
    private let revenueWindowDays = 7
    private let recentClientLimit = 5
    private let overduePetLimit  = 5

    private var dataStore: DataStoreService
    private var eventBus: GlobalEventBus
    private var observers: [AnyCancellable] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var observationTask: Task<Void, Never>?
    private var completedVisitIDs: [PersistentIdentifier] = []

    init(dataStore: DataStoreService, eventBus: GlobalEventBus, repository: DashboardRepositoryProtocol? = nil) {
        dashboardLog.info("DashboardViewModel: Initialized")
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.repository = repository ?? DashboardRepository(modelContext: dataStore.container.mainContext)
        self.predictiveActor = PredictiveSchedulingActor(modelContainer: dataStore.container)

        setupObservers()
        
        Task { [weak self] in await self?.refresh() }
    }

    private func setupObservers() {
        dashboardLog.info("DashboardViewModel: Setting up observers...")
        // EventBus Stream
        let stream = eventBus.stream
        observationTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .checkoutCompleted(let completion):
                    self.markVisitCompleted(completion.visitID)
                    await self.refresh()
                case .refreshRequired:
                    await self.refresh()
                default:
                    break
                }
            }
        }

        // NotificationCenter Observers
        let notifications = [
            Notification.Name.clientDidCreate,
            Notification.Name.visitDidStart,
            Notification.Name.visitDidComplete,
            Notification.Name.serviceDidUpdate
        ]

        for name in notifications {
            dashboardLog.info("DashboardViewModel: Adding observer for \(name.rawValue)")
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notif in
                dashboardLog.info("DashboardViewModel: Received notification \(notif.name.rawValue)")
                let completedVisitID = notif.name == .visitDidComplete ? notif.visitID : nil
                Task { @MainActor [weak self] in
                    if let completedVisitID {
                        self?.markVisitCompleted(completedVisitID)
                    }
                    await self?.refresh()
                }
            }
            notificationObservers.append(observer)
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
        
        dashboardLog.info("DashboardViewModel: Entering TaskGroup.")

        await PerformanceMonitor.measureAsyncNoThrow(label: "Dashboard.refresh") {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { dashboardLog.info("Starting KPI fetch"); await self.fetchKPIs(); dashboardLog.info("Finished KPI fetch") }
                group.addTask { dashboardLog.info("Starting ActiveVisits fetch"); await self.fetchActiveVisits(); dashboardLog.info("Finished ActiveVisits fetch") }
                group.addTask { dashboardLog.info("Starting RecentClients fetch"); await self.fetchRecentClients(); dashboardLog.info("Finished RecentClients fetch") }
                group.addTask { dashboardLog.info("Starting OverduePets fetch"); await self.fetchOverduePets(); dashboardLog.info("Finished OverduePets fetch") }
                group.addTask { dashboardLog.info("Starting RevenueSeries fetch"); await self.buildRevenueSeries(days: self.revenueWindowDays); dashboardLog.info("Finished RevenueSeries fetch") }
                group.addTask { dashboardLog.info("Starting Checklist fetch"); await self.fetchChecklistStatus(); dashboardLog.info("Finished Checklist fetch") }
                group.addTask { dashboardLog.info("Starting Suggestions fetch"); await self.fetchSmartSuggestions(); dashboardLog.info("Finished Suggestions fetch") }
            }
        }
        
        dashboardLog.info("DashboardViewModel: Exited TaskGroup.")
        kpi.inProgressCount = activeVisits.count

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
            let visitRepo = VisitRepository(modelContext: dataStore.container.mainContext, eventBus: eventBus)
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
        dashboardLog.info("DashboardViewModel: Fetching active visits...")
        do {
            let ids = try await repository.fetchActiveVisits()
            dashboardLog.info("DashboardViewModel: Repository returned \(ids.count) visit IDs.")

            let activeIDs = ids.filter { !completedVisitIDs.contains($0) }
            let visits = activeIDs
                .compactMap { dataStore.container.mainContext.model(for: $0) as? Visit }
                .filter { !completedVisitIDs.contains($0.persistentModelID) }
            dashboardLog.info("DashboardViewModel: Resolved \(visits.count) active visits.")
            
            activeVisits = visits
        } catch {
            setDashboardError(error, source: #function)
            activeVisits = []
        }
    }

    private func markVisitCompleted(_ visitID: PersistentIdentifier) {
        if !completedVisitIDs.contains(visitID) {
            completedVisitIDs.append(visitID)
        }
        activeVisits.removeAll { $0.persistentModelID == visitID }
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
