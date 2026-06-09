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
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    private enum SheetDestination: Identifiable {
        case newClient
        case recentHistory(RecentHistoryViewModel.Scope?)

        var id: String {
            switch self {
            case .newClient:
                return "new-client"
            case .recentHistory(let scope):
                return "recent-history-\(scope?.rawValue ?? "all")"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Environment(AuthenticationViewModel.self) private var authViewModel

    @State private var router = NavigationRouter()
    @State private var sidebarSelection: NavigationItem? = .dashboard
    @State private var tabSelection: NavigationItem = .dashboard
    @State private var presentedSheet: SheetDestination?
    @State private var showFeatureTour: Bool = false
    /// Last-handled (kind, uuid, timestamp) used to dedupe near-simultaneous
    /// navigation requests coming from both `.onReceive` and `consumePendingNavigation`
    /// at app launch / cold-start time.
    @State private var lastNavigationDedupeKey: String?
    @State private var lastNavigationDedupeAt: Date = .distantPast
    /// `defaultLaunchTab` only applies once per cold launch; flipping a tab
    /// later must not snap the user back to their pinned default.
    @State private var hasAppliedDefaultLaunchTab = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
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
                presentedSheet = .newClient
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
                if notification.userInfo?[NavigationSelectionKey.item.rawValue] as? String == "recenthistory" {
                    selectSurface(.dashboard, resetPath: notification.shouldResetNavigationPath)
                    presentedSheet = .recentHistory(nil)
                    return
                }
                guard let item = notification.requestedNavigationItem else { return }
                selectSurface(item, resetPath: notification.shouldResetNavigationPath)
            }
            .adaptiveCover(item: $presentedSheet) { destination in
                switch destination {
                case .newClient:
                    NewClientSheet(modelContext: modelContext)
                case .recentHistory(let scope):
                    NavigationStack {
                        RecentHistoryView(initialScope: scope)
                    }
                }
            }
            .adaptiveCover(isPresented: $showFeatureTour) {
                FeatureTourView {
                    appSettings.hasSeenAppTour = true
                    showFeatureTour = false
                }
                .interactiveDismissDisabled(true)
            }
            .onAppear {
                if !hasAppliedDefaultLaunchTab && !AppRuntime.isUITesting,
                   let tab = NavigationItem(rawValue: appSettings.defaultLaunchTab) {
                    sidebarSelection = tab
                    tabSelection = tab
                }
                hasAppliedDefaultLaunchTab = true
                router.activeNavigationItem = horizontalSizeClass == .compact ? tabSelection : (sidebarSelection ?? .dashboard)
                applyUITestLaunchOverrides()
                consumePendingNewClientRequest()
                consumePendingNavigation()
                evaluateFeatureTourIfReady()
            }
            .onChange(of: appSettings.hasSeenAppTour) { _, seen in
                // Pick up the OnboardingViewModel arming the tour without
                // requiring a fresh ContentView appear.
                if !seen { showFeatureTour = true }
            }
    }

    private func evaluateFeatureTourIfReady() {
        guard !AppRuntime.isUITesting else { return }
        // Don't try to present the tour cover while another modal is up
        // (onboarding cover, what's-new sheet, or a presentedSheet) —
        // SwiftUI only allows one presentation at a time per stack.
        guard presentedSheet == nil else { return }
        if !appSettings.hasSeenAppTour {
            showFeatureTour = true
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

        // Resolve the UUID off the main thread. These fetches fire on cold launch alongside
        // CloudKit warmup, and the original sync path could perceptibly stall the first
        // frame. Background context + PersistentIdentifier hand-off matches the pattern
        // used in ClientDetailViewModel.fetchVisitsAsync and DashboardViewModel.fetchChecklistStatus.
        let container = modelContext.container
        Task { @MainActor in
            let resolvedID: PersistentIdentifier? = await Task.detached(priority: .userInitiated) {
                let bgCtx = ModelContext(container)
                switch type {
                case .client:
                    var d = FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == uuid })
                    d.fetchLimit = 1
                    do {
                        return try bgCtx.fetch(d).first?.persistentModelID
                    } catch {
                        Logger.contentNav.error("Client navigation fetch failed: \(String(describing: error))")
                        return nil
                    }
                case .pet:
                    var d = FetchDescriptor<Pet>(predicate: #Predicate { $0.uuid == uuid })
                    d.fetchLimit = 1
                    do {
                        return try bgCtx.fetch(d).first?.persistentModelID
                    } catch {
                        Logger.contentNav.error("Pet navigation fetch failed: \(String(describing: error))")
                        return nil
                    }
                }
            }.value

            guard let id = resolvedID else { return }

            switch type {
            case .client:
                guard let client = modelContext.model(for: id) as? Client else { return }
                selectClientsSurface()
                router.popClientsToRoot()
                router.navigateToClient(client)
            case .pet:
                guard let pet = modelContext.model(for: id) as? Pet, let owner = pet.owner else { return }
                selectClientsSurface()
                router.popClientsToRoot()
                router.navigateToClient(owner)
                router.navigateToPet(pet)
            }
            lastNavigationDedupeKey = dedupeKey
            lastNavigationDedupeAt = now
            clearPendingNavigation(kind: type == .client ? .client : .pet, uuid: uuid)
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
        presentedSheet = .newClient
    }

    private func applyUITestLaunchOverrides() {
        guard let rawValue = AppRuntime.uiTestingStartTab else { return }

        if rawValue == "recenthistory" {
            selectSurface(.dashboard, resetPath: true)
            presentedSheet = .recentHistory(nil)
            return
        }

        guard let item = NavigationItem(rawValue: rawValue) else { return }

        selectSurface(item, resetPath: true)
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
        Group {
            #if os(macOS)
            splitView
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ecosystemStatusInset
                }
            #else
            if horizontalSizeClass == .compact {
                // On iPhone the TabView already owns the bottom safe area for
                // its tab bar; a bottom safe-area-inset here overlaps with the
                // tab bar and swallows taps on the middle tabs (and on
                // anything near the bottom of the scrollable content, like
                // the active-session row's checkout button). Sync state is
                // already surfaced in the dashboard toolbar's CloudKitStatusView
                // and the top-of-screen CloudKitAccountBanner, so the bottom
                // strip is dropped on compact.
                tabView
            } else {
                splitView
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        ecosystemStatusInset
                    }
            }
            #endif
        }
        .preferredColorScheme(appSettings.preferredColorScheme.swiftUIScheme)
    }

    private var ecosystemStatusInset: some View {
        HStack {
            Spacer(minLength: 0)
            EcosystemStatusBar()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var tabView: some View {
        TabView(selection: $tabSelection) {
            NavigationStack(path: $router.dashboardPath) {
                DashboardView(namespace: sharedNamespace)
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label(NSLocalizedString("dashboard.title", value: "Dashboard", comment: ""), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationItem.dashboard)

            NavigationStack(path: $router.clientsPath) {
                ClientsView(namespace: sharedNamespace)
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label(NSLocalizedString("clients.tab", value: "Clients", comment: ""), systemImage: "person.3.fill") }
            .tag(NavigationItem.clients)

            NavigationStack(path: $router.insightsPath) {
                InsightsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .accessibilityIdentifier("tab.content.insights")
            .tabItem { Label(NSLocalizedString("insights.tab", value: "Insights", comment: ""), systemImage: "chart.bar.fill") }
            .tag(NavigationItem.insights)

            NavigationStack(path: $router.settingsPath) {
                SettingsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label(NSLocalizedString("settings.tab", value: "Settings", comment: ""), systemImage: "gear") }
            .tag(NavigationItem.settings)
        }
        .accessibilityIdentifier("content.tabView")
    }

    private var splitView: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection) { item in
                selectSurface(item, resetPath: true)
            }
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        } detail: {
            splitViewDetail
        }
        .background {
            MacTranslucentBackground()
                .ignoresSafeArea()
        }
        .frame(minWidth: 980, minHeight: 650)
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection) { item in
                selectSurface(item, resetPath: true)
                collapseSplitSidebarAfterSelectionIfNeeded()
            }
        } detail: {
            splitViewDetail
        }
        #endif
    }

    @ViewBuilder
    private var splitViewDetail: some View {
        switch sidebarSelection {
        case .dashboard:
            NavigationStack(path: $router.dashboardPath) {
                DashboardView(namespace: sharedNamespace)
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .clients:
            NavigationStack(path: $router.clientsPath) {
                ClientsView(namespace: sharedNamespace)
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
                SettingsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        case .none:
            Text(NSLocalizedString("content.select_item", value: "Select an item", comment: ""))
        }
    }

    // MARK: - Navigation Destination Factory

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .clientDetail(let id):
            if let client = modelContext.model(for: id) as? Client {
                ClientDetailView(client: client, namespace: sharedNamespace)
            } else {
                missingDestinationView
            }

        case .petDetail(let id):
            if let pet = modelContext.model(for: id) as? Pet {
                PetDetailView(pet: pet, namespace: sharedNamespace)
            } else {
                missingDestinationView
            }

        case .visitDetail(let id):
            if let visit = modelContext.model(for: id) as? Visit {
                VisitDetailView(visit: visit)
            } else {
                missingDestinationView
            }

        case .petHistory(let id):
            if let pet = modelContext.model(for: id) as? Pet {
                PetHistoryView(pet: pet, wrapsInNavigationStack: false)
            } else {
                missingDestinationView
            }

        case .checkout(let id):
            if let pet = modelContext.model(for: id) as? Pet {
                CheckoutView(pet: pet, visit: pet.activeVisit)
            } else {
                missingDestinationView
            }
        }
    }

    private var missingDestinationView: some View {
        ContentUnavailableView(
            NSLocalizedString("content.missing_record_title", value: "Record Unavailable", comment: ""),
            systemImage: "exclamationmark.triangle.fill",
            description: Text(NSLocalizedString(
                "content.missing_record_message",
                value: "This record may have been deleted or is still syncing. Return to the list and try again.",
                comment: ""
            ))
        )
    }
}

private extension Logger {
    static let contentNav = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ContentNavigation")
}

private extension ContentView {
    func collapseSplitSidebarAfterSelectionIfNeeded() {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard columnVisibility != .doubleColumn else { return }
        withAnimation(MotionSystem.snappy) {
            columnVisibility = .detailOnly
        }
        #endif
    }
}
