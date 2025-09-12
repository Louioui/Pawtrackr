//
//  CheckoutView.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//  Refactored by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CheckoutViewModel
    // UI extras to match the HTML mockup
    @State private var baseAmountString: String = ""
    @State private var selectedTipPercent: Int? = nil
    @State private var customTipString: String = ""
    @State private var showSuccessModal = false
    @State private var selectedExtras: Set<String> = []

    init(pet: Pet) {
        // The modelContext can be accessed via the pet itself
        _viewModel = State(initialValue: CheckoutViewModel(pet: pet, modelContext: pet.modelContext!))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    petSessionHeader
                    servicesBlock
                    notesAndTagsBlock
                    photosBlock
                    chargeBlock
                    paymentMethodBlock
                    summaryBlock
                    Spacer(minLength: 80) // Space for bottom CTA
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("checkout.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, content: bottomCta)
            .alert("Checkout Error", isPresented: $viewModel.showAlert) {
                Button("OK") {}
            } message: {
                Text(viewModel.alertMessage)
            }
            .overlay { processingOverlay }
            .overlay { successOverlay }
        }
    }
    
    private func confirmAndDismiss() {
        Task {
            if await viewModel.confirmCheckout() {
                dismiss()
            }
        }
    }
    
    // MARK: - Sections (facelifted)
    @ViewBuilder
    private var petSessionHeader: some View {
        Card {
            HStack(spacing: 12) {
                AvatarView(.pet(species: viewModel.pet.species, gender: viewModel.pet.gender, name: viewModel.pet.name, imageData: viewModel.pet.photoData), size: .lg, ringWidth: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.pet.name).font(.headline)
                    Text(viewModel.pet.owner?.fullName ?? "").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundStyle(.green)
                        Text("Session: \(viewModel.sessionDurationString)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NSLocalizedString("checkout.started", comment: "")).font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.timeOnly.string(from: viewModel.visit.startedAt))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
    
    private var servicesBlock: some View {
        VStack(spacing: 12) {
            // Services catalog (packages + individual services)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("checkout.services_performed").font(.subheadline.weight(.semibold))
                    // Packages (.groom category)
                    let packages = viewModel.allServices.filter { $0.category == .groom }
                    if !packages.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(packages) { service in
                                packageRow(service)
                            }
                        }
                    }
                    // Individual services (non-groom)
                    let individuals = viewModel.allServices.filter { $0.category != .groom }
                    if !individuals.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(individuals) { s in serviceTile(s) }
                        }
                    }

                    // Additional services (variable pricing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("checkout.additional_services").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        VStack(spacing: 8) {
                            additionalServiceRow(title: "Knots & Matting Fee", subtitle: "$5–10+ (varies by severity)", icon: "k.square.fill")
                            additionalServiceRow(title: "Flea & Tick Treatment", subtitle: "$5–10", icon: "ant.fill")
                            additionalServiceRow(title: "Hair Dye", subtitle: "$80–1,000 (varies by complexity)", icon: "paintpalette.fill")
                        }
                    }
                }
            }

            // Selected services summary (catalog + extras)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("checkout.selected_services").font(.subheadline.weight(.semibold))
                    if selectedServices.isEmpty && selectedExtras.isEmpty {
                        Text("checkout.none_selected").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(selectedServices, id: \.persistentModelID) { svc in
                                Chip("\(svc.name)", style: .tinted, size: .sm)
                            }
                            ForEach(Array(selectedExtras), id: \.self) { extra in
                                Chip(extra, style: .tinted, size: .sm)
                            }
                        }
                    }
                    Text("checkout.prices_may_vary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func additionalServiceRow(title: String, subtitle: String, icon: String) -> some View {
        let isSel = selectedExtras.contains(title)
        return Button {
            if isSel { selectedExtras.remove(title) } else { selectedExtras.insert(title) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack { Circle().fill(Color.accentColor.opacity(0.12)); Image(systemName: icon).foregroundStyle(Color.accentColor) }
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSel ? .green : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSel ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var notesAndTagsBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("checkout.notes_and_tags").font(.subheadline.weight(.semibold))
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
                
                Text("checkout.behavior_tags").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    // FIX: Use the correct 'Chip' component and binding syntax for the tags Set
                    ForEach(CheckoutViewModel.tagOptions, id: \.self) { tag in
                        Chip.selectable(
                            tag,
                            isSelected: Binding(
                                get: { viewModel.tags.contains(tag) },
                                set: { isSelected, _ in
                                    if isSelected {
                                        viewModel.tags.insert(tag)
                                    } else {
                                        viewModel.tags.remove(tag)
                                    }
                                }
                            )
                        )
                    }
                }
            }
        }
    }
    
    private var photosBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("checkout.before_after_photos").font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ImagePicker(imageData: $viewModel.beforePhotoData, source: .prompt, allowsEditing: true, maxDimension: 1600, jpegQuality: 0.88) {
                        // FIX: Use the correct 'AddPhotoPlaceholder' view.
                        // We also create a small helper to display the image once chosen.
                        PhotoWell(imageData: viewModel.beforePhotoData, title: "Before")
                            .contextMenu {
                                if viewModel.beforePhotoData != nil {
                                    Button(role: .destructive) { viewModel.beforePhotoData = nil } label: {
                                        Label("Remove Photo", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    ImagePicker(imageData: $viewModel.afterPhotoData, source: .prompt, allowsEditing: true, maxDimension: 1600, jpegQuality: 0.88) {
                        PhotoWell(imageData: viewModel.afterPhotoData, title: "After")
                            .contextMenu {
                                if viewModel.afterPhotoData != nil {
                                    Button(role: .destructive) { viewModel.afterPhotoData = nil } label: {
                                        Label("Remove Photo", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
    }
    
    private var chargeBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("checkout.service_charge").font(.subheadline.weight(.semibold))
                labeledContent(NSLocalizedString("checkout.base_amount", comment: "")) {
                    TextField("0.00", text: $baseAmountString)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: baseAmountString) { _ in syncManualAmount() }
                }
                
                // Tip UI — contributes into total via syncManualAmount
                VStack(alignment: .leading, spacing: 8) {
                    Text("checkout.tip_amount").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach([0, 15, 20, 25], id: \.self) { pct in
                            let isSel = selectedTipPercent == pct
                            Chip("\(pct == 0 ? "None" : "\(pct)%")",
                                 style: isSel ? .prominent : .outline,
                                 size: .sm,
                                 tint: .green
                            ) {
                                selectedTipPercent = pct
                                customTipString = ""
                                syncManualAmount()
                            }
                        }
                    }
                    TextField(NSLocalizedString("checkout.custom_tip", comment: ""), text: $customTipString)
                        .keyboardType(.decimalPad)
                        .onChange(of: customTipString) { _ in
                            selectedTipPercent = nil
                            syncManualAmount()
                        }
                }

                if viewModel.requiresExternalReference {
                    labeledContent(NSLocalizedString("checkout.reference", comment: "")) {
                        TextField(viewModel.referencePlaceholder, text: $viewModel.externalReference)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
                
                Divider()
                
                VStack(spacing: 8) {
                    HStack { Text("checkout.total").fontWeight(.semibold); Spacer(); Text(viewModel.finalTotalString).fontWeight(.semibold) }
                }
                .monospacedDigit()
            }
            .animation(.default, value: viewModel.requiresExternalReference)
        }
    }
    
    private func labeledContent<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

    // FIX: Use @ToolbarContentBuilder for correct type inference.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("common.cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("common.confirm", action: confirmCheckoutFlow)
                .disabled(!viewModel.isConfirmEnabled)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                viewModel.formatAmountInput()
                hideKeyboard()
            }
        }
    }

    private func bottomCta() -> some View {
        Button(action: confirmCheckoutFlow) {
            HStack {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("checkout.complete")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(viewModel.finalTotalString)
                        .monospacedDigit()
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.isConfirmEnabled || viewModel.isSaving)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Payment methods block (button grid)
    private var paymentMethodBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("checkout.payment_method").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    paymentTile(.cash, icon: "banknote", tint: .green)
                    paymentTile(.creditCard, icon: "creditcard", tint: .blue)
                    paymentTile(.debitCard, icon: "creditcard", tint: .purple)
                    paymentTile(.zelle, icon: "dollarsign.circle", tint: .yellow)
                }
                if viewModel.requiresExternalReference {
                    labeledContent(NSLocalizedString("checkout.transaction_reference", comment: "")) {
                        TextField(viewModel.referencePlaceholder, text: $viewModel.externalReference)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func paymentTile(_ method: Payment.Method, icon: String, tint: Color) -> some View {
        let isSel = viewModel.selectedPaymentMethod == method
        return Button {
            viewModel.choosePayment(method)
        } label: {
            VStack(spacing: 8) {
                ZStack { Circle().fill(tint.opacity(0.12)); Image(systemName: icon).foregroundStyle(tint) }
                    .frame(width: 48, height: 48)
                Text(method.displayName).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSel ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
                    .background(isSel ? Color.accentColor.opacity(0.06) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary block
    private var summaryBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("checkout.payment_summary").font(.subheadline.weight(.semibold))
                HStack { Text("checkout.base_charge"); Spacer(); Text(baseAmountDecimal.moneyString) }
                HStack { Text("checkout.tip_amount"); Spacer(); Text(tipDecimal.moneyString) }
                Divider()
                HStack { Text("checkout.total_amount").font(.headline); Spacer(); Text(viewModel.finalTotalString).font(.title3).fontWeight(.bold).foregroundStyle(.green) }
                Card {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                        Text("checkout.session_summary").font(.subheadline.weight(.medium))
                    }
                    .padding(.bottom, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: NSLocalizedString("checkout.duration_fmt", comment: ""), viewModel.sessionDurationString))
                        Text(String(format: NSLocalizedString("checkout.started_time_fmt", comment: ""), Formatters.timeOnly.string(from: viewModel.visit.startedAt)))
                        Text(String(format: NSLocalizedString("checkout.payment_method_fmt", comment: ""), viewModel.selectedPaymentMethod.displayName))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .monospacedDigit()
    }

    // MARK: - Service tiles/helpers
    private func packageRow(_ service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        return Button {
            viewModel.toggleService(service)
            syncManualAmount()
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.name).font(.subheadline.weight(.semibold))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func serviceTile(_ service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        let icon = service.systemIcon ?? "pawprint.fill"
        return Button {
            viewModel.toggleService(service)
            syncManualAmount()
        } label: {
            VStack(spacing: 6) {
                ZStack { Circle().fill(Color.accentColor.opacity(0.12)); Image(systemName: icon).foregroundStyle(Color.accentColor) }
                    .frame(width: 36, height: 36)
                Text(service.name).font(.caption.weight(.medium)).foregroundStyle(.primary)
                // Hide per-service price; user will input amount manually
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
                    .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overlays
    @ViewBuilder private var processingOverlay: some View {
        if viewModel.isSaving {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 12) {
                    ZStack { Circle().fill(Color.accentColor.opacity(0.12)); ProgressView().tint(.accentColor) }
                        .frame(width: 64, height: 64)
                    Text("checkout.processing").font(.headline)
                    Text("checkout.processing_desc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(24)
            }
        }
    }

    @ViewBuilder private var successOverlay: some View {
        if showSuccessModal {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack { Circle().fill(Color.green.opacity(0.15)); Image(systemName: "checkmark").foregroundStyle(.green) }
                        .frame(width: 64, height: 64)
                    Text("checkout.complete_title").font(.headline)
                    Text(String(format: NSLocalizedString("checkout.complete_desc_fmt", comment: ""), viewModel.finalTotalString))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("common.continue", comment: "")) { showSuccessModal = false; dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(24)
            }
        }
    }

    // MARK: - Derived (UI money math)
    private var selectedServices: [Service] {
        viewModel.allServices.filter { viewModel.isServiceSelected($0) }
    }

    private var servicesSubtotal: Decimal { 0 } // User will provide total amount manually

    private var baseAmountDecimal: Decimal {
        Formatters.parseCurrency(baseAmountString) ?? 0
    }

    private var tipDecimal: Decimal {
        if let pct = selectedTipPercent {
            let base = baseAmountDecimal +~ servicesSubtotal
            return (base *~ Decimal(pct) / 100).roundedMoney()
        }
        return Formatters.parseCurrency(customTipString) ?? 0
    }

    private func syncManualAmount() {
        let total = (servicesSubtotal +~ baseAmountDecimal +~ tipDecimal).roundedMoney()
        viewModel.setAmountDirectly(total.moneyString)
    }

    private func confirmCheckoutFlow() {
        Task { @MainActor in
            syncManualAmount()
            if await viewModel.confirmCheckout() {
                showSuccessModal = true
            }
        }
    }
}

// MARK: - Private Helpers

fileprivate func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

// Helper to avoid duplicating the image/placeholder logic
fileprivate struct PhotoWell: View {
    let imageData: Data?
    let title: String
    
    var body: some View {
        ZStack {
            if let data = imageData, let image = imageFromData(data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                AddPhotoPlaceholder(title: title, subtitle: "Tap to add")
            }
        }
        .frame(maxWidth: .infinity, idealHeight: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Data → SwiftUI Image helper (module-wide safe)
fileprivate func imageFromData(_ data: Data) -> Image? {
    #if canImport(UIKit)
    if let ui = UIImage(data: data) { return Image(uiImage: ui) }
    #elseif canImport(AppKit)
    if let ns = NSImage(data: data) { return Image(nsImage: ns) }
    #endif
    return nil
}
