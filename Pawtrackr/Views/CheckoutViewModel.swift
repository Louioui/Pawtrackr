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
    enum CheckoutState {
        case selectingServices
        case addingPhotos
        case choosingPayment
        case processing
        case confirmed
        case failed(Error)
    }

    // MARK: Dependencies
    private var modelContext: ModelContext
    
    // MARK: Models
    var pet: Pet
    var visit: Visit // This will now be the active visit, or a new one created upon confirmation.
    
    // MARK: UI State
    var notes: String = ""
    var amountString: String = ""
    private var amountWasManuallySet: Bool = false
    var selectedServiceIDs: Set<PersistentIdentifier> = []
    var selectedPaymentMethod: Payment.Method = .creditCard
    var beforePhotoData: Data?
    var afterPhotoData: Data?
    var externalReference: String = ""
    var tags: Set<String> = []
    var selectedExtras: Set<String> = []

    // MARK: Published State
    private(set) var isSaving: Bool = false
    var showAlert: Bool = false
    private(set) var alertMessage: String = ""
    var state: CheckoutState = .selectingServices
    
    // MARK: Private State
    let allServices: [Service] // Fetched once for performance; exposed for view rendering.
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
    
    var isConfirmEnabled: Bool {
        let ref = externalReference.trimmed
        let hasValidAmount = servicesTotalDecimal > 0
        return hasValidAmount && !isSaving && (!requiresExternalReference || !ref.isEmpty)
    }

    static let tagOptions: [String] = Pet.BehaviorTag.allCases.map { $0.displayName }

    /// Duration string captured at checkout: check-in starts timer, checkout stops it.
    var sessionDurationString: String {
        let start = visit.startedAt
        let end = visit.endedAt ?? checkoutEndsAt ?? Date()
        return Formatters.durationString(from: start, to: end)
    }

    /// The captured end timestamp used for the checkout summary (not persisted until confirm).
    var sessionEndedAt: Date { visit.endedAt ?? checkoutEndsAt ?? Date() }

    init(pet: Pet, modelContext: ModelContext) {
        self.pet = pet
        self.modelContext = modelContext

        // Fetch services ONCE on initialization for performance.
        let descriptor = FetchDescriptor<Service>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.name)]
        )
        self.allServices = (try? modelContext.fetch(descriptor)) ?? []

        // Choose the most recent visit (active if present; otherwise the latest ended visit).
        let visitCandidate: Visit
        if let recent = pet.visits.sorted(by: { $0.sortKeyDate > $1.sortKeyDate }).first {
            visitCandidate = recent
        } else {
            // Create a temporary visit for the UI, but DON'T insert it yet.
            // It will only be inserted upon confirmation.
            visitCandidate = Visit(pet: pet)
            Logger.main.info("Staging new visit for pet \(pet.name).")
        }
        self.visit = visitCandidate

        // Capture a local end timestamp for display, but do not persist.
        // If the user cancels, the session resumes. If they confirm, we persist this value.
        self.checkoutEndsAt = (visitCandidate.endedAt == nil) ? Date() : nil

        hydrateStateFromVisit()
    }

    // No deinit work needed.
    
    private func hydrateStateFromVisit() {
        notes = visit.note ?? ""
        tags = Set(pet.behaviorTags)
        beforePhotoData = visit.beforePhotoData
        afterPhotoData  = visit.afterPhotoData
        
        selectedServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })

        if visit.total > 0 && visit.isCompleted {
            amountString = visit.total.moneyString
            amountWasManuallySet = true
        } else {
            amountWasManuallySet = false
            recomputeAmountFromServices()
        }
        
        // Timer is frozen at checkout entry; no live ticking needed here.
    }
    
    // MARK: - Intents
    
    /// Called when the user types directly into the amount field.
    func setAmountDirectly(_ text: String) {
        amountString = text
        amountWasManuallySet = true
    }

    /// Clears manual override and recomputes from selected services.
    func resetManualAmount() {
        amountWasManuallySet = false
        recomputeAmountFromServices()
    }
    
    func isServiceSelected(_ service: Service) -> Bool {
        selectedServiceIDs.contains(service.persistentModelID)
    }

    func toggleService(_ service: Service) {
        let id = service.persistentModelID
        if selectedServiceIDs.contains(id) {
            selectedServiceIDs.remove(id)
        } else {
            selectedServiceIDs.insert(id)
        }
        if !amountWasManuallySet {
            recomputeAmountFromServices()
        }
    }
    
    func choosePayment(_ method: Payment.Method) {
        selectedPaymentMethod = method
        if !method.requiresExternalReference { externalReference = "" }
    }
    
    func formatAmountInput() {
        let trimmed = amountString.trimmed
        if trimmed.isEmpty {
            // Treat blank as no manual override so chips can drive the amount again
            amountWasManuallySet = false
            amountString = ""
            recomputeAmountFromServices()
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
            state = .addingPhotos
        case .addingPhotos:
            state = .choosingPayment
        case .choosingPayment:
            Task { await processPayment() }
        default:
            break
        }
    }

    func previousStep() {
        switch state {
        case .addingPhotos:
            state = .selectingServices
        case .choosingPayment:
            state = .addingPhotos
        default:
            break
        }
    }
    
    func processPayment() async {
        guard !isSaving else { return }
        isSaving = true
        state = .processing
        
        do {
            try validate()
            
            // If the visit was temporary, insert it into the context now.
            if visit.modelContext == nil {
                modelContext.insert(visit)
            }
            
            // 1. Sync VisitItems with selected services.
            let servicesToSnapshot = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
            let existingServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })
            
            // Remove items that are no longer selected
            visit.items.removeAll { item in
                guard let serviceID = item.service?.persistentModelID else { return false }
                return !selectedServiceIDs.contains(serviceID)
            }
            // Add new items, snapshotting their price from the service catalog.
            for service in servicesToSnapshot where !existingServiceIDs.contains(service.persistentModelID) {
                visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: 1, service: service)
            }

            // Add selected extras as line items with a zero price. Their cost is assumed
            // to be included in the final manual total if one was provided.
            for extra in selectedExtras {
                visit.addItem(title: extra, unitPrice: 0, quantity: 1, service: nil)
            }
            
            // 2. Apply notes, tags, and photos.
            visit.note = notes.trimmed.isEmpty ? nil : notes.trimmed
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
            NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: ["visitID": visit.persistentModelID])
            
            isSaving = false
            state = .confirmed
            
        } catch let error as ValidationError {
            state = .failed(error)
            alertMessage = error.localizedDescription
            showAlert = true
        } catch {
            let error = ValidationError.custom(message: "An unexpected error occurred while saving. Please try again.")
            state = .failed(error)
            alertMessage = error.localizedDescription
            Logger.main.error("Checkout save failed: \(error.localizedDescription)")
            showAlert = true
        }
        
        isSaving = false
    }
    
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
    
    private func recomputeAmountFromServices() {
        let sum = selectedServicesTotal
        amountString = sum > 0 ? sum.moneyString : ""
    }
    
    // MARK: - Derived Totals
    
    private var selectedServicesTotal: Decimal {
        allServices
            .filter { selectedServiceIDs.contains($0.persistentModelID) }
            .reduce(Decimal.zero) { $0 +~ $1.effectiveBasePrice }
    }
    
    var servicesTotalDecimal: Decimal {
        if amountWasManuallySet {
            return Formatters.parseCurrency(amountString) ?? .zero
        } else {
            return selectedServicesTotal
        }
    }
    
    var finalTotalString: String {
        servicesTotalDecimal.moneyString
    }
}
