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
        Logger.main.info("CheckoutViewModel: Loading services")
        self.visitRepository = VisitRepository(modelContainer: modelContext.container)
        self.serviceRepository = ServiceRepository(modelContainer: modelContext.container)
        
        Task {
            do {
                guard let serviceRepository = serviceRepository else { 
                    Logger.main.error("CheckoutViewModel: Service repository is nil")
                    return 
                }
                let all = try await serviceRepository.fetchEnabledServices()
                Logger.main.info("CheckoutViewModel: Fetched \(all.count) services")

                let mainServices = all.filter { $0.category != .addOn }
                self.allServices = mainServices.sorted { svc1, svc2 in
                    let idx1 = Self.serviceOrder.firstIndex(of: svc1.name) ?? Int.max
                    let idx2 = Self.serviceOrder.firstIndex(of: svc2.name) ?? Int.max
                    return idx1 != idx2 ? idx1 < idx2 : svc1.name < svc2.name
                }

                self.addOnServices = all.filter { $0.category == .addOn }
                hydrateStateFromVisit()
                Logger.main.info("CheckoutViewModel: Hydration complete")
            } catch {
                Logger.main.error("CheckoutViewModel: Load failed - \(error.localizedDescription)")
                appError = .database("Failed to load services: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func hydrateStateFromVisit() {
        Logger.main.info("CheckoutViewModel: Hydrating from visit \(self.visit.uuid)")
        sessionNotes = visit.note?.trimmed ?? ""
        if visit.behaviorTags.isEmpty {
            tags = Set(pet.behaviorTags)
        } else {
            tags = Set(visit.behaviorTags)
        }
        beforePhotoData = visit.beforePhotoData
        afterPhotoData  = visit.afterPhotoData
        
        let allIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
        selectedServiceIDs = allIDs.filter { id in allServices.contains(where: { $0.persistentModelID == id }) }
        selectedAddOnIDs = allIDs.filter { id in addOnServices.contains(where: { $0.persistentModelID == id }) }

        if visit.total > 0 && visit.isCompleted {
            amountString = visit.total.moneyString
        } else {
            amountString = ""
        }
    }
    
    func setAmountDirectly(_ text: String) {
        amountString = text
    }
    
    func isServiceSelected(_ service: Service) -> Bool {
        selectedServiceIDs.contains(service.persistentModelID)
    }

    func isAddOnSelected(_ service: Service) -> Bool {
        selectedAddOnIDs.contains(service.persistentModelID)
    }

    func syncSubtotal() {
        let mainTotal = allServices
            .filter { selectedServiceIDs.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 + $1.effectiveBasePrice }
        
        let addOnTotal = addOnServices
            .filter { selectedAddOnIDs.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 + $1.effectiveBasePrice }
        
        let total = (mainTotal + addOnTotal).roundedMoney()
        amountString = total.moneyString
    }

    func toggleService(_ service: Service) {
        let id = service.persistentModelID
        if selectedServiceIDs.contains(id) {
            selectedServiceIDs.remove(id)
        } else {
            selectedServiceIDs.insert(id)
        }
    }

    func toggleAddOn(_ service: Service) {
        let id = service.persistentModelID
        if selectedAddOnIDs.contains(id) {
            selectedAddOnIDs.remove(id)
        } else {
            selectedAddOnIDs.insert(id)
        }
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
    }

    @MainActor
    func processPayment() async {
        guard !isSaving else { return }
        guard let visitRepository = visitRepository else {
            appError = .database("Internal error: data store unavailable")
            return
        }

        isSaving = true
        state = .processing

        defer { isSaving = false }

        await Task.yield()

        do {
            try validate()

            let servicesToSnapshot = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
            let addOnsToSnapshot = addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }
            let allSelectedServices = servicesToSnapshot + addOnsToSnapshot
            let allSelectedIDs = Set(allSelectedServices.map { $0.persistentModelID })

            let existingServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })

            visit.items.removeAll { item in
                guard let serviceID = item.service?.persistentModelID else { return false }
                return !allSelectedIDs.contains(serviceID)
            }

            for service in allSelectedServices where !existingServiceIDs.contains(service.persistentModelID) {
                visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: 1, service: service)
            }

            visit.note = sessionNotes.trimmed.isEmpty ? nil : sessionNotes.trimmed
            let sortedTags = Array(tags.sorted())
            visit.behaviorTags = sortedTags
            pet.setBehaviorTags(sortedTags)
            visit.applyPhotos(before: beforePhotoData, after: afterPhotoData)

            let cleanedRef = externalReference.trimmed
            let payment = Payment(
                amount: servicesTotalDecimal,
                method: selectedPaymentMethod,
                paidAt: Date(),
                externalReference: cleanedRef.isEmpty ? nil : cleanedRef
            )
            visit.attachPayment(payment)

            let finalEndedAt = visit.endedAt ?? checkoutEndsAt ?? Date()
            try await visitRepository.checkOut(visit: visit, total: servicesTotalDecimal, now: finalEndedAt)

            state = .confirmed
        } catch let error as ValidationError {
            let appErr = AppError.validation(error)
            state = .failed(appErr)
            appError = appErr
        } catch {
            let appErr = AppError.database(error.localizedDescription)
            state = .failed(appErr)
            appError = appErr
            Logger.main.error("Checkout save failed: \(error.localizedDescription)")
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
    
    var servicesTotalDecimal: Decimal {
        return Formatters.parseCurrency(amountString) ?? .zero
    }
    
    var finalTotalString: String {
        servicesTotalDecimal.moneyString
    }
}
