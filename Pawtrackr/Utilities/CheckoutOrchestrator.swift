//
//  CheckoutOrchestrator.swift
//  Pawtrackr
//
//  Centralized transactional pipeline for checkout persistence, image processing,
//  and system-wide synchronization.
//

import Foundation
import SwiftData
import Observation

@MainActor
final class CheckoutOrchestrator {
    private let dataStore: DataStoreService
    private let eventBus: GlobalEventBus
    
    init(dataStore: DataStoreService, eventBus: GlobalEventBus) {
        self.dataStore = dataStore
        self.eventBus = eventBus
    }
    
    func process(
        visit: Visit,
        beforeData: Data?,
        afterData: Data?,
        total: Decimal
    ) async throws {
        // 1. Process images on background thread
        let (pBefore, pAfter) = await Task.detached(priority: .userInitiated) {
            let b = beforeData.flatMap { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            let a = afterData.flatMap  { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            return (b, a)
        }.value
        
        // 2. Perform transactional persistence
        visit.beforePhotoData = pBefore
        visit.afterPhotoData = pAfter
        let endedAt = Date()
        visit.markCheckedOut(total: total, now: endedAt)
        
        try dataStore.container.mainContext.save()
        SummaryUpdater.rebuildDay(for: endedAt, in: dataStore.container.mainContext)
        
        // 3. Trigger system-wide synchronization
        let completion = CheckoutCompletionContext(
            visitID: visit.persistentModelID,
            petID: visit.pet?.persistentModelID,
            clientID: visit.pet?.owner?.persistentModelID,
            endedAt: endedAt,
            total: visit.total
        )
        eventBus.publish(.checkoutCompleted(completion))
    }
}
