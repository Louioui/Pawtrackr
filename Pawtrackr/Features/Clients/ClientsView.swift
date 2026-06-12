//
//  ClientsView.swift
//  Pawtrackr
//
//  Client Center: now powered by a ViewModel for performant, debounced searching.
//  - Live timers are now handled efficiently by TimelineView inside ClientCard.
//  - Navigation to detail view is now implemented.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ClientsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GlobalEventBus.self) private var eventBus
    @Environment(NavigationRouter.self) private var router
    var namespace: Namespace.ID

    init(namespace: Namespace.ID) {
        self.namespace = namespace
        _viewModel = State(initialValue: nil)
    }

    @State private var viewModel: ClientsViewModel?
    @State private var showingNewClientSheet = false
    @State private var showNotifications = false
    @State private var storedNotifications: [NotificationItem] = []
    @State private var clientToDelete: Client?
    @State private var isSearchPresented = false
    @State private var searchFocusRequest = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let viewModel {
                        filterChips(viewModel)

                        if viewModel.inProgressClients.isEmpty && viewModel.otherClients.isEmpty {
                            emptyState(viewModel)
                        } else {
                            clientSections(viewModel)
                        }
                    } else {
                        clientsSkeleton
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
            .clientsSearchable(
                text: searchTextBinding,
                isPresented: $isSearchPresented,
                prompt: NSLocalizedString("clients.search_placeholder", comment: "")
            )
            .background(DS.ColorToken.background)
            .alert(item: errorBinding) { error in
                Alert(
                    title: Text(NSLocalizedString("common.error", comment: "")),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
            // Modern alert API — stacking two deprecated `Alert`-returning
            // `.alert(item:)` modifiers on the same view makes SwiftUI
            // silently drop one (the trash-button confirmation never shows).
            // The error alert above keeps the deprecated API since only ONE
            // deprecated alert in the chain is safe.
            .alert(
                clientToDeleteTitle,
                isPresented: clientToDeletePresented,
                presenting: clientToDelete,
                actions: clientDeleteActions,
                message: clientDeleteMessage
            )
            .fabOverlay {
                #if os(iOS)
                FAB(systemImage: "person.fill.badge.plus", accessibilityLabel: NSLocalizedString("clients.add_client", comment: "")) {
                    showingNewClientSheet = true
                }
                .accessibilityIdentifier("clients.fab.addClient")
                #else
                EmptyView()
                #endif
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewClientSheet = true
                    } label: {
                        Label(NSLocalizedString("clients.add_client", comment: ""), systemImage: "person.fill.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("clients.toolbar.addClient")
                }
                #endif

                ToolbarItem(placement: .primaryAction) {
                    CloudKitStatusView()
                }

                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    MacToolbarSearchField(
                        text: searchTextBinding,
                        prompt: NSLocalizedString("clients.search_placeholder", comment: ""),
                        focusRequest: searchFocusRequest
                    )
                    .frame(width: 260)
                }
                #endif

                ToolbarItem(placement: toolbarTrailingPlacement) {
                    sortingMenu
                }

                ToolbarItem(placement: toolbarTrailingPlacement) {
                    notificationsToolbarButton
                }
            }
            .refreshable {
                // Hop to MainActor to call the isolated VM, then run cloud sync
                // concurrently with whatever local refresh the VM kicks off.
                await MainActor.run { viewModel?.fetchClients() }
                await CloudKitMonitor.shared.forceSync()
            }
            .navigationTitle(NSLocalizedString("clients.title", value: "Client Center", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        viewModel?.fetchClients()
                    } label: {
                        Label(NSLocalizedString("common.refresh", value: "Refresh", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            #endif
            .sheet(isPresented: $showingNewClientSheet) {
            } content: {
                NewClientSheet(modelContext: modelContext)
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsSheet(notifications: $storedNotifications)
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = ClientsViewModel(modelContext: modelContext, eventBus: eventBus)
                }
                viewModel?.fetchClients()
                consumePendingSearchFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusClientSearch)) { _ in
                focusSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clientDidCreate)) { note in
                if let id = note.createdClientID, note.clientCreatePhase == .created {
                    storedNotifications.insert(
                        NotificationItem(
                            title: NSLocalizedString("clients.notification.client_created_title", value: "Client Created", comment: ""),
                            message: NSLocalizedString("clients.notification.client_created_message", value: "A new client was added.", comment: ""),
                            date: Date(),
                            relatedID: id
                        ),
                        at: 0
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .visitDidComplete)) { note in
                storedNotifications.insert(
                    NotificationItem(
                        title: NSLocalizedString("clients.notification.visit_completed_title", value: "Visit Completed", comment: ""),
                        message: NSLocalizedString("clients.notification.visit_completed_message", value: "A visit was checked out.", comment: ""),
                        date: Date(),
                        relatedID: note.visitID
                    ),
                    at: 0
                )
            }
        }
    }

    private var toolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .navigationBarTrailing
        #endif
    }

    @ViewBuilder
    private func filterChips(_ viewModel: ClientsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClientsViewModel.Filter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.displayName)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedFilter == filter ? DS.ColorToken.primary : Color.secondary.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(viewModel.selectedFilter == filter ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var sortingMenu: some View {
        Menu {
            Picker(NSLocalizedString("clients.sort_by", value: "Sort By", comment: ""), selection: sortOptionBinding) {
                ForEach(ClientsViewModel.SortOption.allCases, id: \.self) { option in
                    Label(option.displayName, systemImage: sortIcon(for: option))
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
    }

    private func sortIcon(for option: ClientsViewModel.SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .lastVisit: return "clock"
        case .newest: return "calendar.badge.plus"
        }
    }

    private var sortOptionBinding: Binding<ClientsViewModel.SortOption> {
        Binding(
            get: { viewModel?.sortOption ?? .name },
            set: { viewModel?.sortOption = $0 }
        )
    }

    @ViewBuilder
    private func clientSections(_ viewModel: ClientsViewModel) -> some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader(NSLocalizedString("clients.in_progress", comment: ""), count: viewModel.inProgressCount, topPadding: 0)
            clientList(for: viewModel.inProgressClients)
        }
        
        sectionHeader(NSLocalizedString("clients.all_clients", comment: ""), count: viewModel.otherClients.count, topPadding: 16)
        VStack(spacing: 10) {
            clientList(for: viewModel.otherClients, enableInfiniteScroll: true)
            if viewModel.canLoadMore {
                Button(action: { viewModel.loadMore() }) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("common.load_more", comment: "Load More"))
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func clientList(for clients: [Client], enableInfiniteScroll: Bool = false) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(clients.enumerated()), id: \.element.id) { idx, client in
                Button(action: { router.navigateToClient(client) }) {
                    ClientCard(client: client, namespace: namespace)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clients.row.\(client.firstName) \(client.lastName)")
                .contextMenu {
                    Button {
                        router.navigateToClient(client)
                    } label: {
                        Label(NSLocalizedString("clients.action.view_details", value: "View Details", comment: ""), systemImage: "person.crop.circle")
                    }

                    #if canImport(UIKit)
                    if let phone = client.phone, let tel = PhoneUtils.telURLString(phone), let url = URL(string: tel) {
                        Button {
                            viewModel?.recordAttentionOutreach(for: client, method: "call")
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label(NSLocalizedString("clients.action.call", value: "Call", comment: ""), systemImage: "phone")
                        }
                    }
                    
                    if let phone = client.phone, let sms = PhoneUtils.smsURLString(phone), let url = URL(string: sms) {
                        Button {
                            viewModel?.recordAttentionOutreach(for: client, method: "message")
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label(NSLocalizedString("clients.action.message", value: "Message", comment: ""), systemImage: "message")
                        }
                    }

                    if let email = client.email, let url = URL(string: "mailto:\(email)") {
                        Button {
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label(NSLocalizedString("clients.action.email", value: "Email", comment: ""), systemImage: "envelope")
                        }
                    }
                    #endif

                    Divider()

                    Button(role: .destructive) {
                        clientToDelete = client
                    } label: {
                        Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                    }
                }
                .onAppear {
                    guard enableInfiniteScroll,
                          let vm = viewModel,
                          vm.canLoadMore,
                          !vm.isLoadingMore,
                          idx >= max(0, clients.count - 5) else { return }
                    vm.loadMore()
                }
            }
        }
        .padding(.horizontal)
    }

    private func emptyState(_ viewModel: ClientsViewModel) -> some View {
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var title = isSearching
            ? NSLocalizedString("clients.no_results_title", comment: "")
            : NSLocalizedString("clients.empty_title", comment: "")
        var description = isSearching
            ? String(format: NSLocalizedString("clients.no_results_desc_fmt", comment: ""), viewModel.searchText)
            : NSLocalizedString("clients.empty_desc", comment: "")
        var icon = isSearching ? "magnifyingglass" : "person.3.sequence.fill"

        if !isSearching {
            switch viewModel.selectedFilter {
            case .active:
                title = NSLocalizedString("clients.empty.active_title", value: "No Active Sessions", comment: "")
                description = NSLocalizedString("clients.empty.active_desc", value: "There are no pets currently checked in.", comment: "")
                icon = "hourglass.badge.plus"
            case .overdue:
                title = NSLocalizedString("clients.empty.overdue_title", value: "No Attention Needed", comment: "")
                description = NSLocalizedString("clients.empty.overdue_desc", value: "No client outreach is pending right now.", comment: "")
                icon = "checkmark.seal.fill"
            case .missingInfo:
                title = NSLocalizedString("clients.empty.missing_info_title", value: "Data looks great!", comment: "")
                description = NSLocalizedString("clients.empty.missing_info_desc", value: "All your clients have phone numbers and emails on file.", comment: "")
                icon = "vial.viewfinder"
            default:
                break
            }
        }

        return ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(description)
        )
        .padding(40)
    }

    private func sectionHeader(_ title: String, count: Int, topPadding: CGFloat = 0) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: .capsule)
            }
        }
        .padding(.horizontal)
        .padding(.top, topPadding)
    }

    private var notificationsCount: Int { storedNotifications.count }
    private var notificationBadgeText: String { "\(min(notificationsCount, 9))" }

    private var notificationsAccessibilityLabel: String {
        String.localizedStringWithFormat(
            NSLocalizedString("clients.notifications_unread_fmt", value: "Notifications, %d unread", comment: ""),
            notificationsCount
        )
    }

    private var notificationsToolbarButton: some View {
        Button {
            showNotifications = true
        } label: {
            Image(systemName: "bell.fill")
                .overlay(alignment: .topTrailing) {
                    if notificationsCount > 0 {
                        Text(notificationBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.red, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityIdentifier("clients.toolbar.notifications")
        .accessibilityLabel(notificationsAccessibilityLabel)
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        )
    }

    private func consumePendingSearchFocus() {
        guard UserDefaults.standard.string(forKey: AppMenuCommand.pendingClientSearchFocusKey) != nil else { return }
        UserDefaults.standard.removeObject(forKey: AppMenuCommand.pendingClientSearchFocusKey)
        focusSearch()
    }

    private func focusSearch() {
        // Always consume the pending-focus token here so the `.focusClientSearch`
        // notification path (which calls focusSearch() directly while the view is
        // already visible) can't leave a stale token that a later onAppear would
        // re-trigger focus from.
        UserDefaults.standard.removeObject(forKey: AppMenuCommand.pendingClientSearchFocusKey)
        isSearchPresented = true
        #if os(macOS)
        searchFocusRequest += 1
        #endif
    }

    private var errorBinding: Binding<AppError?> {
        Binding(
            get: { viewModel?.appError },
            set: { viewModel?.appError = $0 }
        )
    }

    // MARK: - Delete-client alert helpers
    //
    // Extracted out of the body so SourceKit doesn't time out on the
    // long modifier chain. The alert is wired via these four computed
    // pieces instead of inline closures.

    private var clientToDeleteTitle: String {
        guard let client = clientToDelete else { return "" }
        return String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), client.fullName)
    }

    private var clientToDeletePresented: Binding<Bool> {
        Binding(
            get: { clientToDelete != nil },
            set: { if !$0 { clientToDelete = nil } }
        )
    }

    @ViewBuilder
    private func clientDeleteActions(_ client: Client) -> some View {
        Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
            viewModel?.deleteClient(client)
        }
        Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
    }

    private func clientDeleteMessage(_ client: Client) -> Text {
        Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
    }

    private var clientsSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Card(elevation: .regular) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 160, height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 120, height: 10)
                        }
                        Spacer()
                    }
                }
                .redacted(reason: .placeholder)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Notifications UI
    private struct NotificationItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let date: Date
        let relatedID: PersistentIdentifier?
    }

    private struct NotificationsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var notifications: [NotificationItem]
        var body: some View {
            NavigationStack {
                List {
                    if notifications.isEmpty {
                        ContentUnavailableView(
                            NSLocalizedString("clients.notifications.empty_title", value: "No Notifications", comment: ""),
                            systemImage: "bell.slash"
                        )
                    } else {
                        ForEach(notifications) { n in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "bell.fill").foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title).font(.subheadline.weight(.semibold))
                                    Text(n.message).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(n.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { idx in notifications.remove(atOffsets: idx) }
                    }
                }
                .navigationTitle(NSLocalizedString("clients.notifications.title", value: "Notifications", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("common.close", value: "Close", comment: "")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if !notifications.isEmpty {
                            Button(NSLocalizedString("common.clear_all", value: "Clear All", comment: "")) { notifications.removeAll() }
                        }
                    }
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func clientsSearchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        prompt: String
    ) -> some View {
        #if os(macOS)
        self
        #else
        self.searchable(
            text: text,
            isPresented: isPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(prompt)
        )
        #endif
    }
}

#if os(macOS)
private struct MacToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.setAccessibilityIdentifier("clients.search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = prompt
        if field.stringValue != text {
            field.stringValue = text
        }

        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest

        DispatchQueue.main.async {
            field.window?.makeKeyAndOrderFront(nil)
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
#endif

private struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        Card(elevation: .flat, showBorder: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.title.weight(.bold))
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
