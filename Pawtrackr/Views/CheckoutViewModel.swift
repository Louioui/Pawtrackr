//
//  CheckoutViewModel.swift
//  Pawtrackr
//
//  View-model for CheckoutView: owns selection state, totals math, photos, payment,
//  and visit/payment persistence. Now uses modern @Observable.
//
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData
import OSLog

@Observable
@MainActor
final class CheckoutViewModel {
    enum CheckoutState: Equatable {
        case selectingServices
        case addingPhotos
        case choosingPayment
        case processing
        case confirmed
        case failed(AppError)
    }

    // MARK: Dependencies
    private var visitRepository: VisitRepositoryProtocol?
    private var serviceRepository: ServiceRepositoryProtocol?
    
    // MARK: Models
    var pet: Pet
    var visit: Visit 
    
    // MARK: UI State
    var sessionNotes: String = ""
    var amountString: String = ""
    var selectedServiceIDs: Set<PersistentIdentifier> = []
    var selectedPaymentMethod: Payment.Method = .creditCard
    var beforePhotoData: Data?
    var afterPhotoData: Data?
    var externalReference: String = ""
    var tags: Set<String> = []
    var selectedAddOnIDs: Set<PersistentIdentifier> = []
    
    // MARK: State
    private(set) var isSaving: Bool = false
    var appError: AppError? = nil
    var state: CheckoutState = .selectingServices
    
    // MARK: Private State
    var allServices: [Service] = []
    var addOnServices: [Service] = []
    private let checkoutEndsAt: Date?
    
    // MARK: Computed State
    var requiresExternalReference: Bool {
        selectedPaymentMethod.requiresExternalReference
    }
    
    var referencePlaceholder: String {
        switch selectedPaymentMethod {
        case .cash: return "Optional note"
        case .debitCard, .creditCard: return "Last 4 Digits"
        case .zelle: return "Transaction ID"
        case .other: return "Reference"
        }
    }
    
    var isConfirmEnabled: Bool {
        let ref = externalReference.trimmed
        let hasValidAmount = servicesTotalDecimal > 0
        return hasValidAmount && !isSaving && (!requiresExternalReference || !ref.isEmpty)
    }

    static let tagOptions: [String] = Pet.BehaviorTag.allCases.map { $0.displayName }

    var sessionDurationString: String {
        let start = visit.startedAt
        let end = visit.endedAt ?? checkoutEndsAt ?? Date()
        return Formatters.durationString(from: start, to: end)
    }

    var sessionEndedAt: Date { visit.endedAt ?? checkoutEndsAt ?? Date() }

    // MARK: - Cached Computed Properties
    private(set) var selectedServicesSummary: String = "None"
    private(set) var finalTotalString: String = "$0.00"

    init(pet: Pet, visit: Visit?) {
        self.pet = pet
        self.visit = visit ?? Visit(pet: pet)
        self.checkoutEndsAt = Date()
    }

    convenience init(pet: Pet) {
        self.init(pet: pet, visit: nil)
    }
    
    private static let serviceOrder: [String] = [
        "Full Package", "Basic Package", "Spa Package", "Bath", "Haircut"
    ]

    @MainActor
    func loadServices(modelContext: ModelContext) {
        Logger.checkout.info("CheckoutViewModel: Loading services")
        self.visitRepository = VisitRepository(modelContainer: modelContext.container)
        self.serviceRepository = ServiceRepository(modelContainer: modelContext.container)
        
        Task {
            do {
                guard let serviceRepository = serviceRepository else { 
                    Logger.checkout.error("CheckoutViewModel: Service repository is nil")
                    return 
                }
                let all = try await serviceRepository.fetchEnabledServices()
                Logger.checkout.info("CheckoutViewModel: Fetched \(all.count) services")

                let mainServices = all.filter { $0.category != .addOn }
                self.allServices = mainServices.sorted { svc1, svc2 in
                    let idx1 = Self.serviceOrder.firstIndex(of: svc1.name) ?? Int.max
                    let idx2 = Self.serviceOrder.firstIndex(of: svc2.name) ?? Int.max
                    return idx1 != idx2 ? idx1 < idx2 : svc1.name < svc2.name
                }

                self.addOnServices = all.filter { $0.category == .addOn }
                hydrateStateFromVisit()
                Logger.checkout.info("CheckoutViewModel: Hydration complete")
            } catch {
                Logger.checkout.error("CheckoutViewModel: Load failed - \(error.localizedDescription)")
                appError = .database("Failed to load services: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func hydrateStateFromVisit() {
        Logger.checkout.info("CheckoutViewModel: Hydrating from visit \(self.visit.uuid)")
        sessionNotes = visit.note?.trimmed ?? ""
        
        // Use tags from visit if present, otherwise fallback to pet's current tags
        if visit.behaviorTags.isEmpty {
            tags = Set(pet.behaviorTags)
        } else {
            tags = Set(visit.behaviorTags)
        }
        
        beforePhotoData = visit.beforePhotoData
        afterPhotoData  = visit.afterPhotoData
        
        // Load existing items into selection sets
        let allIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
        selectedServiceIDs = allIDs.filter { id in allServices.contains(where: { $0.persistentModelID == id }) }
        selectedAddOnIDs = allIDs.filter { id in addOnServices.contains(where: { $0.persistentModelID == id }) }

        // Set amount based on existing total if completed, or calculated total if active
        if visit.isCompleted && visit.total > 0 {
            amountString = visit.total.moneyString
        } else {
            updateAmountString()
        }
        
        recalculateCachedStrings()
    }
    
    func setAmountDirectly(_ text: String) {
        amountString = text
        recalculateCachedStrings()
    }
    
    func isServiceSelected(_ service: Service) -> Bool {
        selectedServiceIDs.contains(service.persistentModelID)
    }

    func isAddOnSelected(_ service: Service) -> Bool {
        selectedAddOnIDs.contains(service.persistentModelID)
    }

    /// Updates the local amountString based on current selection. 
    /// No longer mutates visit.items on the main thread.
    func updateVisitItems() {
        updateAmountString()
        recalculateCachedStrings()
    }

    private func updateAmountString() {
        let total = calculateTotalLocally()
        amountString = total.moneyString
    }

    private func calculateTotalLocally() -> Decimal {
        // Combined selection set for single-pass filtering
        let allSelected = selectedServiceIDs.union(selectedAddOnIDs)
        if allSelected.isEmpty { return .zero }
        
        let total = (allServices + addOnServices)
            .filter { allSelected.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 + $1.effectiveBasePrice }
            
        return total.roundedMoney()
    }

    func toggleService(_ service: Service) {
        let id = service.persistentModelID
        if selectedServiceIDs.contains(id) {
            selectedServiceIDs.remove(id)
        } else {
            selectedServiceIDs.insert(id)
        }
        updateAmountString()
        recalculateCachedStrings()
    }

    func toggleAddOn(_ service: Service) {
        let id = service.persistentModelID
        if selectedAddOnIDs.contains(id) {
            selectedAddOnIDs.remove(id)
        } else {
            selectedAddOnIDs.insert(id)
        }
        updateAmountString()
        recalculateCachedStrings()
    }
    
    func removeVisitItem(_ item: VisitItem) {
        // If it's a known service, remove from selection sets
        if let serviceID = item.service?.persistentModelID {
            selectedServiceIDs.remove(serviceID)
            selectedAddOnIDs.remove(serviceID)
        }
        updateAmountString()
        recalculateCachedStrings()
    }
    
    var subtotalDecimal: Decimal {
        calculateTotalLocally()
    }
    
    var servicesTotalDecimal: Decimal {
        if let manual = Formatters.parseCurrency(amountString) {
            return manual
        }
        return calculateTotalLocally()
    }
    
    func choosePayment(_ method: Payment.Method) {
        selectedPaymentMethod = method
        if !method.requiresExternalReference { externalReference = "" }
    }
    
    @MainActor
    func formatAmountInput() {
        let trimmed = amountString.trimmed
        if trimmed.isEmpty {
            amountString = ""
            return
        }
        if let dec = Formatters.parseCurrency(trimmed) {
            amountString = dec.moneyString
        } else {
            amountString = trimmed
        }
        recalculateCachedStrings()
    }

    /// Pre-calculates heavy strings to avoid blocking the UI during transitions.
    private func recalculateCachedStrings() {
        // 1. Total
        finalTotalString = servicesTotalDecimal.moneyString
        
        // 2. Summary
        let allSelected = selectedServiceIDs.union(selectedAddOnIDs)
        let sortedNames = (allServices + addOnServices)
            .filter { allSelected.contains($0.persistentModelID) }
            .map(\.name)
            .sorted()
            
        selectedServicesSummary = sortedNames.isEmpty ? "None" : sortedNames.joined(separator: ", ")
    }

    @MainActor
    func processPayment() async {
        guard !isSaving else { return }
        
        do {
            try validate()
        } catch {
            self.appError = .validation(error as? ValidationError ?? .custom(message: error.localizedDescription))
            return
        }

        isSaving = true
        state = .processing
        appError = nil
        Logger.checkout.info("CheckoutViewModel: Checkout started")

        do {
            let endedAt = try persistCheckout()
            state = .confirmed
            isSaving = false

            let userInfo: [String: Any] = [
                VisitDidCompleteKey.endedAt.rawValue: endedAt
            ]
            NotificationCenter.default.post(name: .visitDidComplete, object: visit, userInfo: userInfo)
            Logger.checkout.info("CheckoutViewModel: Checkout saved successfully")
        } catch {
            Logger.checkout.error("CheckoutViewModel: Persistence failed - \(error.localizedDescription)")
            let appErr = AppError.database("Persistence failed: \(error.localizedDescription)")
            state = .failed(appErr)
            appError = appErr
            isSaving = false
        }
    }

    private func persistCheckout() throws -> Date {
        guard let context = visit.modelContext ?? pet.modelContext else {
            throw AppError.database("Internal error: Data store unavailable.")
        }

        if visit.modelContext == nil {
            context.insert(visit)
        }

        let notes = sessionNotes.trimmed.isEmpty ? nil : sessionNotes.trimmed
        let sortedTags = Array(tags.sorted())
        let total = servicesTotalDecimal
        let ref = externalReference.trimmed
        let endedAt = visit.endedAt ?? checkoutEndsAt ?? Date()

        syncVisitItems(in: context)

        visit.note = notes
        visit.behaviorTags = sortedTags
        pet.setBehaviorTags(sortedTags)
        visit.applyPhotos(before: beforePhotoData, after: afterPhotoData)

        if let payment = visit.payment {
            payment.setAmount(total)
            payment.method = selectedPaymentMethod
            payment.paidAt = Date()
            payment.externalReference = ref.isEmpty ? nil : ref
        } else {
            let payment = Payment(
                amount: total,
                method: selectedPaymentMethod,
                paidAt: Date(),
                externalReference: ref.isEmpty ? nil : ref
            )
            context.insert(payment)
            visit.attachPayment(payment)
        }

        visit.markCheckedOut(total: total, now: endedAt)
        try context.save()
        return endedAt
    }

    private func syncVisitItems(in context: ModelContext) {
        let selectedIDs = selectedServiceIDs.union(selectedAddOnIDs)

        var existingItemsByServiceID: [PersistentIdentifier: VisitItem] = [:]
        for item in visit.items {
            if let serviceID = item.service?.persistentModelID {
                existingItemsByServiceID[serviceID] = item
            }
        }

        for (serviceID, item) in existingItemsByServiceID where !selectedIDs.contains(serviceID) {
            visit.removeItem(item)
            context.delete(item)
        }

        for service in allServices + addOnServices where selectedIDs.contains(service.persistentModelID) {
            if existingItemsByServiceID[service.persistentModelID] == nil {
                visit.addItem(
                    title: service.name,
                    unitPrice: service.effectiveBasePrice,
                    quantity: 1,
                    service: service
                )
            }
        }
    }
    
    private func validate() throws {
        let total = servicesTotalDecimal
        guard total > 0 else {
            throw ValidationError.custom(message: "Cannot check out with a total amount of zero.")
        }
        if requiresExternalReference && externalReference.trimmed.isEmpty {
            throw ValidationError.custom(message: "A reference is required for this payment method.")
        }
    }
}

private extension Logger {
    static let checkout = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Checkout")
}
