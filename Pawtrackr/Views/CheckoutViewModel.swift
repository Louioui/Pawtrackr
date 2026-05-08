//
//  CheckoutViewModel.swift
//  Pawtrackr
//
//  View-model for CheckoutView: owns selection state, totals math, photos, payment,
//  and visit/payment persistence. Uses modern @Observable.
//

import SwiftUI
import SwiftData
import OSLog

@Observable
@MainActor
final class CheckoutViewModel {
    enum CheckoutFlowStep: Int, CaseIterable {
        case services = 0
        case details = 1
        case payment = 2
        case review = 3

        var title: String {
            switch self {
            case .services: return "Services"
            case .details: return "Notes & Photos"
            case .payment: return "Payment"
            case .review: return "Review"
            }
        }

        var primaryButtonTitle: String {
            switch self {
            case .services: return "Continue to Notes"
            case .details: return "Continue to Payment"
            case .payment: return "Review Checkout"
            case .review: return "Confirm & Pay"
            }
        }
    }

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
    private let draftStore: CheckoutDraftStore
    private let eventRecorder: CheckoutEventRecorder

    // MARK: Models
    var pet: Pet
    var visit: Visit
    var currentStep: CheckoutFlowStep = .services

    // MARK: UI State
    var sessionNotes: String = ""
    var amountString: String = ""
    var selectedServiceIDs: Set<PersistentIdentifier> = [] { didSet { scheduleDraftSave(reason: "services_changed") } }
    var selectedPaymentMethod: Payment.Method = .cash { didSet { scheduleDraftSave(reason: "payment_method_changed") } }
    var beforePhotoData: Data? { didSet { scheduleDraftSave(reason: "before_photo_changed") } }
    var afterPhotoData: Data? { didSet { scheduleDraftSave(reason: "after_photo_changed") } }
    var externalReference: String = ""
    var tags: Set<String> = [] { didSet { scheduleDraftSave(reason: "tags_changed") } }
    var selectedAddOnIDs: Set<PersistentIdentifier> = [] { didSet { scheduleDraftSave(reason: "addons_changed") } }

    // MARK: State
    private(set) var isSaving: Bool = false
    private(set) var isLoadingServices: Bool = false
    var appError: AppError? = nil
    var state: CheckoutState = .selectingServices

    // MARK: Private State
    var allServices: [Service] = []
    var addOnServices: [Service] = []
    private let checkoutEndsAt: Date?
    private var autosaveTask: Task<Void, Never>?
    private var suppressDraftAutosave = false
    private var lastSavedDraftFingerprint: String?

    private struct PersistedCheckout {
        let endedAt: Date
        let completion: CheckoutCompletionContext
        let container: ModelContainer
    }

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
    var hasSelectedServices: Bool { !selectedServiceIDs.isEmpty || !selectedAddOnIDs.isEmpty }
    var beforePhotoCount: Int { beforePhotoData == nil ? 0 : 1 }
    var afterPhotoCount: Int { afterPhotoData == nil ? 0 : 1 }
    var totalPhotoCount: Int { beforePhotoCount + afterPhotoCount }
    var paymentMethodLabel: String { selectedPaymentMethod.displayName }
    var paymentReferenceSummary: String {
        let reference = externalReference.trimmed
        return reference.isEmpty ? "None" : reference
    }
    var notesPreview: String {
        let trimmed = sessionNotes.trimmed
        return trimmed.isEmpty ? "No notes added" : trimmed
    }
    var behaviorTagsSummary: String {
        let values = tags.sorted()
        return values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    // MARK: - Cached Computed Properties
    private(set) var selectedServicesSummary: String = "None"
    private(set) var finalTotalString: String = "$0.00"

    private let eventBus: GlobalEventBus

    init(
        pet: Pet,
        visit: Visit?,
        draftStore: CheckoutDraftStore = .shared,
        eventRecorder: CheckoutEventRecorder = .shared,
        eventBus: GlobalEventBus = GlobalEventBus()
    ) {
        self.pet = pet
        self.visit = visit ?? Visit(pet: pet)
        self.checkoutEndsAt = Date()
        self.draftStore = draftStore
        self.eventRecorder = eventRecorder
        self.eventBus = eventBus
    }

    convenience init(pet: Pet) {
        self.init(pet: pet, visit: nil, eventBus: GlobalEventBus())
    }

    private static let serviceOrder: [String] = [
        "Full Package", "Basic Package", "Spa Package", "Bath", "Haircut"
    ]

    @MainActor
    func loadServices(modelContext: ModelContext) {
        Logger.checkout.info("CheckoutViewModel: Loading services")
        self.visitRepository = VisitRepository(modelContainer: modelContext.container, eventBus: eventBus)
        self.serviceRepository = ServiceRepository(modelContainer: modelContext.container)
        isLoadingServices = true

        Task {
            do {
                guard let serviceRepository = serviceRepository else {
                    Logger.checkout.error("CheckoutViewModel: Service repository is nil")
                    isLoadingServices = false
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
                await restoreDraftIfAvailable()
                isLoadingServices = false
                Logger.checkout.info("CheckoutViewModel: Hydration complete")
            } catch {
                isLoadingServices = false
                Logger.checkout.error("CheckoutViewModel: Load failed - \(error.localizedDescription)")
                appError = .database("Failed to load services: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func hydrateStateFromVisit() {
        Logger.checkout.info("CheckoutViewModel: Hydrating from visit \(self.visit.uuid)")
        suppressDraftAutosave = true
        sessionNotes = visit.note?.trimmed ?? ""

        if visit.behaviorTags.isEmpty {
            tags = Set(pet.behaviorTags)
        } else {
            tags = Set(visit.behaviorTags)
        }

        beforePhotoData = visit.beforePhotoData
        afterPhotoData  = visit.afterPhotoData

        let allIDs = Set((visit.items ?? []).compactMap { $0.service?.persistentModelID })
        selectedServiceIDs = allIDs.filter { id in allServices.contains(where: { $0.persistentModelID == id }) }
        selectedAddOnIDs = allIDs.filter { id in addOnServices.contains(where: { $0.persistentModelID == id }) }

        if visit.isCompleted && visit.total > 0 {
            amountString = visit.total.moneyString
        } else {
            updateAmountString()
        }

        recalculateCachedStrings()
        suppressDraftAutosave = false
        trace("hydrated_from_visit")
    }

    func setAmountDirectly(_ text: String) {
        amountString = text
        recalculateCachedStrings()
        scheduleDraftSave(reason: "amount_changed")
    }

    func setSessionNotes(_ text: String) {
        sessionNotes = text
        scheduleDraftSave(reason: "session_notes_changed")
    }

    func setExternalReference(_ text: String) {
        externalReference = text
        scheduleDraftSave(reason: "reference_changed")
    }

    func isServiceSelected(_ service: Service) -> Bool {
        selectedServiceIDs.contains(service.persistentModelID)
    }

    func isAddOnSelected(_ service: Service) -> Bool {
        selectedAddOnIDs.contains(service.persistentModelID)
    }

    func updateVisitItems() {
        updateAmountString()
        recalculateCachedStrings()
    }

    private func updateAmountString() {
        let total = calculateTotalLocally()
        amountString = total.moneyString
    }

    private func calculateTotalLocally() -> Decimal {
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
        trace("service_toggled_\(service.name)")
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
        trace("addon_toggled_\(service.name)")
    }

    func removeVisitItem(_ item: VisitItem) {
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

    func toggleTag(_ raw: String) {
        if tags.contains(raw) { tags.remove(raw) } else { tags.insert(raw) }
    }

    func choosePayment(_ method: Payment.Method) {
        selectedPaymentMethod = method
        if !method.requiresExternalReference { externalReference = "" }
        trace("payment_method_selected_\(method.rawValue)")
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
        scheduleDraftSave(reason: "amount_formatted")
    }

    private func recalculateCachedStrings() {
        finalTotalString = servicesTotalDecimal.moneyString

        let allSelected = selectedServiceIDs.union(selectedAddOnIDs)
        let sortedNames = (allServices + addOnServices)
            .filter { allSelected.contains($0.persistentModelID) }
            .map(\.name)
            .sorted()

        selectedServicesSummary = sortedNames.isEmpty ? "None" : sortedNames.joined(separator: ", ")
    }

    var isAdvanceEnabled: Bool {
        switch currentStep {
        case .services:
            return hasSelectedServices
        case .details:
            return true
        case .payment:
            return isConfirmEnabled
        case .review:
            return isConfirmEnabled && !isSaving
        }
    }

    func goBack() {
        guard currentStep.rawValue > CheckoutFlowStep.services.rawValue else { return }
        currentStep = CheckoutFlowStep(rawValue: currentStep.rawValue - 1) ?? .services
        trace("step_back_to_\(currentStep.rawValue)")
    }

    func advance() throws {
        try validate(step: currentStep)
        guard currentStep != .review else { return }
        currentStep = CheckoutFlowStep(rawValue: currentStep.rawValue + 1) ?? .review
        trace("step_advanced_to_\(currentStep.rawValue)")
        scheduleDraftSave(reason: "step_advanced")
    }

    @MainActor
    func processPayment() async {
        guard !isSaving, state != .confirmed else { return }
        guard currentStep == .review else {
            self.appError = .validation(.custom(message: "Review checkout before confirming payment."))
            return
        }

        do {
            try validate(step: .review)
        } catch {
            self.appError = .validation(error as? ValidationError ?? .custom(message: error.localizedDescription))
            return
        }

        isSaving = true
        state = .processing
        appError = nil
        Logger.checkout.info("CheckoutViewModel: Checkout started")
        trace("confirm_pay_tapped")

        // Capture photo data on main actor before going to background.
        let rawBefore = self.beforePhotoData
        let rawAfter = self.afterPhotoData

        // Process all four image variants (full + thumb × before + after) in parallel
        // on a background thread so the main thread stays free during checkout.
        let (pBefore, pBeforeThumb, pAfter, pAfterThumb) = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?, Data?, Data?) in
            let b = rawBefore.flatMap { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            let bt = rawBefore.flatMap { ImageCache.shared.downsampleToData(data: $0, maxDimension: 200) }
            let a = rawAfter.flatMap  { ImageCache.shared.downsampleToData(data: $0, maxDimension: 1024) }
            let at = rawAfter.flatMap  { ImageCache.shared.downsampleToData(data: $0, maxDimension: 200) }
            return (b, bt, a, at)
        }.value

        do {
            let persisted = try persistCheckout(
                processedBefore: pBefore, processedBeforeThumb: pBeforeThumb,
                processedAfter: pAfter, processedAfterThumb: pAfterThumb
            )
            await rebuildCheckoutSummaries(for: persisted.endedAt, container: persisted.container)
            autosaveTask?.cancel()
            try? await draftStore.deleteDraft(for: visit.uuid)
            state = .confirmed
            isSaving = false
            // Release multi-MB photo Data now that it's persisted to the Visit model
            // (and to disk via @Attribute(.externalStorage)). The didSet hook on these
            // properties tries to schedule a draft save, but scheduleDraftSave bails
            // when state == .confirmed, so this is safe.
            self.beforePhotoData = nil
            self.afterPhotoData = nil
            eventBus.publish(.checkoutCompleted(persisted.completion))

            var userInfo: [String: Any] = [
                VisitDidCompleteKey.visitID.rawValue: persisted.completion.visitID,
                VisitDidCompleteKey.endedAt.rawValue: persisted.endedAt,
                VisitDidCompleteKey.total.rawValue: persisted.completion.total
            ]
            if let petID = persisted.completion.petID {
                userInfo[VisitDidCompleteKey.petID.rawValue] = petID
            }
            if let clientID = persisted.completion.clientID {
                userInfo[VisitDidCompleteKey.clientID.rawValue] = clientID
            }
            NotificationCenter.default.post(name: .visitDidComplete, object: visit, userInfo: userInfo)
            Logger.checkout.info("CheckoutViewModel: Checkout saved successfully")
            trace("checkout_saved")
        } catch {
            Logger.checkout.error("CheckoutViewModel: Persistence failed - \(error.localizedDescription)")
            let appErr = AppError.database("Persistence failed: \(error.localizedDescription)")
            state = .failed(appErr)
            appError = appErr
            isSaving = false
            trace("checkout_save_failed")
        }
    }

    func flushDraft() {
        if state == .confirmed {
            Task { try? await draftStore.deleteDraft(for: visit.uuid) }
            return
        }
        scheduleDraftSave(reason: "view_disappeared", immediate: true)
    }

    private func persistCheckout(
        processedBefore: Data?,
        processedBeforeThumb: Data?,
        processedAfter: Data?,
        processedAfterThumb: Data?
    ) throws -> PersistedCheckout {
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
        reconcileLineItemPrices(to: total)

        visit.note = notes
        visit.behaviorTags = sortedTags
        pet.setBehaviorTags(sortedTags)
        visit.applyPhotos(
            before: processedBefore, beforeThumb: processedBeforeThumb,
            after: processedAfter, afterThumb: processedAfterThumb
        )

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
        let completion = CheckoutCompletionContext(
            visitID: visit.persistentModelID,
            petID: pet.persistentModelID,
            clientID: pet.owner?.persistentModelID,
            endedAt: endedAt,
            total: total
        )
        return PersistedCheckout(endedAt: endedAt, completion: completion, container: context.container)
    }

    private func syncVisitItems(in context: ModelContext) {
        let selectedIDs = selectedServiceIDs.union(selectedAddOnIDs)

        var existingItemsByServiceID: [PersistentIdentifier: VisitItem] = [:]
        for item in visit.items ?? [] {
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
                let item = VisitItem.from(service: service, visit: visit)
                context.insert(item)
                var currentItems = visit.items ?? []
                currentItems.append(item)
                visit.items = currentItems
            }
        }
    }

    private func reconcileLineItemPrices(to finalTotal: Decimal) {
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

    private func rebuildCheckoutSummaries(for endedAt: Date, container: ModelContainer) async {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            SummaryUpdater.rebuildDay(for: endedAt, in: context)
        }.value
    }

    private func validate(step: CheckoutFlowStep) throws {
        switch step {
        case .services:
            guard hasSelectedServices else {
                throw ValidationError.custom(message: "Select at least one service before continuing.")
            }
        case .details:
            break
        case .payment, .review:
            let total = servicesTotalDecimal
            guard total > 0 else {
                throw ValidationError.custom(message: "Cannot check out with a total amount of zero.")
            }
            if requiresExternalReference && externalReference.trimmed.isEmpty {
                throw ValidationError.custom(message: "A reference is required for this payment method.")
            }
        }
    }

    private func restoreDraftIfAvailable() async {
        guard !visit.isCompleted else { return }
        guard let draft = await draftStore.loadDraft(for: visit.uuid), draft.petID == pet.uuid else { return }

        suppressDraftAutosave = true
        sessionNotes = draft.sessionNotes
        amountString = draft.amountString
        externalReference = draft.externalReference
        tags = Set(draft.tags)
        // Photos are intentionally not restored from draft (see makeDraft).
        // beforePhotoData / afterPhotoData come from hydrateStateFromVisit only.

        if let method = Payment.Method(rawValue: draft.selectedPaymentMethodRawValue) {
            selectedPaymentMethod = method
        }

        let mainIDs = Set(allServices.filter { draft.selectedServiceUUIDs.contains($0.uuid) }.map(\.persistentModelID))
        let addOnIDs = Set(addOnServices.filter { draft.selectedAddOnUUIDs.contains($0.uuid) }.map(\.persistentModelID))
        selectedServiceIDs = mainIDs
        selectedAddOnIDs = addOnIDs
        currentStep = CheckoutFlowStep(rawValue: draft.currentStepRawValue) ?? .services
        recalculateCachedStrings()
        lastSavedDraftFingerprint = currentFingerprint()
        suppressDraftAutosave = false
        trace("draft_restored")
    }

    // MARK: - Draft Fingerprint

    /// Fingerprint of mutable checkout state used to skip redundant draft saves.
    private func currentFingerprint() -> String {
        let serviceUUIDs = allServices
            .filter { selectedServiceIDs.contains($0.persistentModelID) }
            .map(\.uuid.uuidString).sorted().joined(separator: "|")
        let addOnUUIDs = addOnServices
            .filter { selectedAddOnIDs.contains($0.persistentModelID) }
            .map(\.uuid.uuidString).sorted().joined(separator: "|")
        let tagList = tags.sorted().joined(separator: "|")
        let parts: [String] = [
            visit.uuid.uuidString,
            pet.uuid.uuidString,
            String(currentStep.rawValue),
            sessionNotes,
            amountString,
            serviceUUIDs,
            addOnUUIDs,
            selectedPaymentMethod.rawValue,
            externalReference,
            tagList,
            String(beforePhotoData?.count ?? 0),
            String(afterPhotoData?.count ?? 0)
        ]
        return parts.joined(separator: "||")
    }

    private func scheduleDraftSave(reason: String, immediate: Bool = false) {
        guard !suppressDraftAutosave, state != .confirmed, !visit.isCompleted else { return }

        let fingerprint = currentFingerprint()
        if fingerprint == lastSavedDraftFingerprint { return }

        autosaveTask?.cancel()

        let draft = makeDraft()

        // Capture only the values we need so the autosave task can outlive
        // the view-model's view without retaining `self`. The fingerprint write
        // hops onto MainActor with a fresh weak self capture and bails if the
        // VM is gone.
        autosaveTask = Task { [draft, fingerprint, draftStore, eventRecorder, visitID = visit.uuid, petName = pet.name, weak self] in
            if !immediate {
                do {
                    try await Task.sleep(for: .milliseconds(450))
                } catch {
                    return
                }
            }
            if Task.isCancelled { return }
            do {
                try await draftStore.saveDraft(draft)
                await MainActor.run { [weak self] in
                    self?.lastSavedDraftFingerprint = fingerprint
                }
                await eventRecorder.record("draft_saved:\(reason)", visitID: visitID, petName: petName)
            } catch {
                Logger.checkout.error("Checkout draft save failed - \(error.localizedDescription)")
            }
        }
    }

    // No deinit needed: the autosave task captures `draft`, `draftStore`,
    // `eventRecorder` strongly and uses `[weak self]` for the fingerprint write.
    // If the VM deallocates mid-flight, the draft still persists (the user's data
    // is saved) and the MainActor write is a no-op against a nil self. New
    // schedule calls cancel the previous task explicitly, so leaks are bounded
    // to a single in-flight save.

    /// Builds a lightweight draft. Photos are intentionally excluded:
    /// - Full-res photos can be several MB, making draft JSON huge and writes slow.
    /// - Photos are restored from the Visit model on re-open (hydrateStateFromVisit),
    ///   so they don't need to live in the draft for the common session-recovery case.
    private func makeDraft() -> CheckoutDraft {
        CheckoutDraft(
            visitID: visit.uuid,
            petID: pet.uuid,
            updatedAt: .now,
            currentStepRawValue: currentStep.rawValue,
            sessionNotes: sessionNotes,
            amountString: amountString,
            selectedServiceUUIDs: allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }.map(\.uuid),
            selectedAddOnUUIDs: addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }.map(\.uuid),
            selectedPaymentMethodRawValue: selectedPaymentMethod.rawValue,
            beforePhotoData: nil,
            afterPhotoData: nil,
            externalReference: externalReference,
            tags: Array(tags.sorted())
        )
    }

    private func trace(_ event: String) {
        let visitID = visit.uuid
        let petName = pet.name
        Task { [eventRecorder] in
            await eventRecorder.record(event, visitID: visitID, petName: petName)
        }
    }
}

private extension Logger {
    static let checkout = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Checkout")
}
