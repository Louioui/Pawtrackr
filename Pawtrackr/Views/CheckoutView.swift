//
//  CheckoutView.swift
//  Pawtrackr
//

import SwiftUI
import SwiftData

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CheckoutViewModel
    @State private var currentStep: CheckoutStep = .services
    @FocusState private var amountFieldFocused: Bool

    enum CheckoutStep: Int, CaseIterable {
        case services = 0
        case details = 1
        case payment = 2
        
        var title: String {
            switch self {
            case .services: return "Services"
            case .details: return "Notes & Photos"
            case .payment: return "Payment"
            }
        }
    }

    init(pet: Pet, visit: Visit? = nil) {
        _viewModel = State(initialValue: CheckoutViewModel(pet: pet, visit: visit))
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            
            TabView(selection: $currentStep) {
                servicesStep.tag(CheckoutStep.services)
                detailsStep.tag(CheckoutStep.details)
                paymentStep.tag(CheckoutStep.payment)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.spring(), value: currentStep)
            
            bottomBar
        }
        .background(DS.ColorToken.background.ignoresSafeArea())
        .navigationTitle(currentStep.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert(item: $viewModel.appError) { error in
            Alert(title: Text("Error"), message: Text(error.localizedDescription), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            viewModel.loadServices(modelContext: modelContext)
        }
        .overlay {
            if viewModel.isSaving || viewModel.state == .confirmed {
                overlayContent
            }
        }
    }

    // MARK: - Steps
    
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(CheckoutStep.allCases, id: \.self) { step in
                VStack(spacing: 8) {
                    Circle()
                        .fill(currentStep.rawValue >= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(step.title)
                        .font(Font.caption2.weight(.medium))
                        .foregroundStyle(currentStep.rawValue >= step.rawValue ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                
                if step != .payment {
                    Rectangle()
                        .fill(currentStep.rawValue > step.rawValue ? Color.blue : Color.gray.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: -12)
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
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Main Services").font(.headline).padding(.horizontal)
                    Card {
                        FlowLayout(spacing: 10, rowSpacing: 10) {
                            ForEach(viewModel.allServices) { service in
                                serviceTag(for: service)
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
            .padding(.vertical)
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior & Notes").font(.headline).padding(.horizontal)
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            FlowLayout(spacing: 10, rowSpacing: 10) {
                                ForEach(CheckoutViewModel.tagOptions, id: \.self) { tag in
                                    behaviorTag(for: tag)
                                }
                            }
                            
                            TextEditor(text: $viewModel.sessionNotes)
                                #if os(iOS)
                                .scrollContentBackground(.hidden)
                                #endif
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Photos").font(.headline).padding(.horizontal)
                    Card {
                        HStack(spacing: 20) {
                            PhotoWell(imageData: $viewModel.beforePhotoData, title: "Before")
                            PhotoWell(imageData: $viewModel.afterPhotoData, title: "After")
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private var paymentStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Final Amount").font(.headline).padding(.horizontal)
                    Card {
                        TextField("$0.00", text: amountBinding)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .focused($amountFieldFocused)
                            .font(Font.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(TextAlignment.center)
                            .foregroundStyle(Color.blue)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Payment Method").font(.headline).padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(paymentOptions) { option in
                            paymentCard(for: option)
                        }
                    }
                    .padding(.horizontal)
                }

                if viewModel.requiresExternalReference {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference Info").font(Font.subheadline.weight(.medium)).padding(.horizontal)
                        TextField(viewModel.referencePlaceholder, text: $viewModel.externalReference)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
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
                if currentStep != .services {
                    Button {
                        withAnimation { currentStep = CheckoutStep(rawValue: currentStep.rawValue - 1) ?? .services }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                }
                
                Button {
                    if currentStep == .payment {
                        confirmCheckout()
                    } else {
                        withAnimation { currentStep = CheckoutStep(rawValue: currentStep.rawValue + 1) ?? .payment }
                    }
                } label: {
                    Text(currentStep == .payment ? "Confirm & Pay" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 15).fill(isNextEnabled ? Color.blue : Color.gray.opacity(0.3)))
                        .foregroundStyle(.white)
                }
                .disabled(!isNextEnabled)
            }
            .padding()
            .background(DS.ColorToken.background)
        }
    }

    private var isNextEnabled: Bool {
        switch currentStep {
        case .services: return !viewModel.selectedServiceIDs.isEmpty
        case .details: return true
        case .payment: return viewModel.isConfirmEnabled
        }
    }

    private func confirmCheckout() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        Task {
            await viewModel.processPayment()
        }
    }

    private var overlayContent: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                if viewModel.state == .confirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Payment Successful").font(Font.title3.weight(.bold))
                    Text(viewModel.finalTotalString).font(Font.title.bold())
                    
                    ShareLink(item: ReceiptDocument(pdfData: PDFReceiptService.shared.generatePDF(for: viewModel.visit), filename: "Receipt_\(viewModel.pet.name).pdf")) {
                        Label("Share Receipt", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 10)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Processing Payment...").font(.headline)
                }
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 25).fill(DS.ColorToken.surface))
            .shadow(radius: 20)
        }
        .onChange(of: viewModel.state) { _, newValue in
            if newValue == .confirmed {
                #if os(iOS)
                HapticManager.notify(.success)
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Helpers

    func serviceTag(for service: Service) -> some View {
        let isSelected = viewModel.isServiceSelected(service)
        return Button {
            viewModel.toggleService(service)
            viewModel.updateVisitItems()
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
        }
        .buttonStyle(.plain)
    }

    func addOnRow(_ service: Service) -> some View {
        let isSelected = viewModel.isAddOnSelected(service)
        return Button {
            viewModel.toggleAddOn(service)
            viewModel.updateVisitItems()
        } label: {
            HStack {
                Image(systemName: service.systemIcon ?? "sparkles")
                    .foregroundStyle(Color.blue)
                    .frame(width: 30)
                Text(service.name).font(.subheadline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.green : Color.gray)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 15).fill(DS.ColorToken.surface))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func behaviorTag(for raw: String) -> some View {
        let isSelected = viewModel.tags.contains(raw)
        let display = BehaviorTagIcons.display(for: raw)
        return Button {
            if isSelected { viewModel.tags.remove(raw) } else { viewModel.tags.insert(raw) }
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
            viewModel.choosePayment(option.method)
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
        }
        .buttonStyle(.plain)
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
            get: { viewModel.amountString },
            set: { newValue in
                let allowed = "0123456789" + (Locale.current.decimalSeparator ?? ".")
                viewModel.amountString = newValue.filter { allowed.contains($0) }
            }
        )
    }

    var selectedServicesSummary: String {
        let list = (viewModel.allServices.filter { viewModel.selectedServiceIDs.contains($0.persistentModelID) }.map(\.name) +
                    viewModel.addOnServices.filter { viewModel.selectedAddOnIDs.contains($0.persistentModelID) }.map(\.name)).sorted()
        return list.isEmpty ? "None" : list.joined(separator: ", ")
    }

    var paymentOptions: [PaymentOption] {
        [
            PaymentOption(method: .cash, icon: "banknote", tint: .green),
            PaymentOption(method: .creditCard, icon: "creditcard", tint: .blue),
            PaymentOption(method: .debitCard, icon: "creditcard", tint: .purple),
            PaymentOption(method: .zelle, icon: "dollarsign.circle", tint: .yellow)
        ]
    }

    struct PaymentOption: Identifiable {
        let id = UUID()
        let method: Payment.Method
        let icon: String
        let tint: Color
        var label: String { method.displayName }
    }
}
