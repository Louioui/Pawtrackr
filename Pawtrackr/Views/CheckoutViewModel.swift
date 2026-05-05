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

    func updateVisitItems() {
        // Update visit items based on selection
        let servicesToSnapshot = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
        let addOnsToSnapshot = addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }
        let allSelectedServices = servicesToSnapshot + addOnsToSnapshot
        let allSelectedIDs = Set(allSelectedServices.map { $0.persistentModelID })

        // Remove items that were unselected
        visit.items.removeAll { item in
            guard let serviceID = item.service?.persistentModelID else { return false }
            return !allSelectedIDs.contains(serviceID)
        }

        // Add missing items
        let existingServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
        for service in allSelectedServices where !existingServiceIDs.contains(service.persistentModelID) {
            visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: 1, service: service)
        }

        amountString = visit.calculatedTotal.moneyString
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
    
    func removeVisitItem(_ item: VisitItem) {
        visit.removeItem(item)
        hydrateStateFromVisit()
        updateVisitItems()
    }
    
    var subtotalDecimal: Decimal {
        return visit.servicesSubtotal
    }
    
    var servicesTotalDecimal: Decimal {
        // If the user manually edited amountString, we respect that if it differs from the calculated total.
        if let manual = Formatters.parseCurrency(amountString), 
           manual != visit.calculatedTotal {
            return manual
        }
        return visit.calculatedTotal
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
        // Verify we have what we need
        if visitRepository == nil {
            appError = .database("Internal error: data store unavailable")
            return
        }

        isSaving = true
        state = .processing
        appError = nil

        // Snapshot necessary values for background processing
        let notes = sessionNotes.trimmed.isEmpty ? nil : sessionNotes.trimmed
        let sortedTags = Array(tags.sorted())
        let before = beforePhotoData
        let after = afterPhotoData
        let total = servicesTotalDecimal
        let method = selectedPaymentMethod
        let ref = externalReference.trimmed
        let endedAt = visit.endedAt ?? checkoutEndsAt ?? Date()
        let visitID = visit.persistentModelID
        let petID = pet.persistentModelID
        
        guard let modelContainer = visit.modelContext?.container else {
            appError = .database("Internal error: Visit is not associated with a data store.")
            isSaving = false
            state = .failed(appError!)
            return
        }

        Task.detached(priority: .userInitiated) { [visitID, petID] in
            do {
                let bgContext = ModelContext(modelContainer)
                
                // Fetch models in background context
                guard let bgVisit = bgContext.model(for: visitID) as? Visit,
                      let bgPet = bgContext.model(for: petID) as? Pet else {
                    throw AppError.database("Could not retrieve visit data in background.")
                }

                // 1. Update background visit/pet state
                bgVisit.note = notes
                bgVisit.behaviorTags = sortedTags
                bgPet.setBehaviorTags(sortedTags)
                bgVisit.applyPhotos(before: before, after: after)

                // 2. Create and attach payment
                let payment = Payment(
                    amount: total,
                    method: method,
                    paidAt: Date(),
                    externalReference: ref.isEmpty ? nil : ref
                )
                bgVisit.attachPayment(payment)

                // 3. Finalize checkout logic
                bgVisit.markCheckedOut(total: total, now: endedAt)
                
                // 4. Save background context
                try bgContext.save()

                // 5. Success UI Update
                await MainActor.run {
                    self.state = .confirmed
                    self.isSaving = false
                    
                    // Trigger summary rebuild notification
                    let userInfo: [String: Any] = [
                        VisitDidCompleteKey.endedAt.rawValue: endedAt
                    ]
                    NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: userInfo)
                }
            } catch {
                await MainActor.run {
                    let appErr = AppError.database(error.localizedDescription)
                    self.state = .failed(appErr)
                    self.appError = appErr
                    self.isSaving = false
                    Logger.checkout.error("Checkout background save failed: \(error.localizedDescription)")
                }
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
    
    var finalTotalString: String {
        servicesTotalDecimal.moneyString
    }

    // Cached summary so CheckoutView doesn't recompute on every render.
    var selectedServicesSummary: String {
        let mainNames  = allServices.filter  { selectedServiceIDs.contains($0.persistentModelID) }.map(\.name)
        let addOnNames = addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID)  }.map(\.name)
        let sorted = (mainNames + addOnNames).sorted()
        return sorted.isEmpty ? "None" : sorted.joined(separator: ", ")
    }
}

private extension Logger {
    static let checkout = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Checkout")
}
