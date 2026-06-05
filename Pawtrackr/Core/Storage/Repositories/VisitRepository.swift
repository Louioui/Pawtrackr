//
//  VisitRepository.swift
//  Pawtrackr
//
//  Manages Visit lifecycle and operations.
//

import Foundation
import SwiftData
import OSLog

@MainActor
protocol VisitRepositoryProtocol: Sendable {
    func fetchVisits(predicate: Predicate<Visit>?, sortBy: [SortDescriptor<Visit>], limit: Int?) async throws -> [Visit]
    func saveVisit(_ visit: Visit) async throws
    func deleteVisit(_ visit: Visit) async throws
    func checkIn(pet: Pet, date: Date) async throws -> Visit
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws
}

@MainActor
final class VisitRepository: VisitRepositoryProtocol {
    private let modelContext: ModelContext
    private let eventBus: GlobalEventBus
    private let loyaltyService: LoyaltyService
    
    /// `eventBus` is required: a default would create a fresh bus with no
    /// subscribers and silently swallow every `.refreshRequired` / checkout
    /// completion event. Pass the same bus the rest of the app holds.
    init(modelContext: ModelContext, eventBus: GlobalEventBus) {
        self.modelContext = modelContext
        self.eventBus = eventBus
        self.loyaltyService = LoyaltyService(modelContainer: modelContext.container)
    }
    
    func fetchVisits(predicate: Predicate<Visit>?, sortBy: [SortDescriptor<Visit>], limit: Int?) async throws -> [Visit] {
        var descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: sortBy)
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }
    
    func saveVisit(_ visit: Visit) async throws {
        if visit.modelContext == nil {
            modelContext.insert(visit)
        }
        visit.ensureSessionToken()
        try modelContext.save()
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Saved visit",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["note", "behaviorTagsRaw", "items", "updatedAt", "lastModifiedAt", "lastModifiedBy"]
            )
        }
    }
    
    func deleteVisit(_ visit: Visit) async throws {
        let visitUUID = visit.uuid
        let started = visit.startedAt
        let ended = visit.endedAt
        modelContext.delete(visit)
        try modelContext.save()
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Deleted visit",
                entityName: "Visit",
                recordUUID: visitUUID,
                changedKeys: ["deleted"]
            )
        }
        
        let cal = Calendar.current
        SummaryUpdater.rebuildDay(for: started, in: modelContext)
        if let ended = ended, cal.startOfDay(for: ended) != cal.startOfDay(for: started) {
            SummaryUpdater.rebuildDay(for: ended, in: modelContext)
        }
        
        eventBus.publish(.refreshRequired)
    }
    
    func checkIn(pet: Pet, date: Date) async throws -> Visit {
        Logger.visits.info("VisitRepository: CheckIn initiated for pet \(pet.name)")
        
        // Re-fetch pet in current context to ensure relationship integrity
        let petID = pet.persistentModelID
        guard let contextPet = modelContext.model(for: petID) as? Pet else {
             Logger.visits.error("VisitRepository: Could not fetch pet in current context")
             throw AppError.database("Pet not found in context")
        }
        
        if let existing = try activeVisit(for: contextPet) {
            Logger.visits.info("VisitRepository: Pet already checked in, returning existing visit")
            existing.ensureSessionToken()
            return existing
        }

        let visit = Visit(pet: contextPet, startedAt: date)
        modelContext.insert(visit)
        Logger.visits.info("VisitRepository: Visit object created and inserted into context")
        
        do {
            try modelContext.save()
            Logger.visits.info("VisitRepository: Context save successful for new visit. visitID=\(visit.uuid)")
        } catch {
            Logger.visits.error("VisitRepository: Context save FAILED: \(error.localizedDescription)")
            throw error
        }
        
        Logger.visits.info("VisitRepository: Attempting CloudKit recording...")
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Checked in pet",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["uuid", "sessionToken", "pet", "startedAt", "createdAt", "updatedAt", "lastModifiedBy"]
            )
        }
        Logger.visits.info("VisitRepository: CloudKit record change recorded")
        
        Logger.visits.info("VisitRepository: Attempting EventBus publish...")
        eventBus.publish(.refreshRequired)
        Logger.visits.info("VisitRepository: EventBus refresh published")
        
        Logger.visits.info("VisitRepository: Attempting visitDidStart notification...")
        NotificationCenter.default.post(name: .visitDidStart, object: visit)
        Logger.visits.info("VisitRepository: visitDidStart notification posted")
        
        return visit
    }
    
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws {
        Logger.visits.info("VisitRepository: Checking out visit \(visit.uuid)")
        visit.markCheckedOut(total: total ?? visit.effectiveTotal, now: now)
        
        // Save the visit and its payment
        try modelContext.save()
        
        // Apply loyalty points
        try await loyaltyService.applyPoints(for: visit)
        
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Checked out visit",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["endedAt", "total", "payment", "updatedAt", "lastModifiedAt", "lastModifiedBy", "loyaltyPointsChange"]
            )
        }

        SummaryUpdater.rebuildDay(for: now, in: modelContext)
        let completion = CheckoutCompletionContext(
            visitID: visit.persistentModelID,
            petID: visit.pet?.persistentModelID,
            clientID: visit.pet?.owner?.persistentModelID,
            endedAt: now,
            total: visit.total
        )
        eventBus.publish(.checkoutCompleted(completion))
        var userInfo: [String: Any] = [
            VisitDidCompleteKey.visitID.rawValue: completion.visitID,
            VisitDidCompleteKey.endedAt.rawValue: completion.endedAt,
            VisitDidCompleteKey.total.rawValue: completion.total
        ]
        if let petID = completion.petID {
            userInfo[VisitDidCompleteKey.petID.rawValue] = petID
        }
        if let clientID = completion.clientID {
            userInfo[VisitDidCompleteKey.clientID.rawValue] = clientID
        }
        NotificationCenter.default.post(name: .visitDidComplete, object: visit, userInfo: userInfo)
        Logger.visits.info("VisitRepository: Checkout complete, event published")
    }

    private func activeVisit(for pet: Pet) throws -> Visit? {
        let activeDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let visits = try modelContext.fetch(activeDescriptor)
        let active = visits.first { $0.pet?.uuid == pet.uuid }
        if let active = active {
            Logger.visits.info("VisitRepository: activeVisit found for pet \(pet.name): visitID=\(active.uuid), endedAt=\(String(describing: active.endedAt))")
        } else {
            Logger.visits.info("VisitRepository: No active visit found for pet \(pet.name)")
        }
        return active
    }
}

private extension Logger {
    static let visits = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "VisitRepository")
}
