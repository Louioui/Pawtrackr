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
    func checkIn(from appointment: Appointment) async throws -> Visit
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws
}

@MainActor
final class VisitRepository: VisitRepositoryProtocol {
    private let modelContext: ModelContext
    private let eventBus: GlobalEventBus
    
    /// `eventBus` is required: a default would create a fresh bus with no
    /// subscribers and silently swallow every `.refreshRequired` / checkout
    /// completion event. Pass the same bus the rest of the app holds.
    init(modelContainer: ModelContainer, eventBus: GlobalEventBus) {
        self.modelContext = modelContainer.mainContext
        self.eventBus = eventBus
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
        if let existing = try activeVisit(for: pet) {
            existing.ensureSessionToken()
            return existing
        }

        let visit = Visit(pet: pet, startedAt: date)
        modelContext.insert(visit)
        try modelContext.save()
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Checked in pet",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["uuid", "sessionToken", "pet", "startedAt", "createdAt", "updatedAt", "lastModifiedBy"]
            )
        }
        eventBus.publish(.refreshRequired)
        NotificationCenter.default.post(name: .visitDidStart, object: visit)
        return visit
    }

    func checkIn(from appointment: Appointment) async throws -> Visit {
        // `appointment.pet` is optional under CloudKit-compatible schema.
        // If the pet record can't be resolved, we can't materialize a visit.
        guard let pet = appointment.pet else {
            throw AppError.database("Appointment is missing its pet reference and cannot be checked in.")
        }
        if let existing = try activeVisit(for: pet) {
            existing.appointment = appointment
            appointment.status = .checkedIn
            appointment.visit = existing
            existing.ensureSessionToken()
            try modelContext.save()
            await MainActor.run {
                CloudKitMonitor.shared.recordLocalChange(
                    "Linked appointment to active visit",
                    entityName: "Visit",
                    recordUUID: existing.uuid,
                    changedKeys: ["appointment", "updatedAt", "lastModifiedAt", "lastModifiedBy"]
                )
            }
            eventBus.publish(.refreshRequired)
            NotificationCenter.default.post(name: .visitDidStart, object: existing)
            return existing
        }

        let visit = Visit(pet: pet, startedAt: .now)
        visit.appointment = appointment
        appointment.status = .checkedIn
        appointment.visit = visit
        modelContext.insert(visit)
        try modelContext.save()
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Checked in appointment",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["uuid", "sessionToken", "pet", "appointment", "startedAt", "createdAt", "updatedAt", "lastModifiedBy"]
            )
        }
        eventBus.publish(.refreshRequired)
        NotificationCenter.default.post(name: .visitDidStart, object: visit)
        return visit
    }
    
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws {
        Logger.visits.info("VisitRepository: Checking out visit \(visit.uuid)")
        visit.markCheckedOut(total: total ?? visit.effectiveTotal, now: now)
        
        // Save the visit and its payment
        try modelContext.save()
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Checked out visit",
                entityName: "Visit",
                recordUUID: visit.uuid,
                changedKeys: ["endedAt", "total", "payment", "updatedAt", "lastModifiedAt", "lastModifiedBy"]
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
        return try modelContext.fetch(activeDescriptor).first { $0.pet?.uuid == pet.uuid }
    }
}

private extension Logger {
    static let visits = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "VisitRepository")
}
