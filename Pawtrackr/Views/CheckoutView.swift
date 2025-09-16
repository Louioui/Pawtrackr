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
    @Environment(\.modelContext) private var modelContext
    private let pet: Pet
    @State private var viewModel: CheckoutViewModel?

    init(pet: Pet) { self.pet = pet }
    
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    switch viewModel.state {
                    case .selectingServices:
                        ServiceSelectionView(viewModel: viewModel)
                    case .addingPhotos:
                        AddPhotosView(viewModel: viewModel)
                    case .choosingPayment:
                        PaymentView(viewModel: viewModel)
                    case .processing:
                        ProgressView("Processing...")
                    case .confirmed:
                        SuccessView()
                    case .failed(let error):
                        ErrorView(error: error, onRetry: { viewModel.previousStep() })
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("checkout.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, content: bottomCta)
            .alert("Checkout Error", isPresented: Binding(get: { viewModel?.showAlert ?? false }, set: { if !$0 { viewModel?.showAlert = false } })) {
                Button("OK") {}
            } message: {
                Text(viewModel?.alertMessage ?? "")
            }
            .overlay { if let vm = viewModel { processingOverlay(vm) } }
            .overlay { if let vm = viewModel { successOverlay(vm) } }
            .overlay {
                if viewModel == nil {
                    ZStack {
                        Color.clear
                        ProgressView()
                    }
                }
            }
        }
        .task { if viewModel == nil { viewModel = CheckoutViewModel(pet: pet, modelContext: modelContext) } }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("common.cancel", role: .cancel) { dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Confirm") {
                viewModel?.formatAmountInput()
                hideKeyboard()
            }
        }
    }

    private func bottomCta() -> some View {
        Button(action: { viewModel?.nextStep() }) {
            HStack {
                if viewModel?.isSaving ?? false {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaButtonTitle)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(viewModel?.finalTotalString ?? "")
                        .monospacedDigit()
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .disabled(!(viewModel?.isConfirmEnabled ?? false) || (viewModel?.isSaving ?? false))
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.ultraThinMaterial)
    }

    private var ctaButtonTitle: String {
        guard let state = viewModel?.state else { return "" }
        switch state {
        case .selectingServices, .addingPhotos:
            return "Next"
        case .choosingPayment:
            return "Confirm & Pay"
        case .processing:
            return "Processing..."
        case .confirmed:
            return "Done"
        case .failed:
            return "Retry"
        }
    }

    @ViewBuilder private func processingOverlay(_ viewModel: CheckoutViewModel) -> some View {
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

    @ViewBuilder private func successOverlay(_ viewModel: CheckoutViewModel) -> some View {
        if case .confirmed = viewModel.state {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack { Circle().fill(Color.green.opacity(0.15)); Image(systemName: "checkmark").foregroundStyle(.green) }
                        .frame(width: 64, height: 64)
                    Text("checkout.complete_title").font(.headline)
                    Text(String(format: NSLocalizedString("checkout.complete_desc_fmt", comment: ""), viewModel.finalTotalString))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("common.continue", comment: "")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(24)
            }
        }
    }
}

private struct ServiceSelectionView: View {
    @State var viewModel: CheckoutViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                petSessionHeader
                servicesBlock
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var petSessionHeader: some View {
        Card {
            HStack(spacing: 12) {
                AvatarView(.pet(species: viewModel.pet.species, gender: viewModel.pet.gender, name: viewModel.pet.name, imageData: viewModel.pet.photoData), size: .lg, ringWidth: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.pet.name).font(.headline)
                    Text(viewModel.pet.owner?.fullName ?? "").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text(String(
                            format: NSLocalizedString("checkout.started_time_fmt", comment: ""),
                            Formatters.timeOnly.string(from: viewModel.visit.startedAt)
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var servicesBlock: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("checkout.services_performed").font(.subheadline.weight(.semibold))
                    let packages = viewModel.allServices.filter { $0.category == .groom }
                    if !packages.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(packages) { service in
                                packageRow(service)
                            }
                        }
                    }
                    let individuals = viewModel.allServices.filter { $0.category != .groom }
                    if !individuals.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(individuals) { s in serviceTile(s) }
                        }
                    }
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
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("checkout.selected_services").font(.subheadline.weight(.semibold))
                    if viewModel.selectedServiceIDs.isEmpty && (viewModel.selectedExtras.isEmpty) {
                        Text("checkout.none_selected").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.allServices.filter { viewModel.selectedServiceIDs.contains($0.persistentModelID) }, id: \.persistentModelID) { svc in
                                Chip("\(svc.name)", style: .tinted, size: .sm)
                            }
                            ForEach(Array(viewModel.selectedExtras), id: \.self) { extra in
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
        let isSel = viewModel.selectedExtras.contains(title)
        return Button {
            if isSel { viewModel.selectedExtras.remove(title) } else { viewModel.selectedExtras.insert(title) }
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

    private func packageRow(_ service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        return Button {
            viewModel.toggleService(service)
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
        } label: {
            VStack(spacing: 6) {
                ZStack { Circle().fill(Color.accentColor.opacity(0.12)); Image(systemName: icon).foregroundStyle(Color.accentColor) }
                    .frame(width: 36, height: 36)
                Text(service.name).font(.caption.weight(.medium)).foregroundStyle(.primary)
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
}

private struct AddPhotosView: View {
    @State var viewModel: CheckoutViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                photosBlock
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var photosBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("checkout.before_after_photos").font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    PhotoWell(imageData: $viewModel.beforePhotoData, title: "Before")
                    PhotoWell(imageData: $viewModel.afterPhotoData, title: "After")
                }
            }
        }
    }
}

private struct PaymentView: View {
    @State var viewModel: CheckoutViewModel
    @State private var baseAmountString: String = ""
    @State private var selectedTipPercent: Int? = nil
    @State private var customTipString: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                chargeBlock
                paymentMethodBlock
                summaryBlock
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var chargeBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("checkout.service_charge").font(.subheadline.weight(.semibold))
                labeledContent(NSLocalizedString("checkout.base_charge", comment: "")) {
                    TextField("0.00", text: $baseAmountString)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: baseAmountString) { syncManualAmount() }
                }
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
                        .onChange(of: customTipString) { 
                            selectedTipPercent = nil
                            syncManualAmount()
                        }
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

    @ViewBuilder
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
        let isSel = (viewModel.selectedPaymentMethod == method)
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

    @ViewBuilder
    private var summaryBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("checkout.payment_summary").font(.subheadline.weight(.semibold))
                HStack { Text("checkout.base_charge"); Spacer(); Text(baseAmountDecimal.moneyString) }
                HStack { Text("checkout.tip_amount"); Spacer(); Text(tipDecimal.moneyString) }
                Divider()
                HStack { Text("checkout.total_amount").font(.headline); Spacer(); Text(viewModel.finalTotalString).font(.title3).fontWeight(.bold).foregroundStyle(.green) }
            }
        }
        .monospacedDigit()
    }

    private var baseAmountDecimal: Decimal {
        Formatters.parseCurrency(baseAmountString) ?? 0
    }

    private var tipDecimal: Decimal {
        if let pct = selectedTipPercent {
            let base = baseAmountDecimal
            return (base *~ Decimal(pct) / 100).roundedMoney()
        }
        return Formatters.parseCurrency(customTipString) ?? 0
    }

    private func syncManualAmount() {
        let total = (baseAmountDecimal +~ tipDecimal).roundedMoney()
        viewModel.setAmountDirectly(total.moneyString)
    }
}

private struct SuccessView: View {
    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.green)
            Text("Checkout Complete!")
                .font(.title)
        }
    }
}

private struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack {
            Image(systemName: "xmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .font(.title)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

fileprivate func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

fileprivate func cachedImage(_ data: Data) -> Image? {
    #if canImport(UIKit)
    if let ui = ImageCache.shared.image(data: data, maxDimension: 800) { return Image(uiImage: ui) }
    #elseif canImport(AppKit)
    if let ns = NSImage(data: data) { return Image(nsImage: ns) }
    #endif
    return nil
}