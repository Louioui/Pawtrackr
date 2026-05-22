//
//  DataStoreService.swift
//  Pawtrackr
//
//  Centralized service for data access. Acts as the Single Source of Truth
//  for all SwiftData operations, providing a reactive interface to the UI.
//

import Foundation
import SwiftData
import Observation
import OSLog

@Observable
@MainActor
public final class DataStoreService {
    let container: ModelContainer
    private let mainContext: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.mainContext = container.mainContext
    }

    convenience init(inMemory: Bool) {
        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(
                inMemory ? "PawtrackrTests" : "Pawtrackr",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: inMemory ? .none : .automatic
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: inMemory ? nil : PawtrackrMigrationPlan.self,
                configurations: [config]
            )
            self.init(container: container)
        } catch {
            Logger.dataStore.critical("Failed to create DataStoreService container: \(error.localizedDescription, privacy: .public)")
            preconditionFailure("DataStoreService could not initialize its ModelContainer: \(error.localizedDescription)")
        }
    }

    /// Fetches a list of persistent models with a given predicate and optional sort descriptors.
    @MainActor
    func fetch<T: PersistentModel>(_ predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        let descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        // Optimization: Prefetch relationships if needed
        return try mainContext.fetch(descriptor)
    }

    /// Performs an asynchronous fetch in a detached context to keep the UI responsive.
    nonisolated func fetchAsync<T: PersistentModel>(_ predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) async throws -> [T] {
        let container = self.container
        return try await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            let descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
            return try bgContext.fetch(descriptor)
        }.value
    }

    /// Yields a tick whenever the main context records changes.
    ///
    /// FRAGILE: SwiftData wraps Core Data, so the Core Data
    /// `NSManagedObjectContextObjectsDidChange` notification *currently* fires
    /// when a SwiftData ModelContext mutates. This is undocumented — Apple
    /// could rev SwiftData's internals at any release and silently break this
    /// stream. If the UI stops reacting to writes after a future iOS update,
    /// this observer is the first thing to suspect; replace with a SwiftData-
    /// native subscription if/when one ships.
    func observeChanges<T: PersistentModel>(_ modelType: T.Type) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: mainContext,
                queue: .main
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

private extension Logger {
    static let dataStore = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataStoreService")
}
