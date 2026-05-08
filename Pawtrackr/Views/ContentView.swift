//
//  ContentView.swift
//  Pawtrackr
//
//  Cross-platform main content view.
//  Uses NavigationSplitView for macOS/iPad and TabView for iPhone.
//

import SwiftUI
import SwiftData
import OSLog

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Environment(AuthenticationViewModel.self) private var authViewModel

    @State private var router = NavigationRouter()
    @State private var sidebarSelection: NavigationItem? = .dashboard
    @State private var tabSelection: NavigationItem = .dashboard
    @State private var showingNewClientSheet = false
    /// Last-handled (kind, uuid, timestamp) used to dedupe near-simultaneous
    /// navigation requests coming from both `.onReceive` and `consumePendingNavigation`
    /// at app launch / cold-start time.
    @State private var lastNavigationDedupeKey: String?
    @State private var lastNavigationDedupeAt: Date = .distantPast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var sharedNamespace

    var body: some View {
        rootContent
            .environment(router)
            .onChange(of: appSettings.currencySymbol) { _, newValue in
                Formatters.updateCurrencySymbol(newValue)
            }
            .onChange(of: sidebarSelection) { _, newValue in
                if let newValue {
                    router.activeNavigationItem = newValue
                }
            }
            .onChange(of: tabSelection) { _, newValue in
                router.activeNavigationItem = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .showNewClientSheet)) { _ in
                consumePendingNewClientRequest()
                showingNewClientSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToPet)) { notification in
                handleNavigation(notification, type: .pet)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToClient)) { notification in
                handleNavigation(notification, type: .client)
            }
            .onReceive(NotificationCenter.default.publisher(for: .clientOpenRequested)) { notification in
                guard let id = notification.requestedClientID,
                      let client = modelContext.model(for: id) as? Client else { return }
                selectClientsSurface()
                router.popClientsToRoot()
                router.navigateToClient(client)
                NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                    ClientDidCreateKey.clientID.rawValue: id,
                    ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.navigated.rawValue
                ])
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectNavigationItem)) { notification in
                guard let item = notification.requestedNavigationItem else { return }
                selectSurface(item, resetPath: notification.shouldResetNavigationPath)
            }
            .sheet(isPresented: $showingNewClientSheet) {
                NewClientSheet(modelContext: modelContext)
            }
            .onAppear {
                router.activeNavigationItem = horizontalSizeClass == .compact ? tabSelection : (sidebarSelection ?? .dashboard)
                consumePendingNewClientRequest()
                consumePendingNavigation()
            }
    }

    private enum NavigationType { case pet, client }

    private func handleNavigation(_ notification: Notification, type: NavigationType) {
        guard let uuid = notification.userInfo?["uuid"] as? UUID else { return }

        // Dedupe near-simultaneous fires (e.g. `.onReceive` + `consumePendingNavigation`
        // on cold launch). 1.5s window is generous; legitimate re-navigation by user
        // tap will exceed this trivially.
        let dedupeKey = "\(type)-\(uuid)"
        let now = Date()
        if dedupeKey == lastNavigationDedupeKey, now.timeIntervalSince(lastNavigationDedupeAt) < 1.5 {
            return
        }

        switch type {
        case .client:
            var descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == uuid })
            descriptor.fetchLimit = 1
            do {
                if let client = try modelContext.fetch(descriptor).first {
                    selectClientsSurface()
                    router.popClientsToRoot()
                    router.navigateToClient(client)
                    lastNavigationDedupeKey = dedupeKey
                    lastNavigationDedupeAt = now
                    clearPendingNavigation(kind: .client, uuid: uuid)
                }
            } catch {
                Logger.contentNav.error("Client navigation fetch failed: \(String(describing: error))")
            }

        case .pet:
            var petDescriptor = FetchDescriptor<Pet>(predicate: #Predicate { $0.uuid == uuid })
            petDescriptor.fetchLimit = 1
            do {
                if let pet = try modelContext.fetch(petDescriptor).first, let owner = pet.owner {
                    selectClientsSurface()
                    router.popClientsToRoot()
                    router.navigateToClient(owner)
                    router.navigateToPet(pet)
                    lastNavigationDedupeKey = dedupeKey
                    lastNavigationDedupeAt = now
                    clearPendingNavigation(kind: .pet, uuid: uuid)
                }
            } catch {
                Logger.contentNav.error("Pet navigation fetch failed: \(String(describing: error))")
            }
        }
    }

    private func selectClientsSurface() {
        selectSurface(.clients)
    }

    private func selectSurface(_ item: NavigationItem, resetPath: Bool = false) {
        sidebarSelection = item
        tabSelection = item
        router.activeNavigationItem = item
        if resetPath {
            router.popToRoot()
        }
    }

    private func consumePendingNewClientRequest() {
        guard UserDefaults.standard.string(forKey: AppMenuCommand.pendingNewClientRequestKey) != nil else { return }
        UserDefaults.standard.removeObject(forKey: AppMenuCommand.pendingNewClientRequestKey)
        showingNewClientSheet = true
    }

    private func consumePendingNavigation() {
        guard let kindRaw = UserDefaults.standard.string(forKey: PendingNavigationCommand.kindKey),
              let kind = PendingNavigationCommand.Kind(rawValue: kindRaw),
              let uuidRaw = UserDefaults.standard.string(forKey: PendingNavigationCommand.uuidKey),
              let uuid = UUID(uuidString: uuidRaw) else { return }

        let type: NavigationType = kind == .pet ? .pet : .client
        handleNavigation(Notification(name: .navigateToClient, object: nil, userInfo: ["uuid": uuid]), type: type)
    }

    private func clearPendingNavigation(kind: PendingNavigationCommand.Kind, uuid: UUID) {
        guard UserDefaults.standard.string(forKey: PendingNavigationCommand.kindKey) == kind.rawValue,
              UserDefaults.standard.string(forKey: PendingNavigationCommand.uuidKey) == uuid.uuidString else { return }
        UserDefaults.standard.removeObject(forKey: PendingNavigationCommand.kindKey)
        UserDefaults.standard.removeObject(forKey: PendingNavigationCommand.uuidKey)
    }

    // MARK: - Views

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        splitView
        #else
        if horizontalSizeClass == .compact {
            tabView
        } else {
            splitView
        }
        #endif
    }

    private var tabView: some View {
        TabView(selection: $tabSelection) {
            NavigationStack(path: $router.dashboardPath) {
                DashboardView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(NavigationItem.dashboard)

            NavigationStack(path: $router.clientsPath) {
                ClientsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label("Clients", systemImage: "person.3.fill") }
            .tag(NavigationItem.clients)

            NavigationStack(path: $router.insightsPath) {
                InsightsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            .tag(NavigationItem.insights)

            NavigationStack(path: $router.settingsPath) {
                SettingsView(wrapsInNavigationStack: false)
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(NavigationItem.settings)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            splitViewDetail
        }
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 700)
        #endif
    }

    @ViewBuilder
    private var splitViewDetail: some View {
        switch sidebarSelection {
        case .dashboard:
            NavigationStack(path: $router.dashboardPath) {
                DashboardView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .clients:
            NavigationStack(path: $router.clientsPath) {
                ClientsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .insights:
            NavigationStack(path: $router.insightsPath) {
                InsightsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .settings:
            NavigationStack(path: $router.settingsPath) {
                SettingsView(wrapsInNavigationStack: false)
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .none:
            Text("Select an item")
        }
    }

    // MARK: - Navigation Destination Factory

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .clientDetail(let client):
            ClientDetailView(client: client)

        case .petDetail(let pet):
            PetDetailView(pet: pet, namespace: sharedNamespace)

        case .visitDetail(let visit):
            VisitDetailView(visit: visit)

        case .petHistory(let pet):
            PetHistoryView(pet: pet, wrapsInNavigationStack: false)

        case .checkout(let pet):
            CheckoutView(pet: pet, visit: pet.activeVisit)
        }
    }
}

private extension Logger {
    static let contentNav = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ContentNavigation")
}
