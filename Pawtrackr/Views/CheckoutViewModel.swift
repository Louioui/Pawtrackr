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
    enum CheckoutState {
        case selectingServices
        case addingPhotos
        case choosingPayment
        case processing
        case confirmed
        case failed(Error)
    }

    /// Lightweight state machine to centralize allowed transitions.
    private func canTransition(from: CheckoutState, to: CheckoutState) -> Bool {
        switch (from, to) {
        case (.selectingServices, .addingPhotos): return true
        case (.addingPhotos, .choosingPayment): return true
        case (.choosingPayment, .processing): return true
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
    @Published var additionalNotes: String = ""
    @Published var amountString: String = ""
    private var amountWasManuallySet: Bool = false
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

    /// Derived subtotal driven by the currently selected services or any existing visit items.
    /// Falls back to the visit's snapshot subtotal so editing an in-flight visit reflects its items.
    private var autoSubtotal: Decimal {
        let selectedTotal = selectedServicesTotal
        if selectedTotal > 0 { return selectedTotal }
        let visitTotal = visit.servicesSubtotal
        return visitTotal > 0 ? visitTotal : .zero
    }
    
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
    
    @MainActor
    func loadServices(modelContext: ModelContext) {
        self.modelContext = modelContext
        let descriptor = FetchDescriptor<Service>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.name)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        self.allServices = all.filter { $0.category != .addOn }
        self.addOnServices = all.filter { $0.category == .addOn }
        hydrateStateFromVisit()
    }

    // No deinit work needed.
    
    @MainActor
    private func hydrateStateFromVisit() {
        hydrateNotes()
        tags = Set(pet.behaviorTags)
        beforePhotoData = visit.beforePhotoData
        afterPhotoData  = visit.afterPhotoData
        
        let allIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
        selectedServiceIDs = allIDs.filter { id in allServices.contains(where: { $0.persistentModelID == id }) }
        selectedAddOnIDs = allIDs.filter { id in addOnServices.contains(where: { $0.persistentModelID == id }) }


        if visit.total > 0 && visit.isCompleted {
            amountString = visit.total.moneyString
            amountWasManuallySet = true
        } else {
            amountWasManuallySet = false
            updateAutoAmountFromSelection()
        }
        
        // Timer is frozen at checkout entry; no live ticking needed here.
    }

    private func hydrateNotes() {
        let existing = visit.note?.trimmed ?? ""
        guard !existing.isEmpty else {
            sessionNotes = ""
            additionalNotes = ""
            return
        }

        if let additionalRange = existing.range(of: "\n\nAdditional Notes:\n") {
            let sessionPart = String(existing[..<additionalRange.lowerBound])
            let additionalPart = String(existing[additionalRange.upperBound...])
            sessionNotes = sessionPart.replacingOccurrences(of: "Session Notes:\n", with: "").trimmed
            additionalNotes = additionalPart.trimmed
        } else if existing.hasPrefix("Session Notes:\n") {
            sessionNotes = existing.replacingOccurrences(of: "Session Notes:\n", with: "").trimmed
            additionalNotes = ""
        } else if existing.hasPrefix("Additional Notes:\n") {
            sessionNotes = ""
            additionalNotes = existing.replacingOccurrences(of: "Additional Notes:\n", with: "").trimmed
        } else {
            sessionNotes = existing
            additionalNotes = ""
        }
    }

    private func composeVisitNote() -> String? {
        let session = sessionNotes.trimmed
        let additional = additionalNotes.trimmed

        switch (session.isEmpty, additional.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return session
        case (true, false):
            return "Additional Notes:\n\(additional)"
        case (false, false):
            return "Session Notes:\n\(session)\n\nAdditional Notes:\n\(additional)"
        }
    }
    
    // MARK: - Intents
    
    /// Called when the user types directly into the amount field.
    func setAmountDirectly(_ text: String) {
        amountString = text
        amountWasManuallySet = true
    }

    /// Clears manual override and recomputes from selected services.
    @MainActor
    func resetManualAmount() {
        amountWasManuallySet = false
        updateAutoAmountFromSelection()
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
        updateAutoAmountFromSelection()
    }

    @MainActor
    func toggleAddOn(_ service: Service) {
        let id = service.persistentModelID
        if selectedAddOnIDs.contains(id) {
            selectedAddOnIDs.remove(id)
        } else {
            selectedAddOnIDs.insert(id)
        }
        updateAutoAmountFromSelection()
    }
    
    func choosePayment(_ method: Payment.Method) {
        selectedPaymentMethod = method
        if !method.requiresExternalReference { externalReference = "" }
    }
    
    @MainActor
    func formatAmountInput() {
        let trimmed = amountString.trimmed
        if trimmed.isEmpty {
            // Treat blank as no manual override so chips can drive the amount again
            amountWasManuallySet = false
            amountString = ""
            updateAutoAmountFromSelection()
            return
        }
        if let dec = Formatters.parseCurrency(trimmed) {
            amountString = dec.moneyString
            amountWasManuallySet = true
        } else {
            // Keep user's text but mark as manual so we don't clobber it; UI can show validation later
            amountWasManuallySet = true
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
        guard !isSaving else { return }
        guard let modelContext = modelContext else { return }
        isSaving = true
        if canTransition(from: state, to: .processing) { state = .processing }
        updateAutoAmountFromSelection()
        
        do {
            try validate()
            
            // If the visit was temporary, insert it into the context now.
            if visit.modelContext == nil {
                modelContext.insert(visit)
            }
            
            // 1. Sync VisitItems with selected services.
            let servicesToSnapshot = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
            let addOnsToSnapshot = addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }
            let allSelectedServices = servicesToSnapshot + addOnsToSnapshot
            let allSelectedIDs = Set(allSelectedServices.map { $0.persistentModelID })
            
            let existingServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
            
            // Remove items that are no longer selected
            visit.items.removeAll { item in
                guard let serviceID = item.service?.persistentModelID else { return false }
                return !allSelectedIDs.contains(serviceID)
            }
            // Add new items, snapshotting their price from the service catalog.
            for service in allSelectedServices where !existingServiceIDs.contains(service.persistentModelID) {
                visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: 1, service: service)
            }
            
            // 2. Apply notes, tags, and photos.
            visit.note = composeVisitNote()
            pet.setBehaviorTags(Array(tags))
            visit.applyPhotos(before: beforePhotoData, after: afterPhotoData)
            
            // 3. Finalize visit total and mark as checked out.
            // If already completed, preserve its original endedAt; otherwise, use captured checkout end.
            let finalEndedAt = visit.endedAt ?? checkoutEndsAt ?? Date()
            visit.markCheckedOut(total: servicesTotalDecimal, now: finalEndedAt)

            // 4. Create and attach payment.
            let cleanedRef = externalReference.trimmed
            let payment = Payment(
                amount: servicesTotalDecimal,
                method: selectedPaymentMethod,
                paidAt: Date(),
                externalReference: cleanedRef.isEmpty ? nil : cleanedRef
            )
            visit.attachPayment(payment)
            
            // 5. Save and notify.
            try modelContext.save()
            // Update daily summaries for Insights immediately
            SummaryUpdater.rebuildDay(for: finalEndedAt, in: modelContext)
            NotificationCenter.default.post(
                name: .visitDidComplete,
                object: nil,
                userInfo: [
                    VisitDidCompleteKey.visitID.rawValue: visit.persistentModelID,
                    VisitDidCompleteKey.petID.rawValue: visit.pet.persistentModelID,
                    VisitDidCompleteKey.clientID.rawValue: visit.pet.owner?.persistentModelID as Any,
                    VisitDidCompleteKey.endedAt.rawValue: finalEndedAt,
                    VisitDidCompleteKey.total.rawValue: servicesTotalDecimal
                ].compactMapValues { $0 }
            )
            
            isSaving = false
            if canTransition(from: .processing, to: .confirmed) { state = .confirmed }
            
        } catch let error as ValidationError {
            if canTransition(from: .processing, to: .failed(error)) { state = .failed(error) } else { state = .failed(error) }
            alertMessage = error.localizedDescription
            showAlert = true
        } catch {
            let error = ValidationError.custom(message: "An unexpected error occurred while saving. Please try again.")
            if canTransition(from: .processing, to: .failed(error)) { state = .failed(error) } else { state = .failed(error) }
            alertMessage = error.localizedDescription
            Logger.main.error("Checkout save failed: \(error.localizedDescription)")
            showAlert = true
        }
        
        isSaving = false
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
    
    /// Keeps the amount in sync with selected services unless the user explicitly set it.
    @MainActor
    private func updateAutoAmountFromSelection() {
        guard !amountWasManuallySet else { return }
        amountString = autoSubtotal.moneyString
    }
    
    // MARK: - Derived Totals
    
    private var selectedServicesTotal: Decimal {
        let mainServices = allServices
            .filter { selectedServiceIDs.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 +~ $1.effectiveBasePrice }
        let addOnServices = addOnServices
            .filter { selectedAddOnIDs.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 +~ $1.effectiveBasePrice }
        return mainServices + addOnServices
    }
    
    @MainActor
    var servicesTotalDecimal: Decimal {
        return Formatters.parseCurrency(amountString) ?? .zero
    }
    
    @MainActor
    var finalTotalString: String {
        servicesTotalDecimal.moneyString
    }
}
