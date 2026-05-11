//
//  CheckoutTransactionActor.swift
//  Pawtrackr
//
//  Elite background actor for atomic checkout operations.
//  Ensures idempotency and thread-safety while offloading the MainActor.
//

import Foundation
import SwiftData
import OSLog

private let checkoutLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CheckoutTransactionActor")

struct CheckoutRequest: Sendable {
    let visitUUID: UUID
    let petUUID: UUID
    let clientUUID: UUID?
    
    let amount: Decimal
    let paymentMethod: Payment.Method
    let externalReference: String?
    
    let sessionNotes: String?
    let behaviorTags: [String]
    
    let beforePhotoData: Data?
    let afterPhotoData: Data?
    
    let selectedServiceIDs: [PersistentIdentifier]
    let selectedAddOnIDs: [PersistentIdentifier]
}

struct CheckoutResult: Sendable {
    let visitID: PersistentIdentifier
    let petID: PersistentIdentifier
    let clientID: PersistentIdentifier?
    let endedAt: Date
    let total: Decimal
}

@ModelActor
final actor CheckoutTransactionActor {
    
    func process(_ request: CheckoutRequest) async throws -> CheckoutResult {
        let context = modelContext
        
        // 1. Idempotency Check
        let idempotencyKey = "checkout:\(request.visitUUID.uuidString)"
        let transaction = try fetchOrCreateTransaction(idempotencyKey: idempotencyKey, request: request)
        
        if transaction.status == .succeeded, let completedAt = transaction.completedAt {
            return try buildResult(for: request.visitUUID, endedAt: completedAt)
        }
        
        transaction.markProcessing(
            amount: request.amount,
            method: request.paymentMethod,
            externalReference: request.externalReference,
            clientUUID: request.clientUUID
        )
        
        do {
            // 2. Fetch or Insert Visit
            let visit = try fetchOrCreateVisit(uuid: request.visitUUID, petUUID: request.petUUID)
            let pet = try fetchPet(uuid: request.petUUID)
            
            // 3. Process Images (Parallelized background work)
            let (pBefore, pBeforeThumb, pAfter, pAfterThumb) = await processImages(
                before: request.beforePhotoData,
                after: request.afterPhotoData
            )
            
            // 4. Sync State
            visit.note = request.sessionNotes
            visit.behaviorTags = request.behaviorTags
            pet.setBehaviorTags(request.behaviorTags)
            
            visit.applyPhotos(
                before: pBefore, beforeThumb: pBeforeThumb,
                after: pAfter, afterThumb: pAfterThumb
            )
            
            // 5. Sync Line Items
            try syncVisitItems(visit: visit, serviceIDs: request.selectedServiceIDs + request.selectedAddOnIDs)
            reconcileLineItemPrices(visit: visit, finalTotal: request.amount)
            
            // 6. Payment
            let endedAt = Date.now
            applyPayment(visit: visit, request: request, endedAt: endedAt)
            
            // 7. Finalize Visit
            visit.markCheckedOut(total: request.amount, now: endedAt)
            
            // 8. Commit
            transaction.markSucceeded(completedAt: endedAt)
            try context.save()
            
            // 9. Rebuild Summaries (Off-actor utility)
            SummaryUpdater.rebuildDay(for: endedAt, in: context)
            
            return CheckoutResult(
                visitID: visit.persistentModelID,
                petID: pet.persistentModelID,
                clientID: pet.owner?.persistentModelID,
                endedAt: endedAt,
                total: request.amount
            )
        } catch {
            transaction.markFailed(error.localizedDescription)
            try? context.save()
            checkoutLog.error("Checkout failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Internal Logic
    
    private func fetchOrCreateTransaction(idempotencyKey: String, request: CheckoutRequest) throws -> CheckoutTransaction {
        var descriptor = FetchDescriptor<CheckoutTransaction>(
            predicate: #Predicate<CheckoutTransaction> { $0.idempotencyKey == idempotencyKey }
        )
        descriptor.fetchLimit = 1
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let transaction = CheckoutTransaction(
            idempotencyKey: idempotencyKey,
            visitUUID: request.visitUUID,
            petUUID: request.petUUID,
            clientUUID: request.clientUUID,
            amount: request.amount,
            method: request.paymentMethod,
            externalReference: request.externalReference
        )
        modelContext.insert(transaction)
        return transaction
    }
    
    private func fetchOrCreateVisit(uuid: UUID, petUUID: UUID) throws -> Visit {
        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        
        let pet = try fetchPet(uuid: petUUID)
        let visit = Visit(pet: pet)
        visit.uuid = uuid
        modelContext.insert(visit)
        return visit
    }
    
    private func fetchPet(uuid: UUID) throws -> Pet {
        var descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate<Pet> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        guard let pet = try modelContext.fetch(descriptor).first else {
            throw AppError.database("Pet not found for checkout.")
        }
        return pet
    }
    
    private func processImages(before: Data?, after: Data?) async -> (Data?, Data?, Data?, Data?) {
        await Task.detached(priority: .userInitiated) {
            let b = before.flatMap { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            let bt = before.flatMap { ImageCache.shared.downsampleToData(data: $0, maxDimension: 200) }
            let a = after.flatMap  { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            let at = after.flatMap  { ImageCache.shared.downsampleToData(data: $0, maxDimension: 200) }
            return (b, bt, a, at)
        }.value
    }
    
    private func syncVisitItems(visit: Visit, serviceIDs: [PersistentIdentifier]) throws {
        let context = modelContext
        let currentItems = visit.items ?? []
        
        // Remove items not in selection
        for item in currentItems {
            if let serviceID = item.service?.persistentModelID, !serviceIDs.contains(serviceID) {
                visit.removeItem(item)
                context.delete(item)
            }
        }
        
        // Add missing items
        let existingServiceIDs = Set(currentItems.compactMap { $0.service?.persistentModelID })
        for id in serviceIDs where !existingServiceIDs.contains(id) {
            guard let service = context.model(for: id) as? Service else { continue }
            let item = VisitItem.from(service: service, visit: visit)
            context.insert(item)
            var items = visit.items ?? []
            items.append(item)
            visit.items = items
        }
    }
    
    private func reconcileLineItemPrices(visit: Visit, finalTotal: Decimal) {
        let items = visit.items ?? []
        guard !items.isEmpty else { return }

        let subtotal = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        let normalizedTotal = finalTotal.roundedMoney()
        guard subtotal != normalizedTotal else { return }

        var allocated = Decimal.zero
        for (index, item) in items.enumerated() {
            let lineTotal: Decimal
            if index == items.count - 1 {
                lineTotal = (normalizedTotal - allocated).roundedMoney()
            } else if subtotal > .zero {
                lineTotal = ((item.lineTotal / subtotal) * normalizedTotal).roundedMoney()
                allocated += lineTotal
            } else {
                lineTotal = (normalizedTotal / Decimal(items.count)).roundedMoney()
                allocated += lineTotal
            }

            let quantity = Decimal(max(1, item.quantity))
            item.setUnitPrice((lineTotal / quantity).roundedMoney())
        }
        visit.recalcTotal()
    }
    
    private func applyPayment(visit: Visit, request: CheckoutRequest, endedAt: Date) {
        if let payment = visit.payment {
            payment.setAmount(request.amount)
            payment.method = request.paymentMethod
            payment.paidAt = endedAt
            payment.externalReference = request.externalReference
            payment.markModified()
        } else {
            let payment = Payment(
                amount: request.amount,
                method: request.paymentMethod,
                paidAt: endedAt,
                externalReference: request.externalReference
            )
            modelContext.insert(payment)
            visit.attachPayment(payment)
        }
    }
    
    private func buildResult(for visitUUID: UUID, endedAt: Date) throws -> CheckoutResult {
        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { $0.uuid == visitUUID }
        )
        descriptor.fetchLimit = 1
        guard let visit = try modelContext.fetch(descriptor).first else {
            throw AppError.database("Visit disappeared after successful checkout.")
        }
        return CheckoutResult(
            visitID: visit.persistentModelID,
            petID: visit.pet?.persistentModelID ?? visit.persistentModelID, // Fallback if pet is gone
            clientID: visit.pet?.owner?.persistentModelID,
            endedAt: endedAt,
            total: visit.total
        )
    }
}
