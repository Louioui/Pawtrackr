//
//  CloudKitSchemaInitializer.swift
//  Pawtrackr
//
//  DEBUG-only tool that pushes every record type and field of the current
//  models to the CloudKit Development environment.
//

#if DEBUG
import CoreData
import Foundation
import OSLog
import SwiftData

/// Pushes the full CloudKit schema for `PawtrackrSchema.models` to the
/// Development environment when the app launches with `-PawtrackrInitCloudKitSchema`.
///
/// Without this, Development only contains the types and fields that some debug
/// build happened to upload with a non-nil value, and Development is what gets
/// deployed to Production. If Production is missing a field, every App Store
/// upload batch that carries it is rejected while imports keep working.
/// Release steps are in docs/icloud-validation.md.
///
/// Follows Apple's SwiftData pattern, "Syncing model data across a person's
/// devices" (developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices):
/// load the models into an NSPersistentCloudKitContainer synchronously, call
/// `initializeCloudKitSchema()`, then remove the store before SwiftData opens its
/// own. One deliberate change: the store is a throwaway in the temporary
/// directory, not `ModelConfiguration.url`, so the real Pawtrackr.store is never
/// opened by a second framework.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-PawtrackrInitCloudKitSchema"

    private static let containerIdentifier = "iCloud.PartnerShipWithMedia.Pawtrackr"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CloudKitSchema")

    enum Failure: Error {
        case managedObjectModelUnavailable
    }

    /// Call from `PawtrackrApp.init` before any ModelContainer opens. It blocks
    /// on the network, which is acceptable only because it's opt-in and DEBUG-only.
    /// Returns true when CloudKit accepted the schema.
    @discardableResult
    static func runIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard arguments.contains(launchArgument) else { return false }
        guard AppRuntime.allowsICloudSync else {
            log.notice("Skipping CloudKit schema initialization: this launch doesn't use iCloud (tests or in-memory store).")
            return false
        }

        let fileManager = FileManager.default
        // A throwaway directory created for this run only. Deleting it is not
        // deleting a user store; Pawtrackr.store is never touched here.
        let scratchDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PawtrackrCloudKitSchema-\(UUID().uuidString)", isDirectory: true)
        defer {
            do {
                if fileManager.fileExists(atPath: scratchDirectory.path) {
                    try fileManager.removeItem(at: scratchDirectory)
                }
            } catch {
                log.error("Couldn't remove the throwaway schema store at \(scratchDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let startedAt = Date()
        do {
            try fileManager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            // The pool makes sure the Core Data stack is deallocated before
            // SwiftData sets up its own, as in Apple's sample.
            try autoreleasepool {
                try initializeSchema(storeURL: scratchDirectory.appendingPathComponent("SchemaInit.store"))
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            log.notice("CloudKit Development schema initialized for \(PawtrackrSchema.models.count) models in \(elapsed, format: .fixed(precision: 1))s. Deploy it to Production in CloudKit Console before release.")
            return true
        } catch {
            // String(describing:) keeps the NSError userInfo, which carries the
            // underlying CKError and any model validation reason.
            log.error("CloudKit schema initialization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func initializeSchema(storeURL: URL) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PawtrackrSchema.models) else {
            throw Failure.managedObjectModelUnavailable
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        // Load synchronously so the store is ready before initializeCloudKitSchema().
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "PawtrackrSchemaInit", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        // Unload even when initialization throws: if the mirroring delegate
        // outlived this call, two frameworks would sync the same zone once
        // SwiftData opens the real store.
        defer {
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                do {
                    try coordinator.remove(store)
                } catch {
                    log.error("Couldn't unload the throwaway schema store: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // A fresh store starts mirroring as soon as it loads, so it also imports
        // the Development zone while it's open. That can make this slow with a
        // large dev dataset, but nothing is uploaded except the representative
        // records initializeCloudKitSchema creates and then deletes.
        try container.initializeCloudKitSchema(options: [])
    }
}
#endif
