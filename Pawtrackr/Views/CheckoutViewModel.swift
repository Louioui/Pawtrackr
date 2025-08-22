//
//  CheckoutViewModel.swift
//  Pawtrackr
//
//  Updated by ChatGPT on 2025-08-21
//

import SwiftUI
import SwiftData

@MainActor
final class CheckoutViewModel: ObservableObject {
    // MARK: Inputs bound from the view
    @Published var notes: String = ""
    @Published var amountString: String = ""
    @Published var selectedServiceIDs: Set<PersistentIdentifier> = []
    @Published var selectedPaymentMethod: Payment.Method = .cash
    @Published var beforePhotoData: Data?
    @Published var afterPhotoData: Data?

    // MARK: Outputs / derived state
    @Published private(set) var isConfirmEnabled: Bool = false

    // MARK: Dependencies / context
    private let modelContext: ModelContext
    private let pet: Pet
    private(set) var visit: Visit

    init(pet: Pet, modelContext: ModelContext) {
        self.modelContext = modelContext
        self.pet = pet

        // Reuse active visit if present, otherwise create one
        if let active = pet.activeVisit {
            self.visit = active
        } else {
            let v = Visit(pet: pet, startedAt: Date())
            modelContext.insert(v)
            self.visit = v
        }

        // Hydrate UI state from visit
        self.notes = visit.notes ?? ""
        self.beforePhotoData = visit.photoBefore
        self.afterPhotoData  = visit.photoAfter
        self.amountString = Formatters.currencyEditingString(for: visit.total)
        self.selectedServiceIDs = Set(visit.items.compactMap { $0.service?.persistentModelID })

        recomputeConfirmEnabled()
    }

    // MARK: Intents

    func toggleService(_ service: Service) {
        let id = service.persistentModelID
        if selectedServiceIDs.contains(id) {
            selectedServiceIDs.remove(id)
            removeItem(for: service)
        } else {
            selectedServiceIDs.insert(id)
            addItem(for: service)
        }
        recomputeConfirmEnabled()
    }

    func choosePayment(_ method: Payment.Method) {
        selectedPaymentMethod = method
        recomputeConfirmEnabled()
    }

    func setAmount(_ raw: String) {
        amountString = raw
        recomputeConfirmEnabled()
    }

    func confirmCheckout() throws {
        // Validate amount
        guard let amount = Decimal(fromCurrencyEditing: amountString) else {
            throw ValidationError.invalidAmount
        }

        // Snapshot notes/photos
        visit.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.photoBefore = beforePhotoData
        visit.photoAfter  = afterPhotoData
        visit.endedAt = visit.endedAt ?? Date()

        // Payment (replace or create)
        let payment = visit.payment ?? Payment(amount: amount, method: selectedPaymentMethod, note: nil, externalReference: nil)
        payment.method = selectedPaymentMethod
        payment.amount = amount
        visit.payment = payment

        // Ensure total reflects items unless an explicit amount is typed
        visit.recalcTotal()

        try modelContext.save()
    }

    // MARK: - Private helpers

    private func addItem(for service: Service) {
        let item = VisitItem(visit: visit, service: service, name: service.name)
        item.unitPrice = service.defaultPrice
        item.quantity = 1
        visit.recalcTotal()
    }

    private func removeItem(for service: Service) {
        visit.items.removeAll {
            $0.service?.persistentModelID == service.persistentModelID || $0.name == service.name
        }
        visit.recalcTotal()
    }

    private func recomputeConfirmEnabled() {
        let hasServices = !selectedServiceIDs.isEmpty
        let amountValid = Decimal(fromCurrencyEditing: amountString) != nil
        isConfirmEnabled = hasServices && amountValid
    }
}

// MARK: - Formatting helpers

private extension Decimal {
    init?(fromCurrencyEditing input: String) {
        // Liberal parser: keep digits and decimal separators only
        let allowed = CharacterSet(charactersIn: "0123456789., ")
        let filtered = String(input.unicodeScalars.filter { allowed.contains($0) })
        let normalized = filtered.replacingOccurrences(of: ",", with: ".")
        self.init(string: normalized.trimmingCharacters(in: .whitespaces))
    }
}
