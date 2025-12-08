//
//  CheckoutView.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//  Refactored by Assistant on 2025-09-03
//  Redesigned for iOS inline checkout experience on 2025-10-09
//

import SwiftUI
import SwiftData

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: CheckoutViewModel
    @FocusState private var amountFieldFocused: Bool

    init(pet: Pet, visit: Visit? = nil) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(pet: pet, visit: visit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    servicesSection
                    behaviorSection
                    photosSection
                    serviceChargeSection
                    paymentSection
                    summarySection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("checkout.title")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, content: bottomCta)
            .alert(NSLocalizedString("common.error", comment: ""), isPresented: $viewModel.showAlert) {
                Button(NSLocalizedString("common.ok", comment: "")) {}
            } message: {
                Text(viewModel.alertMessage)
            }
            .overlay { processingOverlay(viewModel) }
            .overlay { successOverlay(viewModel) }
        }
        .onAppear {
            viewModel.loadServices(modelContext: modelContext)
        }
        .onChange(of: amountFieldFocused) {
            if !amountFieldFocused { viewModel.formatAmountInput() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(NSLocalizedString("common.confirm", comment: "")) {
                viewModel.formatAmountInput()
                hideKeyboard()
            }
        }
    }

    private func bottomCta() -> some View {
        Button(action: processCheckout) {
            HStack(spacing: 12) {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.headline)
                    Text(ctaButtonTitle)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(viewModel.finalTotalString)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .foregroundColor(.white)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color(red: 0.4, green: 0.85, blue: 0.97), Color(red: 0.65, green: 0.72, blue: 0.99)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        }
        .disabled(!viewModel.isConfirmEnabled || viewModel.isSaving)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var ctaButtonTitle: String {
        switch viewModel.state {
        case .processing:
            return NSLocalizedString("checkout.processing", comment: "")
        case .confirmed:
            return NSLocalizedString("common.done", comment: "")
        default:
            return NSLocalizedString("checkout.complete", comment: "")
        }
    }

    private func processCheckout() {
        switch viewModel.state {
        case .confirmed:
            dismiss()
        default:
            Task { await viewModel.processPayment() }
        }
    }

    @ViewBuilder
    private func processingOverlay(_ viewModel: CheckoutViewModel) -> some View {
        if viewModel.isSaving {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15))
                        ProgressView().tint(.accentColor)
                    }
                    .frame(width: 68, height: 68)
                    Text(NSLocalizedString("checkout.processing", comment: ""))
                        .font(.headline)
                    Text(NSLocalizedString("checkout.processing_desc", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .padding(32)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func successOverlay(_ viewModel: CheckoutViewModel) -> some View {
        if case .confirmed = viewModel.state {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.15))
                        Image(systemName: "checkmark")
                            .font(.title)
                            .foregroundStyle(.green)
                    }
                    .frame(width: 68, height: 68)
                    Text(NSLocalizedString("checkout.complete_title", comment: ""))
                        .font(.headline)
                    Text(String(format: NSLocalizedString("checkout.complete_desc_fmt", comment: ""), viewModel.finalTotalString))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button(NSLocalizedString("common.continue", comment: "")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .padding(32)
            }
            .transition(.opacity)
        }
    }
}

private extension CheckoutView {
    var headerSection: some View {
        Card(elevation: .raised, accent: .leading(.color(Color(red: 0.63, green: 0.69, blue: 0.99)))) {
            HStack(spacing: 16) {
                AvatarView(
                    .pet(
                        species: viewModel.pet.species,
                        gender: viewModel.pet.gender,
                        name: viewModel.pet.name,
                        imageData: viewModel.pet.photoData
                    ),
                    size: .lg,
                    ringWidth: 5
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.pet.name)
                        .font(.title3).fontWeight(.semibold)
                    Text(viewModel.pet.owner?.fullName ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
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

    var servicesSection: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("checkout.services_performed")
                    FlowLayout(spacing: 10, rowSpacing: 10) {
                        ForEach(viewModel.allServices) { service in
                            serviceTag(for: service)
                        }
                    }
                    if viewModel.allServices.isEmpty {
                        Text(NSLocalizedString("checkout.no_services_hint", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.addOnServices.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("checkout.add_ons", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        VStack(spacing: 10) {
                            ForEach(viewModel.addOnServices) { service in
                                addOnRow(service)
                            }
                        }
                    }
                }
            }
        }
    }

    var behaviorSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("checkout.notes_and_tags")
                notesEditor(
                    text: $viewModel.sessionNotes,
                    placeholder: NSLocalizedString("checkout.notes_placeholder", comment: "")
                )
                Text(NSLocalizedString("checkout.behavior_tags", comment: ""))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 10, rowSpacing: 10) {
                    ForEach(CheckoutViewModel.tagOptions, id: \.self) { tag in
                        behaviorTag(for: tag)
                    }
                }
            }
        }
    }

    var photosSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("checkout.before_after_photos")
                HStack(spacing: 16) {
                    PhotoWell(imageData: $viewModel.beforePhotoData, title: NSLocalizedString("photobox.before", comment: ""))
                    PhotoWell(imageData: $viewModel.afterPhotoData, title: NSLocalizedString("photobox.after", comment: ""))
                }
            }
        }
    }

    var serviceChargeSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("checkout.service_charge")
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    TextField("$0.00", text: amountBinding)
                        .keyboardType(.decimalPad)
                        .focused($amountFieldFocused)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(.label))
                }
                Text(NSLocalizedString("checkout.service_charge_hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var paymentSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("checkout.payment_method")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(paymentOptions, id: \.method) { option in
                        paymentCard(for: option)
                    }
                }

                if viewModel.requiresExternalReference {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("checkout.transaction_reference", comment: ""))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(viewModel.referencePlaceholder, text: $viewModel.externalReference)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    var summarySection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("checkout.session_summary")
                summaryRow(title: NSLocalizedString("checkout.summary.check_in", comment: ""), value: Formatters.timeOnly.string(from: viewModel.visit.startedAt))
                summaryRow(title: NSLocalizedString("checkout.summary.duration", comment: ""), value: viewModel.sessionDurationString)
                summaryRow(title: NSLocalizedString("checkout.summary.services", comment: ""), value: selectedServicesSummary)
                Divider()
                summaryRow(title: NSLocalizedString("checkout.total_amount", comment: ""), value: viewModel.finalTotalString, isTotal: true)
            }
        }
    }

    func sectionTitle(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(.label))
    }

    func summaryRow(title: String, value: String, isTotal: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(isTotal ? .headline : .subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(isTotal ? .title3.weight(.bold) : .subheadline)
                .foregroundStyle(isTotal ? .green : Color(.label))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    func serviceTag(for service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        return Button {
            viewModel.toggleService(service)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: service.systemIcon ?? "pawprint.fill")
                    .font(.footnote)
                Text(service.name)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color(red: 0.4, green: 0.85, blue: 0.97) : Color.gray.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(red: 0.4, green: 0.85, blue: 0.97) : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? Color(.label) : Color(.secondaryLabel))
        }
        .buttonStyle(.plain)
    }

    func addOnRow(_ service: Service) -> some View {
        let isSelected = viewModel.isAddOnSelected(service)
        return Button {
            viewModel.toggleAddOn(service)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: service.systemIcon ?? "sparkles")
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 36, height: 36)
                Text(service.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    func behaviorTag(for raw: String) -> some View {
        let isSelected = viewModel.tags.contains(raw)
        let display = BehaviorTagIcons.display(for: raw)
        return Button {
            if isSelected {
                viewModel.tags.remove(raw)
            } else {
                viewModel.tags.insert(raw)
            }
        } label: {
            HStack(spacing: 6) {
                if let emoji = display.emoji {
                    Text(emoji)
                        .font(.body)
                }
                Text(display.label)
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color(red: 0.87, green: 0.95, blue: 0.99) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(red: 0.4, green: 0.85, blue: 0.97) : Color.gray.opacity(0.25), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(.label))
    }

    func notesEditor(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .font(.body)
            if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                    .padding(.leading, 18)
            }
        }
    }

    func paymentCard(for option: PaymentOption) -> some View {
        let isSelected = viewModel.selectedPaymentMethod == option.method
        return Button {
            viewModel.choosePayment(option.method)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(option.tint.opacity(0.12))
                    Image(systemName: option.icon)
                        .font(.title3)
                        .foregroundStyle(option.tint)
                }
                .frame(width: 58, height: 58)
                Text(option.label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.label))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? option.tint.opacity(0.15) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? option.tint : Color.gray.opacity(0.2), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    var amountBinding: Binding<String> {
        Binding(
            get: { viewModel.amountString },
            set: { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                viewModel.setAmountDirectly("$" + filtered)
            }
        )
    }

    var selectedServicesList: [String] {
        let serviceNames = viewModel.allServices
            .filter { viewModel.selectedServiceIDs.contains($0.persistentModelID) }
            .map(\.name)
        let addOnNames = viewModel.addOnServices
            .filter { viewModel.selectedAddOnIDs.contains($0.persistentModelID) }
            .map(\.name)
        return (serviceNames + addOnNames).sorted()
    }

    var selectedServicesSummary: String {
        let list = selectedServicesList
        if list.isEmpty { return NSLocalizedString("checkout.none_selected", comment: "") }
        return list.joined(separator: ", ")
    }

    var paymentOptions: [PaymentOption] {
        [
            PaymentOption(method: .cash, icon: "banknote", tint: .green),
            PaymentOption(method: .creditCard, icon: "creditcard", tint: .blue),
            PaymentOption(method: .debitCard, icon: "creditcard", tint: .purple),
            PaymentOption(method: .zelle, icon: "dollarsign.circle", tint: .yellow)
        ]
    }
}

private extension CheckoutView {
    struct PaymentOption: Identifiable {
        let id = UUID()
        let method: Payment.Method
        let icon: String
        let tint: Color

        var label: String { method.displayName }
    }
}

fileprivate func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}
