//
//  DashboardView.swift
//  Pawtrackr
//

import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

struct DashboardView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(DataStoreService.self) private var dataStore
    @Environment(GlobalEventBus.self) private var eventBus
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var vm: DashboardViewModel?
    @State private var showNewClient = false
    @State private var showActivityFeed = false
    @State private var selectedRevenueDate: Date?
    var namespace: Namespace.ID

    var body: some View {
        dashboardContent
            .navigationTitle(NSLocalizedString("dashboard.title", comment: ""))
            .sheet(isPresented: $showNewClient) {
                NewClientSheet(modelContext: modelContext)
            }
            .sheet(isPresented: $showActivityFeed) {
                ActivityFeedView()
            }
            .alert(item: appErrorBinding) { error in
                Alert(
                    title: Text(NSLocalizedString("common.error", comment: "")),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
            .toolbar { insightsToolbarItem }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if let vm {
            switch vm.state {
            case .loading:
                skeletonView
                    .transition(.opacity)
            case .loaded:
                content(vm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .error(let message):
                ContentUnavailableView(
                    NSLocalizedString("common.error", comment: ""),
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        } else {
            Color.clear
                .task {
                    guard self.vm == nil else { return }
                    vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
                }
        }
    }

    private var appErrorBinding: Binding<AppError?> {
        Binding(get: { vm?.appError }, set: { vm?.appError = $0 })
    }

    @ToolbarContentBuilder
    private var insightsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showActivityFeed = true
            } label: {
                Label("Salon Activity", systemImage: "clock.arrow.2.circlepath")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showNewClient = true
            } label: {
                Label(NSLocalizedString("dashboard.new_client", comment: ""), systemImage: "person.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            CloudKitStatusView()
        }

        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            Button {
                Task { await vm?.refresh() }
            } label: {
                Label(NSLocalizedString("common.refresh", comment: ""), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        #endif
    }

    @ViewBuilder
    private func content(_ vm: DashboardViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                smartSummary(vm)
                
                if !appSettings.isChecklistDismissed && !vm.checklist.allSatisfy({ $0.isCompleted }) {
                    checklistSection(vm)
                }

                #if os(macOS)
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 24) {
                        kpiSection(vm)
                        activeSessionsSection(vm)
                        reengagementSection(vm)
                        revenueSection(vm)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 24) {
                        quickActionsSection
                        overduePetsSection(vm)
                        recentClientsSection(vm)
                        gallerySection(vm)
                    }
                    .frame(maxWidth: 350)
                }
                #else
                VStack(spacing: 24) {
                    kpiSection(vm)
                    quickActionsSection
                    if !vm.smartSuggestions.isEmpty { smartSuggestionsSection(vm) }
                    if !vm.activeVisits.isEmpty { activeSessionsSection(vm) }
                    reengagementSection(vm)
                    if !vm.overduePets.isEmpty { overduePetsSection(vm) }
                    if !vm.recentClients.isEmpty { recentClientsSection(vm) }
                    revenueSection(vm)
                    if !vm.gallery.isEmpty { gallerySection(vm) }
                }
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .accessibilityIdentifier("dashboard.scroll")
        .refreshable {
            async let local: Void = vm.refresh()
            async let cloud: Void = CloudKitMonitor.shared.forceSync()
            _ = await (local, cloud)
        }
    }

    // MARK: - Skeleton View
    private var skeletonView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Smart Summary Skeleton
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonRect().frame(width: 150, height: 24)
                    SkeletonRect().frame(maxWidth: .infinity).frame(height: 16)
                    SkeletonRect().frame(width: 200, height: 16)
                }
                .padding(.bottom, 8)

                // KPI Skeleton
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        SkeletonRect().frame(height: 80)
                        SkeletonRect().frame(height: 80)
                    }
                    GridRow {
                        SkeletonRect().frame(height: 80)
                        SkeletonRect().frame(height: 80)
                    }
                }

                // Quick Actions Skeleton
                HStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        SkeletonRect().frame(width: 130, height: 100)
                    }
                }

                // List Skeleton
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonRect().frame(width: 120, height: 20)
                    ForEach(0..<3) { _ in
                        SkeletonRect().frame(height: 120)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Sections (unchanged logic, just ensuring they use the VM)

    private func smartSuggestionsSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(NSLocalizedString("dashboard.smart_suggestions", value: "Smart Suggestions", comment: ""), systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(vm.smartSuggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: SmartSuggestion) -> some View {
        Card(elevation: .regular, accent: .leading(.color(.purple), thickness: 4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(suggestion.petName).font(.subheadline.weight(.bold))
                        Text(suggestion.ownerName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: suggestion.actionType == .text ? "message.fill" : "phone.fill")
                        .foregroundStyle(.purple)
                        .font(.caption)
                }
                
                Text(suggestion.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    // Logic to open client and start communication
                    if let clientID = suggestion.clientID, let client = modelContext.model(for: clientID) as? Client {
                        openClient(client)
                    }
                } label: {
                    Text(NSLocalizedString("dashboard.reengage", value: "Re-engage", comment: ""))
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }
            .frame(width: 200)
        }
    }

    private func checklistSection(_ vm: DashboardViewModel) -> some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("dashboard.getting_started", value: "Getting Started", comment: ""))
                            .font(.headline)
                        Text(String(format: NSLocalizedString("dashboard.steps_completed_fmt", value: "%d of %d steps completed", comment: ""), vm.checklist.filter({ $0.isCompleted }).count, vm.checklist.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation {
                            appSettings.isChecklistDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                ProgressView(value: Double(vm.checklist.filter({ $0.isCompleted }).count), total: Double(vm.checklist.count))
                    .tint(DS.ColorToken.success)
                
                VStack(spacing: 12) {
                    ForEach(vm.checklist) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? DS.ColorToken.success : DS.ColorToken.border)
                                .font(.title3)
                            
                            Text(item.title)
                                .font(.subheadline)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .strikethrough(item.isCompleted)
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(DS.Spacing.md)
        }
    }

    private func reengagementSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !vm.overduePets.isEmpty {
                HStack {
                    Text(NSLocalizedString("dashboard.reengagement_suggestions", value: "Re-engagement Suggestions", comment: ""))
                        .font(.headline)
                    Spacer()
                    Chip(String(format: NSLocalizedString("dashboard.actionable_count_fmt", value: "%d Actionable", comment: ""), vm.overduePets.count), style: .tinted, size: .sm, tint: .orange)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.overduePets.prefix(3)) { pet in
                            reengagementCard(pet)
                        }
                    }
                }
            }
        }
    }

    private func reengagementCard(_ pet: Pet) -> some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .sm)
                    VStack(alignment: .leading) {
                        Text(pet.name).font(.subheadline.weight(.bold))
                        Text(pet.owner?.fullName ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Text(pet.isOverdue ? NSLocalizedString("dashboard.overdue_for_visit", value: "Overdue for visit", comment: "") : NSLocalizedString("dashboard.due_soon", value: "Due soon", comment: ""))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())

                HStack {
                    if let sms = pet.owner?.smsURL {
                        Link(destination: sms) {
                            Label(NSLocalizedString("dashboard.message", comment: ""), systemImage: "message.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if let owner = pet.owner {
                        Button {
                            openClient(owner)
                        } label: {
                            Label(NSLocalizedString("dashboard.view_owner", value: "View Owner", comment: ""), systemImage: "person.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }
            .frame(width: 180)
        }
    }

    private func smartSummary(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Calendar.current.component(.hour, from: .now) < 12 ? NSLocalizedString("dashboard.greeting.morning", value: "Good Morning", comment: "") : NSLocalizedString("dashboard.greeting.afternoon", value: "Good Afternoon", comment: ""))
                .font(.title2.weight(.bold))

            let summary = generateSummaryText(vm)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func generateSummaryText(_ vm: DashboardViewModel) -> String {
        var parts: [String] = []

        if vm.kpi.inProgressCount > 0 {
            parts.append(String(format: NSLocalizedString("dashboard.summary.active_sessions_fmt", value: "%d active sessions in progress", comment: ""), vm.kpi.inProgressCount))
        }

        if let trend = vm.kpi.revenueTrend {
            let direction = trend >= 0 ? NSLocalizedString("dashboard.trend.up", value: "up", comment: "") : NSLocalizedString("dashboard.trend.down", value: "down", comment: "")
            let pct = Formatters.percentString(abs(trend), showSign: false) ?? ""
            parts.append(String(format: NSLocalizedString("dashboard.summary.revenue_trend_fmt", value: "revenue is %@ %@ from yesterday", comment: ""), direction, pct))
        }

        return parts.joined(separator: ", ") + "."
    }

    private func kpiSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dashboard.today", comment: "")).font(.headline)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    recentHistoryLink(scope: .today) {
                        kpiCard(title: NSLocalizedString("dashboard.in_progress", comment: ""), value: "\(vm.kpi.inProgressCount)", symbol: "hourglass")
                    }
                    recentHistoryLink(scope: .today) {
                        kpiCard(title: NSLocalizedString("dashboard.completed", comment: ""), value: "\(vm.kpi.completedToday)", symbol: "checkmark.circle")
                    }
                }
                GridRow {
                    Button {
                        selectSurface(.insights, resetPath: true)
                    } label: {
                        kpiCard(title: NSLocalizedString("dashboard.revenue", comment: ""), value: vm.kpi.revenueTodayString, symbol: "dollarsign.circle", trend: vm.kpi.revenueTrend)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(NSLocalizedString("dashboard.revenue", comment: "")))
                    .accessibilityValue(Text(vm.kpi.revenueTodayString))
                    .accessibilityHint(Text(NSLocalizedString("dashboard.opens_insights", value: "Opens Insights", comment: "")))
                    .accessibilityIdentifier("dashboard.kpi.revenueInsights")
                    .accessibilityAddTraits(.isButton)
                    .gridCellColumns(2)
                }
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dashboard.quick_actions", comment: "")).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionCard(
                    title: NSLocalizedString("dashboard.new_client", comment: ""),
                    symbol: "person.crop.circle.badge.plus",
                    accessibilityIdentifier: "dashboard.quickAction.newClient"
                ) { showNewClient = true }
                actionCard(
                    title: NSLocalizedString("dashboard.quick_check_in", value: "Quick Check-In", comment: ""),
                    symbol: "play.circle",
                    accessibilityIdentifier: "dashboard.quickAction.checkIn"
                ) {
                    // Navigate to clients and focus search if possible, or just navigate
                    selectSurface(.clients, resetPath: true)
                }
                actionCard(
                    title: NSLocalizedString("dashboard.check_out", comment: ""),
                    symbol: "stop.circle",
                    accessibilityIdentifier: "dashboard.quickAction.checkOut"
                ) {
                    selectRecentHistory(resetPath: true)
                }
                actionCard(
                    title: NSLocalizedString("dashboard.reports", comment: ""),
                    symbol: "chart.bar.fill",
                    accessibilityIdentifier: "dashboard.quickAction.reports"
                ) {
                    selectSurface(.insights, resetPath: true)
                }
            }
        }
    }

    private func activeSessionsSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dashboard.active_sessions", comment: "")).font(.headline)
            LazyVStack(spacing: 10) {
                ForEach(vm.activeVisits) { visit in
                    ActiveVisitRow(visit: visit)
                }
            }
        }
    }

    private func overduePetsSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dashboard.needs_attention", comment: "")).font(.headline)
            LazyVStack(spacing: 12) {
                ForEach(vm.overduePets, id: \.uuid) { pet in
                    if let owner = pet.owner {
                        Card {
                            VStack(spacing: 8) {
                                PetCard(
                                    pet: pet,
                                    activeVisit: pet.activeVisit,
                                    onViewDetails: { openPet(pet) },
                                    onCheckIn: { Task { await vm.checkInPet(pet) } },
                                    onCheckOut: { router.navigateToCheckout(pet) },
                                    namespace: namespace
                                )

                                if owner.smsURL != nil || owner.telURL != nil {
                                    HStack(spacing: 12) {
                                        if let sms = owner.smsURL {
                                            Link(destination: sms) {
                                                Label(NSLocalizedString("dashboard.message", comment: ""), systemImage: "message.fill")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.vertical, 8)
                                                    .frame(maxWidth: .infinity)
                                                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                        if let tel = owner.telURL {
                                            Link(destination: tel) {
                                                Label(NSLocalizedString("dashboard.call", comment: ""), systemImage: "phone.fill")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.vertical, 8)
                                                    .frame(maxWidth: .infinity)
                                                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentClientsSection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("dashboard.recent_clients", comment: "")).font(.headline)
                Spacer()
                Button(NSLocalizedString("dashboard.view_all", comment: "")) {
                    selectSurface(.clients, resetPath: true)
                }
                .font(.footnote)
            }
            LazyVStack(spacing: 10) {
                ForEach(vm.recentClients.prefix(5)) { client in
                    Button {
                        openClient(client)
                    } label: {
                        ClientRow(client: client)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func revenueSection(_ vm: DashboardViewModel) -> some View {
        #if canImport(Charts)
        let selectedPoint = selectedRevenuePoint(in: vm)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("dashboard.revenue_7d", comment: "")).font(.headline)
                Spacer()
                if let selected = selectedPoint {
                    Text("\(selected.date.formatted(.dateTime.weekday(.abbreviated))): \(selected.amount.moneyString)")
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.ColorToken.primary)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            Card {
                if vm.revenueSeries.isEmpty {
                    ContentUnavailableView(NSLocalizedString("dashboard.no_revenue_yet", comment: ""), systemImage: "chart.bar.xaxis", description: Text(NSLocalizedString("dashboard.no_revenue_desc", comment: "")))
                        .frame(height: 180)
                } else {
                    Chart {
                        ForEach(vm.revenueSeries) { point in
                            BarMark(
                                x: .value(NSLocalizedString("insights.chart.day", value: "Day", comment: ""), point.date, unit: .day),
                                y: .value(NSLocalizedString("insights.revenue", comment: ""), point.amountDouble)
                            )
                            .foregroundStyle(DS.ColorToken.primary.gradient)
                            .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.4)
                        }

                        if let selected = selectedPoint {
                            RuleMark(x: .value(NSLocalizedString("common.selected", comment: ""), selected.date, unit: .day))
                                .foregroundStyle(.gray.opacity(0.3))
                                .offset(y: -10)
                                .zIndex(-1)
                        }
                    }
                    .chartXSelection(value: $selectedRevenueDate)
                    .frame(height: 180)
                    .animation(.spring(), value: selectedRevenueDate)
                }
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func selectedRevenuePoint(in vm: DashboardViewModel) -> DashboardViewModel.RevenuePoint? {
        guard let selectedRevenueDate else { return nil }
        let calendar = Calendar.current
        return vm.revenueSeries.first { calendar.isDate($0.date, inSameDayAs: selectedRevenueDate) }
    }

    private func gallerySection(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dashboard.pet_gallery", comment: "")).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(vm.gallery) { item in
                    Card {
                        #if canImport(UIKit)
                        if let uiImage = item.uiImage {
                            Image(uiImage: uiImage).resizable().scaledToFill()
                                .frame(height: 120).clipped().cornerRadius(8)
                        } else {
                            LabelContent(title: NSLocalizedString("dashboard.no_photo", comment: ""), systemImage: "photo")
                                .frame(height: 120)
                        }
                        #elseif canImport(AppKit)
                        if let nsImage = item.nsImage {
                            Image(nsImage: nsImage).resizable().scaledToFill()
                                .frame(height: 120).clipped().cornerRadius(8)
                        } else {
                            LabelContent(title: NSLocalizedString("dashboard.no_photo", comment: ""), systemImage: "photo")
                                .frame(height: 120)
                        }
                        #endif
                    }
                }
            }
        }
    }

    private func kpiCard(title: String, value: String, symbol: String, trend: Double? = nil) -> some View {
        Card {
            HStack(alignment: .top) {
                IconCircle(systemImage: symbol, size: .md)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.footnote).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        if let trend = trend {
                            HStack(spacing: 2) {
                                Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text(Formatters.percentString(abs(trend), showSign: false) ?? "")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(trend >= 0 ? .green : .red)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(trend != nil ? String(format: NSLocalizedString("dashboard.trend.accessibility_fmt", value: "Trend: %@ %@", comment: ""), trend! >= 0 ? NSLocalizedString("dashboard.trend.up_label", value: "Up", comment: "") : NSLocalizedString("dashboard.trend.down_label", value: "Down", comment: ""), Formatters.percentString(abs(trend!), showSign: false) ?? "") : "")
    }

    private func actionCard(title: String, symbol: String, accessibilityIdentifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionCardLabel(title: title, symbol: symbol)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityAddTraits(.isButton)
            .frame(maxWidth: .infinity)
    }

    private func recentHistoryLink<Label: View>(
        scope: RecentHistoryViewModel.Scope?,
        accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        NavigationLink {
            RecentHistoryView(initialScope: scope)
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? NSLocalizedString("history.title", value: "Recent History", comment: "")))
        .applyAccessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }

    private func actionCardLabel(title: String, symbol: String) -> some View {
        Card {
            VStack(spacing: 8) {
                IconCircle(systemImage: symbol, size: .lg)
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
        }
    }

    private func selectSurface(_ item: NavigationItem, resetPath: Bool = false) {
        NotificationCenter.default.post(name: .selectNavigationItem, object: nil, userInfo: [
            NavigationSelectionKey.item.rawValue: item.rawValue,
            NavigationSelectionKey.resetPath.rawValue: resetPath
        ])
    }

    private func selectRecentHistory(resetPath: Bool = false) {
        NotificationCenter.default.post(name: .selectNavigationItem, object: nil, userInfo: [
            NavigationSelectionKey.item.rawValue: "recenthistory",
            NavigationSelectionKey.resetPath.rawValue: resetPath
        ])
    }

    private func openClient(_ client: Client) {
        NotificationCenter.default.post(name: .navigateToClient, object: nil, userInfo: [
            "uuid": client.uuid
        ])
    }
    
    private func openPet(_ pet: Pet) {
        NotificationCenter.default.post(name: .navigateToPet, object: nil, userInfo: [
            "uuid": pet.uuid
        ])
    }
}

// MARK: - Skeleton Components

struct SkeletonRect: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                GeometryReader { geo in
                    Color.white.opacity(0.3)
                        .mask(
                            Rectangle()
                                .fill(
                                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * 0.5)
                                .offset(x: -geo.size.width * 0.5 + (geo.size.width * 1.5 * phase))
                        )
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
