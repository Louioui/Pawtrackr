//
//  CheckoutView.swift
//  Pawtrackr
//

import SwiftUI
import SwiftData
import CoreTransferable

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GlobalEventBus.self) private var eventBus
    @State private var viewModel: CheckoutViewModel
    @State private var receiptPDFData: Data?
    @State private var receiptFailed = false
    @State private var isGoingBack = false
    @State private var notesEditorText: String = ""
    @State private var amountEditorText: String = ""
    @State private var referenceEditorText: String = ""
    @State private var notesSyncTask: Task<Void, Never>?
    @State private var amountSyncTask: Task<Void, Never>?
    @State private var referenceSyncTask: Task<Void, Never>?
    @State private var didLoadViewModel = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case sessionNotes
        case amount
        case externalReference
    }

    init(pet: Pet, visit: Visit? = nil) {
        _viewModel = State(initialValue: CheckoutViewModel(pet: pet, visit: visit, eventBus: GlobalEventBus()))
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeInOut(duration: 0.22), value: viewModel.currentStep)

            bottomBar
        }
        .background(DS.ColorToken.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .navigationTitle(viewModel.currentStep.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    if focusedField == .amount {
                        commitAmountInput()
                    }
                    focusedField = nil
                }
            }
        }
        #endif
        .alert(item: $viewModel.appError) { error in
            Alert(title: Text("Error"), message: Text(error.localizedDescription), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            guard !didLoadViewModel else { return }
            didLoadViewModel = true
            viewModel = CheckoutViewModel(pet: viewModel.pet, visit: viewModel.visit, eventBus: eventBus)
            viewModel.loadServices(modelContext: modelContext)
            notesEditorText = viewModel.sessionNotes
            amountEditorText = viewModel.amountString
            referenceEditorText = viewModel.externalReference
        }
        .onDisappear {
            notesSyncTask?.cancel()
            amountSyncTask?.cancel()
            referenceSyncTask?.cancel()
            viewModel.flushDraft()
        }
        .onChange(of: viewModel.sessionNotes) { _, newValue in
            if focusedField != .sessionNotes && notesEditorText != newValue {
                notesEditorText = newValue
            }
        }
        .onChange(of: viewModel.amountString) { _, newValue in
            if focusedField != .amount && amountEditorText != newValue {
                amountEditorText = newValue
            }
        }
        .onChange(of: viewModel.externalReference) { _, newValue in
            if focusedField != .externalReference && referenceEditorText != newValue {
                referenceEditorText = newValue
            }
        }
        .overlay {
            if shouldShowOverlay {
                overlayContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShowOverlay)
        #if os(macOS)
        .onChange(of: viewModel.currentStep) { _, newStep in
            guard !isGoingBack else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                switch newStep {
                case .payment: focusedField = .amount
                case .details: focusedField = .sessionNotes
                default: break
                }
            }
        }
        #endif
    }

    // MARK: - Overlay condition

    private var shouldShowOverlay: Bool {
        viewModel.isSaving || viewModel.state == .confirmed
    }

    // MARK: - Platform Adapters

    private var primaryButtonHeight: CGFloat {
        #if os(macOS)
        return 38
        #else
        return 50
        #endif
    }

    private var paymentGridColumns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 120, maximum: 160))]
        #else
        return [GridItem(.flexible()), GridItem(.flexible())]
        #endif
    }

    // MARK: - Steps

    private var stepTransition: AnyTransition {
        .opacity
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .services:  servicesStep.transition(stepTransition)
        case .details:   detailsStep.transition(stepTransition)
        case .payment:   paymentStep.transition(stepTransition)
        case .review:    reviewStep.transition(stepTransition)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(CheckoutViewModel.CheckoutFlowStep.allCases, id: \.self) { step in
                let isActive = viewModel.currentStep.rawValue >= step.rawValue
                VStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: isActive ? 12 : 10, height: isActive ? 12 : 10)
                    Text(step.title)
                        .font(Font.caption2.weight(isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.currentStep)

                if step != .review {
                    Rectangle()
                        .fill(viewModel.currentStep.rawValue > step.rawValue ? Color.blue : Color.gray.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: -12)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
                }
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 32)
    }

    private var servicesStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                stepHero(
                    eyebrow: "Step 1",
                    title: "Pick the services",
                    message: "Choose the main service and any add-ons before you move to notes and photos."
                )

                if viewModel.isLoadingServices {
                    ProgressView("Loading services…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Main Services").font(.headline).padding(.horizontal)
                        Card {
                            if viewModel.allServices.isEmpty {
                                Text("No services found. Add services in Settings.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            } else {
                                FlowLayout(spacing: 10, rowSpacing: 10) {
                                    ForEach(viewModel.allServices) { service in
                                        serviceTag(for: service)
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.addOnServices.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add-ons").font(.headline).padding(.horizontal)
                            VStack(spacing: 10) {
                                ForEach(viewModel.addOnServices) { service in
                                    addOnRow(service)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHero(
                    eyebrow: "Step 2",
                    title: "Add notes and photos",
                    message: "Capture behavior, grooming notes, and before/after photos without leaving checkout."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior & Notes").font(.headline).padding(.horizontal)
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            FlowLayout(spacing: 10, rowSpacing: 10) {
                                ForEach(CheckoutViewModel.tagOptions, id: \.self) { tag in
                                    behaviorTag(for: tag)
                                }
                            }
                            
                            TextEditor(text: $notesEditorText)
                                #if os(iOS)
                                .scrollContentBackground(.hidden)
                                #endif
                                .focused($focusedField, equals: .sessionNotes)
                                .accessibilityIdentifier("checkout.notesEditor")
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                                .onChange(of: notesEditorText) { _, newValue in
                                    notesSyncTask?.cancel()
                                    notesSyncTask = Task { @MainActor in
                                        do {
                                            try await Task.sleep(for: .milliseconds(400))
                                        } catch {
                                            return
                                        }
                                        viewModel.setSessionNotes(newValue)
                                    }
                                }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Photos").font(.headline).padding(.horizontal)
                    Card {
                        photoLayout
                    }
                }
            }
            .padding(.vertical)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private var photoLayout: some View {
        #if os(iOS)
        VStack(spacing: 16) {
            PhotoWell(imageData: $viewModel.beforePhotoData, title: "Before")
            PhotoWell(imageData: $viewModel.afterPhotoData, title: "After")
        }
        #else
        HStack(spacing: 20) {
            PhotoWell(imageData: $viewModel.beforePhotoData, title: "Before")
            PhotoWell(imageData: $viewModel.afterPhotoData, title: "After")
        }
        #endif
    }

    private var paymentStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHero(
                    eyebrow: "Step 3",
                    title: "Confirm payment",
                    message: "Set the total and payment method before the final review."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Final Amount").font(.headline).padding(.horizontal)
                    Card {
                        TextField("$0.00", text: amountBinding)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .focused($focusedField, equals: .amount)
                            .accessibilityIdentifier("checkout.amountField")
                            .font(Font.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(TextAlignment.center)
                            .foregroundStyle(Color.blue)
                            .onSubmit {
                                commitAmountInput()
                                #if os(macOS)
                                focusedField = nil
                                if viewModel.isAdvanceEnabled { advance() }
                                #endif
                            }

                        Text("Auto-filled from selected services. You can adjust the total before charging the client.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Payment Method").font(.headline).padding(.horizontal)
                    LazyVGrid(columns: paymentGridColumns, spacing: 12) {
                        ForEach(Self.paymentOptions) { option in
                            paymentCard(for: option)
                        }
                    }
                    .padding(.horizontal)
                }

                if viewModel.requiresExternalReference {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference Info").font(Font.subheadline.weight(.medium)).padding(.horizontal)
                        TextField(viewModel.referencePlaceholder, text: $referenceEditorText)
                            .focused($focusedField, equals: .externalReference)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                            .onChange(of: referenceEditorText) { _, newValue in
                                referenceSyncTask?.cancel()
                                referenceSyncTask = Task { @MainActor in
                                    do {
                                        try await Task.sleep(for: .milliseconds(250))
                                    } catch {
                                        return
                                    }
                                    viewModel.setExternalReference(newValue)
                                }
                            }
                            #if os(macOS)
                            .onSubmit {
                                referenceSyncTask?.cancel()
                                viewModel.setExternalReference(referenceEditorText)
                                if viewModel.isAdvanceEnabled { advance() }
                            }
                            #endif
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary").font(.headline).padding(.horizontal)
                    Card {
                        VStack(spacing: 10) {
                            summaryRow(title: "Pet", value: viewModel.pet.name)
                            summaryRow(title: "Duration", value: viewModel.sessionDurationString)
                            summaryRow(title: "Services", value: selectedServicesSummary)
                            Divider()
                            summaryRow(title: "Total", value: viewModel.finalTotalString, isTotal: true)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepHero(
                    eyebrow: "Step 4",
                    title: "Review everything",
                    message: "Confirm exactly what will be saved to history and insights."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Visit Summary").font(.headline).padding(.horizontal)
                    Card {
                        VStack(spacing: 10) {
                            summaryRow(title: "Pet", value: viewModel.pet.name)
                            summaryRow(title: "Duration", value: viewModel.sessionDurationString)
                            summaryRow(title: "Services", value: selectedServicesSummary)
                            summaryRow(title: "Behavior Tags", value: viewModel.behaviorTagsSummary)
                            summaryRow(title: "Notes", value: viewModel.notesPreview)
                            summaryRow(title: "Photos", value: "\(viewModel.totalPhotoCount)")
                            Divider()
                            summaryRow(title: "Total", value: viewModel.finalTotalString, isTotal: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Payment Review").font(.headline).padding(.horizontal)
                    Card {
                        VStack(spacing: 10) {
                            summaryRow(title: "Method", value: viewModel.paymentMethodLabel)
                            summaryRow(title: "Reference", value: viewModel.paymentReferenceSummary)
                            summaryRow(
                                title: "History Save",
                                value: viewModel.totalPhotoCount > 0
                                    ? "Visit, \(viewModel.totalPhotoCount) photo\(viewModel.totalPhotoCount == 1 ? "" : "s"), services, notes, payment"
                                    : "Visit, services, notes, payment"
                            )
                            summaryRow(title: "Insights Save", value: "\(viewModel.finalTotalString) tracked as revenue")
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Components

    private var headerCard: some View {
        Card {
            HStack(spacing: 16) {
                AvatarView(.pet(species: viewModel.pet.species, gender: viewModel.pet.gender, name: viewModel.pet.name, imageData: viewModel.pet.photoData), size: .md)
                VStack(alignment: .leading) {
                    Text(viewModel.pet.name).font(.headline)
                    Text(viewModel.pet.owner?.fullName ?? "Unknown Owner").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Started").font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.visit.startedAt, style: .time).font(Font.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if viewModel.currentStep != .services {
                    Button {
                        isGoingBack = true
                        viewModel.goBack()
                    } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .frame(width: primaryButtonHeight, height: primaryButtonHeight)
                                .background(Circle().fill(Color.gray.opacity(0.1)))
                        }
                        .accessibilityIdentifier("checkout.backButton")
                    }
                
                Button {
                    advance()
                } label: {
                    Text(viewModel.currentStep.primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: primaryButtonHeight)
                        .background(RoundedRectangle(cornerRadius: 15).fill(viewModel.isAdvanceEnabled ? Color.blue : Color.gray.opacity(0.3)))
                        .foregroundStyle(.white)
                        .scaleEffect(viewModel.isAdvanceEnabled ? 1.0 : 0.97)
                }
                .disabled(!viewModel.isAdvanceEnabled)
                .accessibilityIdentifier("checkout.primaryButton")
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isAdvanceEnabled)
                #if os(macOS)
                .keyboardShortcut(.return)
                #endif
            }
            .padding()
            .background(DS.ColorToken.background)
        }
    }

    private func advance() {
        isGoingBack = false
        if viewModel.currentStep == .review {
            confirmCheckout()
            return
        }

        flushPendingEditors()
        focusedField = nil

        Task { @MainActor in
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif

            #if os(iOS)
            try? await Task.sleep(for: .milliseconds(120))
            #endif
            do {
                try viewModel.advance()
            } catch {
                viewModel.appError = .validation(error as? ValidationError ?? .custom(message: error.localizedDescription))
            }
        }
    }

    private func confirmCheckout() {
        flushPendingEditors()
        focusedField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        Task {
            await viewModel.processPayment()
        }
    }

    private func flushPendingEditors() {
        notesSyncTask?.cancel()
        amountSyncTask?.cancel()
        referenceSyncTask?.cancel()

        switch viewModel.currentStep {
        case .details:
            viewModel.setSessionNotes(notesEditorText)
        case .payment, .review:
            viewModel.setSessionNotes(notesEditorText)
            viewModel.setAmountDirectly(amountEditorText)
            viewModel.setExternalReference(referenceEditorText)
        case .services:
            break
        }
    }

    private func commitAmountInput() {
        amountSyncTask?.cancel()
        viewModel.setAmountDirectly(amountEditorText)
        viewModel.formatAmountInput()
        amountEditorText = viewModel.amountString
    }

    private func stepHero(eyebrow: String, title: String, message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue)
                Text(title)
                    .font(.title3.weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private var overlayContent: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                if viewModel.state == .confirmed {
                    confirmedContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                            removal: .opacity
                        ))
                } else {
                    processingContent
                        .transition(.opacity)
                }
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 25).fill(DS.ColorToken.surface))
            .shadow(radius: 20)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.state == .confirmed)
        }
        .onChange(of: viewModel.state) { _, newValue in
            if newValue == .confirmed {
                #if os(iOS)
                HapticManager.notify(.success)
                #endif
                let receiptSnapshot = PDFReceiptService.shared.makeSnapshot(for: viewModel.visit)
                Task {
                    let data: Data? = await withTaskGroup(of: Data?.self) { group in
                        group.addTask {
                            await Task.detached(priority: .userInitiated) {
                                PDFReceiptService.render(snapshot: receiptSnapshot)
                            }.value
                        }
                        group.addTask {
                            try? await Task.sleep(for: .seconds(10))
                            return nil
                        }
                        let result = await group.next() ?? nil
                        group.cancelAll()
                        return result
                    }
                    if let data {
                        receiptPDFData = data
                    } else {
                        receiptFailed = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var confirmedContent: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.green)
        Text(NSLocalizedString("checkout.complete_title", comment: "")).font(Font.title3.weight(.bold))
        Text(viewModel.finalTotalString).font(Font.title.bold())

        if let pdfData = receiptPDFData {
            ShareLink(
                item: ReceiptDocument(
                    pdfData: pdfData,
                    filename: "Receipt_\(viewModel.pet.name).pdf"
                ),
                preview: SharePreview("Receipt", image: Image(systemName: "doc.pdf"))
            ) {
                Label(NSLocalizedString("receipt.share", comment: ""), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.top, 10)
        } else if receiptFailed {
            Label("Receipt unavailable", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text(NSLocalizedString("receipt.preparing", comment: "Preparing receipt…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }

        Button(NSLocalizedString("common.done", comment: "")) {
            dismiss()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkout.doneButton")
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var processingContent: some View {
        ProgressView()
            .scaleEffect(1.5)
        Text("Processing payment…")
            .font(.headline)
        Text("Please keep the app open.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    func serviceTag(for service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                viewModel.toggleService(service)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: service.systemIcon ?? "pawprint.fill")
                Text(service.name)
            }
            .font(Font.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.05)))
            .overlay(Capsule().stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1))
            .foregroundStyle(isSelected ? Color.blue : Color.primary)
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkout.service.\(service.name)")
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }

    func addOnRow(_ service: Service) -> some View {
        let isSelected = viewModel.isAddOnSelected(service)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                viewModel.toggleAddOn(service)
            }
        } label: {
            HStack {
                Image(systemName: service.systemIcon ?? "sparkles")
                    .foregroundStyle(Color.blue)
                    .frame(width: 30)
                Text(service.name).font(.subheadline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.green : Color.gray)
                    .scaleEffect(isSelected ? 1.15 : 1.0)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 15).fill(DS.ColorToken.surface))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkout.addOn.\(service.name)")
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
    }

    func behaviorTag(for raw: String) -> some View {
        let isSelected = viewModel.tags.contains(raw)
        let display = BehaviorTagIcons.display(for: raw)
        return Button {
            viewModel.toggleTag(raw)
        } label: {
            HStack(spacing: 4) {
                if let emoji = display.emoji { Text(emoji) }
                Text(display.label)
            }
            .font(Font.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? Color.orange.opacity(0.15) : Color.clear))
            .overlay(Capsule().stroke(isSelected ? Color.orange : Color.gray.opacity(0.3), lineWidth: 1))
            .foregroundStyle(isSelected ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    func paymentCard(for option: PaymentOption) -> some View {
        let isSelected = viewModel.selectedPaymentMethod == option.method
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                viewModel.choosePayment(option.method)
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.title2)
                Text(option.label).font(Font.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 15).fill(isSelected ? option.tint.opacity(0.1) : Color.gray.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? option.tint : Color.clear, lineWidth: 2))
            .foregroundStyle(isSelected ? option.tint : Color.secondary)
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkout.payment.\(option.method.rawValue)")
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
    }

    func summaryRow(title: String, value: String, isTotal: Bool = false) -> some View {
        HStack {
            Text(title).font(isTotal ? Font.headline : Font.subheadline).foregroundStyle(Color.secondary)
            Spacer()
            Text(value).font(isTotal ? Font.headline.bold() : Font.subheadline).foregroundStyle(isTotal ? Color.blue : Color.primary)
        }
    }

    var amountBinding: Binding<String> {
        Binding(
            get: { amountEditorText },
            set: { newValue in
                let allowed = "0123456789" + (Locale.current.decimalSeparator ?? ".")
                let filtered = newValue.filter { allowed.contains($0) }
                amountEditorText = filtered
                amountSyncTask?.cancel()
                amountSyncTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        return
                    }
                    viewModel.setAmountDirectly(filtered)
                }
            }
        )
    }

    // Delegates to ViewModel so this is not recomputed on every render.
    var selectedServicesSummary: String { viewModel.selectedServicesSummary }

    struct PaymentOption: Identifiable {
        let id = UUID()
        let method: Payment.Method
        let icon: String
        let tint: Color
        var label: String { method.displayName }
    }

    static let paymentOptions: [PaymentOption] = [
        PaymentOption(method: .cash,       icon: "banknote",          tint: .green),
        PaymentOption(method: .creditCard, icon: "creditcard",         tint: .blue),
        PaymentOption(method: .debitCard,  icon: "creditcard.fill",    tint: .purple),
        PaymentOption(method: .zelle,      icon: "dollarsign.circle",  tint: .yellow),
        PaymentOption(method: .other,      icon: "ellipsis.circle",    tint: .gray),
    ]
}
