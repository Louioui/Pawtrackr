//
//  CheckoutViewModel.swift
//  Pawtrackr
//
//  View-model for CheckoutView: owns selection state, totals math, photos, payment,
//  and visit/payment persistence. Uses modern @Observable and CheckoutTransactionActor.
//

import SwiftUI
import SwiftData
import OSLog
import Combine

 @Observable @MainActor
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

    struct DraftRecoveryNotice: Equatable {
        let restoredAt: Date
        let missingBeforePhoto: Bool
        let missingAfterPhoto: Bool

        var hasMissingPhotos: Bool {
            missingBeforePhoto || missingAfterPhoto
        }

        var detailText: String {
            let restoredTimestamp = restoredAt.formatted(date: .abbreviated, time: .shortened)
            if missingBeforePhoto && missingAfterPhoto {
                return "Recovered your saved checkout from \(restoredTimestamp). Re-add the before and after photos to finish cleanly."
            }
            if missingBeforePhoto {
                return "Recovered your saved checkout from \(restoredTimestamp). Re-add the before photo to finish cleanly."
            }
            if missingAfterPhoto {
                return "Recovered your saved checkout from \(restoredTimestamp). Re-add the after photo to finish cleanly."
            }
            return "Recovered your saved checkout from \(restoredTimestamp)."
        }
    }

    // MARK: Dependencies
    private var visitRepository: VisitRepositoryProtocol?
    private var serviceRepository: ServiceRepositoryProtocol?
    private let draftStore: CheckoutDraftStore
    private let eventRecorder: CheckoutEventRecorder
    /// Set in `loadServices` once we have the real ModelContainer from the SwiftUI environment.
    /// Never construct a fallback container here — a phantom container would route the entire
    /// checkout to an orphan store and silently lose the groomer's revenue.
    private var transactionActor: CheckoutTransactionActor?

    // MARK: Models
    var pet: Pet
    var visit: Visit
    var currentStep: CheckoutFlowStep = .services

    // MARK: UI State
    var sessionNotes: String = ""
    var amountString: String = ""
    var selectedServiceIDs: Set<PersistentIdentifier> = [] { didSet { scheduleDraftSave(reason: "services_changed") } }
    var selectedPaymentMethod: Payment.Method = .cash { didSet { scheduleDraftSave(reason: "payment_method_changed") } }
    var selectedTipPercentage: Int? { didSet { scheduleCriticalDraftSave(reason: "tip_percentage_changed") } }
    var tipAmountString: String = "" {
        didSet {
            recalculateCachedStrings()
            scheduleCriticalDraftSave(reason: "tip_amount_changed")
        }
    }
    var beforePhotoData: Data? { didSet { scheduleDraftSave(reason: "before_photo_changed") } }
    var afterPhotoData: Data? { didSet { scheduleDraftSave(reason: "after_photo_changed") } }
    var externalReference: String = ""
    var tags: Set<String> = [] { didSet { scheduleDraftSave(reason: "tags_changed") } }
    var selectedAddOnIDs: Set<PersistentIdentifier> = [] { didSet { scheduleDraftSave(reason: "addons_changed") } }

    // MARK: State
    private(set) var isSaving: Bool = false
    private(set) var isLoadingServices: Bool = false
    private(set) var draftRecoveryNotice: DraftRecoveryNotice?
    var appError: AppError? = nil
    var state: CheckoutState = .selectingServices

    // MARK: Private State
    var allServices: [Service] = []
    var addOnServices: [Service] = []
    private let checkoutEndsAt: Date?
    private var autosaveTask: Task<Void, Never>?
    private var servicesLoadTask: Task<Void, Never>?
    private var suppressDraftAutosave = false
    private var isBootstrappingCheckout = false
    private var lastSavedDraftFingerprint: String?
    private var lastAcceptedConfirmAt: Date?
    private let confirmDebounceWindow: TimeInterval = 1.0

    // MARK: Computed State
    var requiresExternalReference: Bool {
        selectedPaymentMethod.requiresExternalReference
    }

    var referenceFieldTitle: String {
        selectedPaymentMethod.referenceFieldTitle
    }

    var referencePlaceholder: String {
        selectedPaymentMethod.referencePlaceholder
    }

    var referenceHelperText: String {
        selectedPaymentMethod.referenceHelperText
    }

    var referenceValidationMessage: String? {
        selectedPaymentMethod.validationMessage(for: externalReference)
    }

    var isConfirmEnabled: Bool {
        let hasValidAmount = servicesTotalDecimal > 0
        let hasValidReference = selectedPaymentMethod.isValidReference(externalReference)
        return hasValidAmount && !isSaving && (!requiresExternalReference || hasValidReference)
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

        // Bind to the real ModelContainer the pet/visit already lives in. Never construct
        // a fallback container — that path would route the entire checkout to an orphan
        // in-memory store and silently lose revenue. If neither object is attached to a
        // container, `loadServices(modelContext:)` will wire one up before checkout runs.
        if let container = pet.modelContext?.container ?? visit?.modelContext?.container {
            self.transactionActor = CheckoutTransactionActor(modelContainer: container)
        }
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
        self.serviceRepository = ServiceRepository(modelContainer: modelContext.container)
        if self.transactionActor == nil {
            self.transactionActor = CheckoutTransactionActor(modelContainer: modelContext.container)
        }
        isLoadingServices = true

        servicesLoadTask?.cancel()
        servicesLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let serviceRepository = self.serviceRepository else {
                    Logger.checkout.error("CheckoutViewModel: Service repository is nil")
                    self.isLoadingServices = false
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
                self.isBootstrappingCheckout = true
                self.hydrateStateFromVisit()
                await self.restoreDraftIfAvailable()
                self.isBootstrappingCheckout = false
                self.isLoadingServices = false
                Logger.checkout.info("CheckoutViewModel: Hydration complete")
            } catch {
                self.isBootstrappingCheckout = false
                self.isLoadingServices = false
                Logger.checkout.error("CheckoutViewModel: Load failed - \(error.localizedDescription)")
                self.appError = .database("Failed to load services: \(error.localizedDescription)")
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
        externalReference = selectedPaymentMethod.normalizeReference(text)
        scheduleCriticalDraftSave(reason: "reference_changed")
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
        recalculateCachedStrings()
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
        baseAmountDecimal
    }

    var servicesTotalDecimal: Decimal {
        (baseAmountDecimal + tipAmountDecimal).roundedMoney()
    }

    private var baseAmountDecimal: Decimal {
        if let manual = Formatters.parseCurrency(amountString) {
            return manual.roundedMoney()
        }
        return calculateTotalLocally()
    }

    private var tipAmountDecimal: Decimal {
        guard let tip = Formatters.parseCurrency(tipAmountString), tip > .zero else {
            return .zero
        }
        return tip.roundedMoney()
    }

    func selectTip(percentage: Int) {
        guard percentage > 0 else {
            selectedTipPercentage = nil
            tipAmountString = ""
            trace("tip_cleared")
            return
        }

        let tip = (subtotalDecimal * Decimal(percentage) / Decimal(100)).roundedMoney()
        selectedTipPercentage = percentage
        tipAmountString = tip.moneyString
        trace("tip_selected_\(percentage)")
    }

    func toggleTag(_ raw: String) {
        if tags.contains(raw) { tags.remove(raw) } else { tags.insert(raw) }
    }

    func choosePayment(_ method: Payment.Method) {
        let previousMethod = selectedPaymentMethod
        let existingReference = externalReference
        selectedPaymentMethod = method

        if !method.requiresExternalReference {
            externalReference = ""
        } else if method.preservesReference(whenSwitchingFrom: previousMethod) {
            externalReference = method.normalizeReference(existingReference)
        } else {
            externalReference = ""
        }

        trace("payment_method_selected_\(method.rawValue)")
        scheduleCriticalDraftSave(reason: "payment_method_finalized")
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
        scheduleCriticalDraftSave(reason: "step_back")
    }

    func advance() throws {
        try validate(step: currentStep)
        guard currentStep != .review else { return }
        currentStep = CheckoutFlowStep(rawValue: currentStep.rawValue + 1) ?? .review
        trace("step_advanced_to_\(currentStep.rawValue)")
        scheduleCriticalDraftSave(reason: "step_advanced")
    }

    func dismissDraftRecoveryNotice() {
        guard draftRecoveryNotice != nil else { return }
        draftRecoveryNotice = nil
        trace("draft_notice_dismissed")
    }

    func discardRecoveredDraft() async {
        guard draftRecoveryNotice != nil else { return }

        autosaveTask?.cancel()
        draftRecoveryNotice = nil
        currentStep = .services
        hydrateStateFromVisit()
        lastSavedDraftFingerprint = currentFingerprint()

        do {
            try await draftStore.deleteDraft(for: visit.uuid)
        } catch {
            Logger.checkout.error("CheckoutViewModel: Draft discard cleanup failed - \(error.localizedDescription)")
        }

        trace("draft_discarded")
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

        guard let transactionActor else {
            // Checkout was attempted before `loadServices(modelContext:)` wired up the
            // real ModelContainer. Fail loudly instead of silently writing to a phantom store.
            Logger.checkout.error("CheckoutViewModel: processPayment invoked before transactionActor was initialized")
            let appErr = AppError.database("Checkout isn't ready yet. Please reopen the screen and try again.")
            state = .failed(appErr)
            appError = appErr
            return
        }

        guard acceptConfirmAttempt() else {
            trace("confirm_pay_debounced")
            return
        }

        isSaving = true
        state = .processing
        appError = nil
        Logger.checkout.info("CheckoutViewModel: Checkout started")
        trace("confirm_pay_tapped")
        #if os(iOS)
        HapticManager.impact(.medium)
        #endif

        let request = CheckoutRequest(
            visitUUID: visit.uuid,
            petUUID: pet.uuid,
            clientUUID: pet.owner?.uuid,
            amount: servicesTotalDecimal,
            paymentMethod: selectedPaymentMethod,
            externalReference: externalReference.trimmed.isEmpty ? nil : externalReference.trimmed,
            sessionNotes: sessionNotes.trimmed.isEmpty ? nil : sessionNotes.trimmed,
            behaviorTags: Array(tags.sorted()),
            beforePhotoData: beforePhotoData,
            afterPhotoData: afterPhotoData,
            selectedServiceIDs: Array(selectedServiceIDs),
            selectedAddOnIDs: Array(selectedAddOnIDs)
        )

        do {
            let result = try await transactionActor.process(request)

            autosaveTask?.cancel()
            do {
                try await draftStore.deleteDraft(for: visit.uuid)
            } catch {
                Logger.checkout.error("CheckoutViewModel: Draft cleanup failed after checkout - \(error.localizedDescription)")
            }

            // Refresh `self.visit` in the main context.
            // Bypassing the cache ensures we get the results committed by the actor.
            let visitID = result.visitID
            let context = (pet.modelContext ?? visit.modelContext)
            
            if let mainContext = context {
                do {
                    // Ensure the main context sees the changes from the background actor.
                    try mainContext.save()

                    let descriptor = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.persistentModelID == visitID })
                    if let refreshed = try mainContext.fetch(descriptor).first {
                        self.visit = refreshed
                    } else {
                        Logger.checkout.error("CheckoutViewModel: Checkout saved but refreshed visit was not found in the main context")
                    }
                } catch {
                    Logger.checkout.error("CheckoutViewModel: Checkout saved but main-context refresh failed - \(error.localizedDescription)")
                }
            }

            state = .confirmed
            isSaving = false
            draftRecoveryNotice = nil

            // Clear photo data to free memory
            self.beforePhotoData = nil
            self.afterPhotoData = nil
            
            let completion = CheckoutCompletionContext(
                visitID: result.visitID,
                petID: result.petID,
                clientID: result.clientID,
                endedAt: result.endedAt,
                total: result.total
            )
            eventBus.publish(.checkoutCompleted(completion))

            var userInfo: [String: Any] = [
                VisitDidCompleteKey.visitID.rawValue: result.visitID,
                VisitDidCompleteKey.endedAt.rawValue: result.endedAt,
                VisitDidCompleteKey.total.rawValue: result.total
            ]
            if let petID = result.petID { userInfo[VisitDidCompleteKey.petID.rawValue] = petID }
            if let clientID = result.clientID { userInfo[VisitDidCompleteKey.clientID.rawValue] = clientID }
            
            NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: userInfo)
            
            Logger.checkout.info("CheckoutViewModel: Checkout saved successfully via Actor")
            trace("checkout_saved")
            #if os(iOS)
            HapticManager.notify(.success)
            #endif
        } catch {
            Logger.checkout.error("CheckoutViewModel: Persistence failed - \(error.localizedDescription)")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving checkout")
            let appErr = AppError.database("Persistence failed: \(error.localizedDescription)")
            state = .failed(appErr)
            appError = appErr
            isSaving = false
            trace("checkout_save_failed")
            #if os(iOS)
            HapticManager.notify(.error)
            #endif
        }
    }

    func flushDraft() {
        if state == .confirmed {
            Task { [draftStore, visitID = visit.uuid] in
                do {
                    try await draftStore.deleteDraft(for: visitID)
                } catch {
                    Logger.checkout.error("CheckoutViewModel: Confirmed draft cleanup failed - \(error.localizedDescription)")
                }
            }
            return
        }
        scheduleDraftSave(reason: "view_disappeared", immediate: true)
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
            if let message = selectedPaymentMethod.validationMessage(for: externalReference) {
                throw ValidationError.custom(message: message)
            }
        }
    }

    private func restoreDraftIfAvailable() async {
        guard !visit.isCompleted else { return }
        guard let draft = await draftStore.loadDraft(for: visit.uuid), draft.petID == pet.uuid else { return }

        suppressDraftAutosave = true
        sessionNotes = draft.sessionNotes
        amountString = draft.amountString
        tipAmountString = draft.tipAmountString
        selectedTipPercentage = draft.selectedTipPercentage
        externalReference = draft.externalReference
        tags = Set(draft.tags)
        
        if let method = Payment.Method(rawValue: draft.selectedPaymentMethodRawValue) {
            selectedPaymentMethod = method
        }

        let mainIDs = Set(allServices.filter { draft.selectedServiceUUIDs.contains($0.uuid) }.map(\.persistentModelID))
        let addOnIDs = Set(addOnServices.filter { draft.selectedAddOnUUIDs.contains($0.uuid) }.map(\.persistentModelID))
        selectedServiceIDs = mainIDs
        selectedAddOnIDs = addOnIDs
        if let restoredStep = CheckoutFlowStep(rawValue: draft.currentStepRawValue) {
            currentStep = restoredStep
        } else {
            // Don't silently regress to step 1 — that confuses the user when their
            // selections look filled in but the wizard rewinds. Log loudly, leave
            // the user where they were (default `currentStep` from init).
            Logger.checkout.error("Draft restore: unknown step rawValue=\(draft.currentStepRawValue, privacy: .public). Keeping current step.")
        }
        recalculateCachedStrings()
        lastSavedDraftFingerprint = currentFingerprint()
        draftRecoveryNotice = DraftRecoveryNotice(
            restoredAt: draft.updatedAt,
            missingBeforePhoto: draft.hadBeforePhoto && beforePhotoData == nil,
            missingAfterPhoto: draft.hadAfterPhoto && afterPhotoData == nil
        )
        suppressDraftAutosave = false
        trace("draft_restored")
    }

    // MARK: - Draft Fingerprint

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
            tipAmountString,
            String(selectedTipPercentage ?? 0),
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

    private func scheduleCriticalDraftSave(reason: String) {
        scheduleDraftSave(reason: reason, immediate: true)
    }

    private func scheduleDraftSave(reason: String, immediate: Bool = false) {
        guard !suppressDraftAutosave, !isBootstrappingCheckout, state != .confirmed, !visit.isCompleted else { return }

        let fingerprint = currentFingerprint()
        if fingerprint == lastSavedDraftFingerprint { return }

        autosaveTask?.cancel()

        let draft = makeDraft()

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

    private func acceptConfirmAttempt(now: Date = .now) -> Bool {
        if let lastAcceptedConfirmAt,
           now.timeIntervalSince(lastAcceptedConfirmAt) < confirmDebounceWindow {
            return false
        }
        lastAcceptedConfirmAt = now
        return true
    }

    private func makeDraft() -> CheckoutDraft {
        // Keep the autosave payload small and atomic. We only persist whether
        // photos existed so restore can warn the groomer to re-pick them after
        // an interruption without inflating the draft file with image blobs.
        CheckoutDraft(
            visitID: visit.uuid,
            petID: pet.uuid,
            updatedAt: .now,
            currentStepRawValue: currentStep.rawValue,
            sessionNotes: sessionNotes,
            amountString: amountString,
            tipAmountString: tipAmountString,
            selectedTipPercentage: selectedTipPercentage,
            selectedServiceUUIDs: allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }.map(\.uuid),
            selectedAddOnUUIDs: addOnServices.filter { selectedAddOnIDs.contains($0.persistentModelID) }.map(\.uuid),
            selectedPaymentMethodRawValue: selectedPaymentMethod.rawValue,
            beforePhotoData: nil,
            afterPhotoData: nil,
            hadBeforePhoto: beforePhotoData != nil,
            hadAfterPhoto: afterPhotoData != nil,
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
