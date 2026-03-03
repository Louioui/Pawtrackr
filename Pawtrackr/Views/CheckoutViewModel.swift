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

final class CheckoutViewModel: ObservableObject {
    enum CheckoutState: Equatable {
        case selectingServices
        case addingPhotos
        case choosingPayment
        case processing
        case confirmed
        case failed(String) // Changed from Error to String for Equatable conformance

        static func == (lhs: CheckoutState, rhs: CheckoutState) -> Bool {
            switch (lhs, rhs) {
            case (.selectingServices, .selectingServices),
                 (.addingPhotos, .addingPhotos),
                 (.choosingPayment, .choosingPayment),
                 (.processing, .processing),
                 (.confirmed, .confirmed):
                return true
            case (.failed(let lhsMsg), .failed(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    /// Lightweight state machine to centralize allowed transitions.
    private func canTransition(from: CheckoutState, to: CheckoutState) -> Bool {
        switch (from, to) {
        case (.selectingServices, .addingPhotos): return true
        case (.addingPhotos, .choosingPayment): return true
        // Allow processing from any input state (user can complete checkout at any step)
        case (.selectingServices, .processing),
             (.addingPhotos, .processing),
             (.choosingPayment, .processing): return true
        case (.processing, .confirmed), (.processing, .failed(_)): return true
        case (.failed(_), .selectingServices), (.failed(_), .addingPhotos), (.failed(_), .choosingPayment): return true
        default: return false
        }
    }

    // MARK: Dependencies
    var modelContext: ModelContext?
    
    // MARK: Models
    var pet: Pet
    var visit: Visit // This will now be the active visit, or a new one created upon confirmation.
    
    // MARK: UI State
    @Published var sessionNotes: String = ""
    @Published var amountString: String = ""
    @Published var selectedServiceIDs: Set<PersistentIdentifier> = []
    @Published var selectedPaymentMethod: Payment.Method = .creditCard
    @Published var beforePhotoData: Data?
    @Published var afterPhotoData: Data?
    @Published var externalReference: String = ""
    @Published var tags: Set<String> = []
    @Published var selectedAddOnIDs: Set<PersistentIdentifier> = []

    // MARK: Published State
    @Published private(set) var isSaving: Bool = false
    @Published var showAlert: Bool = false
    @Published private(set) var alertMessage: String = ""
    @Published var state: CheckoutState = .selectingServices
    
    // MARK: Private State
    var allServices: [Service] // Fetched once for performance; exposed for view rendering.
    var addOnServices: [Service] = []
    private let checkoutEndsAt: Date?
    
    // MARK: Computed State
    var requiresExternalReference: Bool {
        selectedPaymentMethod.requiresExternalReference
    }
    
    var referencePlaceholder: String {
        switch selectedPaymentMethod {
        case .cash:
            return "Optional note"
        case .debitCard, .creditCard:
            return "Last 4 Digits"
        case .zelle:
            return "Transaction ID"
        case .other:
            return "Reference"
        }
    }
    
    @MainActor
    var isConfirmEnabled: Bool {
        let ref = externalReference.trimmed
        let hasValidAmount = servicesTotalDecimal > 0
        return hasValidAmount && !isSaving && (!requiresExternalReference || !ref.isEmpty)
    }

    static let tagOptions: [String] = Pet.BehaviorTag.allCases.map { $0.displayName }

    /// Duration string captured at checkout: check-in starts timer, checkout stops it.
    @MainActor
    var sessionDurationString: String {
        let start = visit.startedAt
        let end = visit.endedAt ?? checkoutEndsAt ?? Date()
        return Formatters.durationString(from: start, to: end)
    }

    /// The captured end timestamp used for the checkout summary (not persisted until confirm).
    var sessionEndedAt: Date { visit.endedAt ?? checkoutEndsAt ?? Date() }

    @MainActor
    init(pet: Pet, visit: Visit?) {
        self.pet = pet
        self.visit = visit ?? Visit(pet: pet)
        self.checkoutEndsAt = Date()
        self.allServices = []
    }

    /// Backwards-compatible initializer: creates a new Visit if none provided.
    @MainActor
    convenience init(pet: Pet) {
        self.init(pet: pet, visit: nil)
    }
    
    /// Define the preferred order for main services (packages and main services)
    private static let serviceOrder: [String] = [
        "Full Package",
        "Basic Package",
        "Spa Package",
        "Bath",
        "Haircut"
    ]

    @MainActor
    func loadServices(modelContext: ModelContext) {
        self.modelContext = modelContext
        let descriptor = FetchDescriptor<Service>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.name)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []

        // Separate main services (packages + groom) from add-ons
        let mainServices = all.filter { $0.category != .addOn }

        // Sort main services by the predefined order
        self.allServices = mainServices.sorted { svc1, svc2 in
            let idx1 = Self.serviceOrder.firstIndex(of: svc1.name) ?? Int.max
            let idx2 = Self.serviceOrder.firstIndex(of: svc2.name) ?? Int.max
            if idx1 != idx2 {
                return idx1 < idx2
            }
            // Fall back to alphabetical for services not in the predefined list
            return svc1.name < svc2.name
        }

        self.addOnServices = all.filter { $0.category == .addOn }
        hydrateStateFromVisit()
    }

    // No deinit work needed.
    
    @MainActor
    private func hydrateStateFromVisit() {
        hydrateNotes()
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
        
        // Timer is frozen at checkout entry; no live ticking needed here.
    }

    private func hydrateNotes() {
        sessionNotes = visit.note?.trimmed ?? ""
    }

    private func composeVisitNote() -> String? {
        let session = sessionNotes.trimmed
        return session.isEmpty ? nil : session
    }
    
    // MARK: - Intents
    
    /// Called when the user types directly into the amount field.
    func setAmountDirectly(_ text: String) {
        amountString = text
    }
    
    func isServiceSelected(_ service: Service) -> Bool {
        selectedServiceIDs.contains(service.persistentModelID)
    }

    func isAddOnSelected(_ service: Service) -> Bool {
        selectedAddOnIDs.contains(service.persistentModelID)
    }

    @MainActor
    func toggleService(_ service: Service) {
        let id = service.persistentModelID
        if selectedServiceIDs.contains(id) {
            selectedServiceIDs.remove(id)
        } else {
            selectedServiceIDs.insert(id)
        }
    }

    @MainActor
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
            // Keep user's text; UI can show validation later
            amountString = trimmed
        }
    }

    func nextStep() {
        switch state {
        case .selectingServices:
            if canTransition(from: state, to: .addingPhotos) { state = .addingPhotos }
        case .addingPhotos:
            if canTransition(from: state, to: .choosingPayment) { state = .choosingPayment }
        case .choosingPayment:
            Task { await processPayment() }
        default:
            break
        }
    }

    func previousStep() {
        switch state {
        case .addingPhotos:
            if canTransition(from: .addingPhotos, to: .selectingServices) { state = .selectingServices }
            else { state = .selectingServices }
        case .choosingPayment:
            if canTransition(from: .choosingPayment, to: .addingPhotos) { state = .addingPhotos }
            else { state = .addingPhotos }
        default:
            break
        }
    }
    
    @MainActor
    func processPayment() async {
        print("DEBUG: processPayment started")
        guard !isSaving else {
            print("DEBUG: Already saving, returning early")
            return
        }
        guard let modelContext = modelContext else {
            print("DEBUG: modelContext is nil")
            alertMessage = "Unable to save. Please try again."
            showAlert = true
            return
        }

        print("DEBUG: Setting isSaving = true")
        isSaving = true
        state = .processing

        // Guarantee cleanup no matter what happens
        defer {
            print("DEBUG: defer block executing, isSaving=\(isSaving)")
            if isSaving {
                isSaving = false
                print("DEBUG: defer set isSaving = false")
            }
        }

        // Yield to allow UI to update and show processing overlay
        await Task.yield()
        print("DEBUG: After first yield")

        do {
            print("DEBUG: About to validate")
            try validate()
            print("DEBUG: Validation passed")

            // If the visit was temporary, insert it into the context now.
            print("DEBUG: Checking if visit needs insertion")
            if visit.modelContext == nil {
                print("DEBUG: Inserting visit into context")
                modelContext.insert(visit)
            }
            print("DEBUG: Visit context check done")

            // 1. Sync VisitItems with selected services.
            print("DEBUG: Starting service sync - allServices count: \(allServices.count)")
            let servicesToSnapshot = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
            print("DEBUG: servicesToSnapshot count: \(servicesToSnapshot.count)")
            let addOnsToSnapshot = addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }
            print("DEBUG: addOnsToSnapshot count: \(addOnsToSnapshot.count)")
            let allSelectedServices = servicesToSnapshot + addOnsToSnapshot
            let allSelectedIDs = Set(allSelectedServices.map { $0.persistentModelID })
            print("DEBUG: allSelectedIDs count: \(allSelectedIDs.count)")

            print("DEBUG: Getting existing service IDs from visit.items")
            let existingServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
            print("DEBUG: existingServiceIDs count: \(existingServiceIDs.count)")

            // Remove items that are no longer selected
            print("DEBUG: Removing unselected items")
            visit.items.removeAll { item in
                guard let serviceID = item.service?.persistentModelID else { return false }
                return !allSelectedIDs.contains(serviceID)
            }
            print("DEBUG: Items removed")

            // Add new items, snapshotting their price from the service catalog.
            print("DEBUG: Adding new items")
            for service in allSelectedServices where !existingServiceIDs.contains(service.persistentModelID) {
                visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: 1, service: service)
            }
            print("DEBUG: Items added")

            // 2. Apply notes, tags, and photos.
            print("DEBUG: Applying notes and tags")
            visit.note = composeVisitNote()
            let sortedTags = Array(tags.sorted())
            visit.behaviorTags = sortedTags
            pet.setBehaviorTags(sortedTags)
            print("DEBUG: Applying photos")
            visit.applyPhotos(before: beforePhotoData, after: afterPhotoData)
            print("DEBUG: Notes, tags, photos applied")

            // 3. Finalize visit total and mark as checked out.
            print("DEBUG: Marking checked out")
            let finalEndedAt = visit.endedAt ?? checkoutEndsAt ?? Date()
            visit.markCheckedOut(total: servicesTotalDecimal, now: finalEndedAt)
            print("DEBUG: Visit marked checked out")

            // 4. Create and attach payment.
            print("DEBUG: Getting cleanedRef")
            let cleanedRef = externalReference.trimmed
            print("DEBUG: cleanedRef = \(cleanedRef)")
            print("DEBUG: Getting servicesTotalDecimal")
            let paymentAmount = servicesTotalDecimal
            print("DEBUG: paymentAmount = \(paymentAmount)")
            print("DEBUG: Creating Payment object - method: \(selectedPaymentMethod)")
            let paymentDate = Date()
            print("DEBUG: Payment date created")
            let paymentRef: String? = cleanedRef.isEmpty ? nil : cleanedRef
            print("DEBUG: Payment ref: \(String(describing: paymentRef))")

            // Create payment with minimal params first
            print("DEBUG: About to call Payment init")
            let payment = Payment(
                amount: paymentAmount,
                method: selectedPaymentMethod,
                paidAt: paymentDate,
                externalReference: paymentRef
            )
            print("DEBUG: Payment init completed")
            print("DEBUG: Payment created, attaching to visit")
            visit.attachPayment(payment)
            print("DEBUG: Payment attached")

            // 5. Save
            print("DEBUG: About to save modelContext")
            try modelContext.save()
            print("DEBUG: modelContext saved successfully")

            // 6. Notify (wrapped to prevent observer issues from blocking completion)
            let notificationInfo: [String: Any] = [
                VisitDidCompleteKey.visitID.rawValue: visit.persistentModelID,
                VisitDidCompleteKey.petID.rawValue: visit.pet?.persistentModelID as Any,
                VisitDidCompleteKey.clientID.rawValue: visit.pet?.owner?.persistentModelID as Any,
                VisitDidCompleteKey.endedAt.rawValue: finalEndedAt,
                VisitDidCompleteKey.total.rawValue: servicesTotalDecimal
            ].compactMapValues { $0 }

            print("DEBUG: Posting notification asynchronously")
            // Post notification asynchronously so it doesn't block checkout completion
            Task.detached { @MainActor in
                NotificationCenter.default.post(
                    name: .visitDidComplete,
                    object: nil,
                    userInfo: notificationInfo
                )
            }

            // Success - update state immediately
            print("DEBUG: Setting state = .confirmed and isSaving = false")
            state = .confirmed
            isSaving = false
            print("DEBUG: processPayment SUCCESS - isSaving is now \(isSaving)")

        } catch let error as ValidationError {
            print("DEBUG: ValidationError caught: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            alertMessage = error.localizedDescription
            showAlert = true
            isSaving = false
        } catch {
            print("DEBUG: General error caught: \(error.localizedDescription)")
            let message = "An unexpected error occurred while saving. Please try again."
            state = .failed(message)
            alertMessage = message
            Logger.main.error("Checkout save failed: \(error.localizedDescription)")
            showAlert = true
            isSaving = false
        }
        print("DEBUG: processPayment function exiting")
    }
    
    @MainActor
    private func validate() throws {
        let total = servicesTotalDecimal
        guard total > 0 else {
            throw ValidationError.custom(message: "Cannot check out with a total amount of zero.")
        }
        let ref = externalReference.trimmed
        if requiresExternalReference && ref.isEmpty {
            throw ValidationError.custom(message: "A reference (e.g., Last 4, Txn ID) is required for this payment method.")
        }
    }
    
    // MARK: - Private Helpers
    
    // MARK: - Derived Totals
    
    @MainActor
    var servicesTotalDecimal: Decimal {
        return Formatters.parseCurrency(amountString) ?? .zero
    }
    
    @MainActor
    var finalTotalString: String {
        servicesTotalDecimal.moneyString
    }
}
