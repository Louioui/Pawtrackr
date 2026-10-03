import SwiftUI
import SwiftData
import OSLog

struct InboxEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let date: Date
    let isRead: Bool
}

@ModelActor
actor NotificationRepository {
    /// Returns values instead of passing actor-owned SwiftData objects to UI.
    func entries() throws -> [InboxEntry] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<AppNotification>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
            .map { InboxEntry(id: $0.uuid, title: $0.title, message: $0.message, date: $0.timestamp, isRead: $0.isRead) }
    }

    /// Marks only entries actually presented, leaving later arrivals unread.
    func markRead(ids: Set<UUID>) throws {
        do {
            for item in try modelContext.fetch(FetchDescriptor<AppNotification>()) where ids.contains(item.uuid) {
                item.isRead = true
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    /// Removes the requested inbox entries atomically, including Clear All's snapshot.
    func remove(ids: Set<UUID>) throws {
        do {
            for item in try modelContext.fetch(FetchDescriptor<AppNotification>()) where ids.contains(item.uuid) {
                modelContext.delete(item)
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    /// Records a completed visit once even if multiple windows receive the event.
    func recordVisit(id: PersistentIdentifier) throws {
        guard let visit = modelContext.model(for: id) as? Visit else { return }
        let key = "visit-completed-\(visit.uuid)"
        let descriptor = FetchDescriptor<AppNotification>(predicate: #Predicate { $0.sourceKey == key })
        guard try modelContext.fetch(descriptor).isEmpty else { return }
        modelContext.insert(AppNotification(
            title: AppLocalization.localized("clients.notification.visit_completed_title", value: "Visit Completed"),
            message: visit.pet?.name ?? AppLocalization.localized("clients.notification.visit_completed_message", value: "A visit was checked out."),
            sourceKey: key
        ))
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }
}

@Observable
@MainActor
final class NotificationInbox {
    private(set) var entries: [InboxEntry] = []
    private(set) var isLoading = false
    var error: AppError?
    var isMutating = false
    var unreadCount: Int { entries.filter { !$0.isRead }.count }
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var repository: NotificationRepository?

    /// Keeps one repository per inbox/container so writes are serialized.
    private func store(_ container: ModelContainer) -> NotificationRepository {
        if let repository { return repository }
        let repository = NotificationRepository(modelContainer: container)
        self.repository = repository
        return repository
    }

    /// Loads the shared snapshot used by both the bell badge and its sheet.
    func refresh(container: ModelContainer) {
        refreshTask?.cancel()
        isLoading = true
        let repository = store(container)
        refreshTask = Task { [weak self] in
            do {
                let entries = try await repository.entries()
                guard !Task.isCancelled else { return }
                self?.entries = entries
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.report(error)
                self?.isLoading = false
            }
        }
    }

    /// Waits for the current refresh; used when presenting the inbox and in tests.
    func waitForRefresh() async { await refreshTask?.value }

    /// Saves read/deletion changes before replacing the visible snapshot.
    func update(ids: Set<UUID>, removing: Bool, container: ModelContainer) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let repository = store(container)
            if removing { try await repository.remove(ids: ids) }
            else { try await repository.markRead(ids: ids) }
            refresh(container: container)
            await waitForRefresh()
            NotificationCenter.default.post(name: .inboxDidUpdate, object: nil)
        } catch { report(error) }
    }

    /// Persists the existing checkout notification before refreshing the badge.
    func recordVisit(id: PersistentIdentifier, container: ModelContainer) async {
        do {
            try await store(container).recordVisit(id: id)
            refresh(container: container)
        } catch { report(error) }
    }

    /// Surfaces inbox failures while retaining the last successfully loaded entries.
    private func report(_ failure: Error) {
        Logger.database.error("Inbox operation failed: \(failure.localizedDescription, privacy: .public)")
        error = .database(failure.localizedDescription)
    }
}

struct NotificationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var inbox: NotificationInbox
    let container: ModelContainer

    var body: some View {
        NavigationStack {
            Group {
                if inbox.isLoading && inbox.entries.isEmpty {
                    ProgressView()
                } else if inbox.entries.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.localized("clients.notifications.empty_title", value: "No Notifications"),
                        systemImage: "bell.slash"
                    )
                } else {
                    List {
                        ForEach(inbox.entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.isRead ? "bell" : "bell.badge.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.headline)
                                    Text(entry.message).font(.subheadline).foregroundStyle(.secondary)
                                    Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button(role: .destructive) { remove([entry.id]) } label: {
                                    Image(systemName: "trash")
                                }
                                .pressScaleStyle()
                                .accessibilityLabel(AppLocalization.localized("common.delete", value: "Delete"))
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { indices in
                            remove(Set(indices.compactMap { inbox.entries.indices.contains($0) ? inbox.entries[$0].id : nil }))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(AppLocalization.localized("clients.notifications.title", value: "Notifications"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.close", value: "Close")) { dismiss() }
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("common.close", value: "Close"))
                }
                ToolbarItem(placement: .primaryAction) {
                    if !inbox.entries.isEmpty {
                        Button(AppLocalization.localized("common.clear_all", value: "Clear All"), role: .destructive) {
                            remove(Set(inbox.entries.map(\.id)))
                        }
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("common.clear_all", value: "Clear All"))
                    }
                }
            }
            .disabled(inbox.isMutating)
            .alert(item: $inbox.error) { error in
                Alert(title: Text(AppLocalization.localized("common.error", value: "Error")), message: Text(error.localizedDescription))
            }
            .task {
                inbox.refresh(container: container)
                await inbox.waitForRefresh()
                await inbox.update(ids: Set(inbox.entries.map(\.id)), removing: false, container: container)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 360, idealHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    /// Captures IDs at the user's action so a later arrival is never deleted accidentally.
    private func remove(_ ids: Set<UUID>) {
        Task { await inbox.update(ids: ids, removing: true, container: container) }
    }
}
