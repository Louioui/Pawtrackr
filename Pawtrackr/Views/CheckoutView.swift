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

    init(pet: Pet) {
        // The modelContext can be accessed via the pet itself
        _viewModel = State(initialValue: CheckoutViewModel(pet: pet, modelContext: pet.modelContext!))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    servicesSection
                    notesSection
                    photosSection
                    chargeSection
                    Spacer(minLength: 80) // Space for bottom CTA
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Check Out")
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
        }
    }
    
    private func confirmAndDismiss() {
        Task {
            if await viewModel.confirmCheckout() {
                dismiss()
            }
        }
    }
    
    // MARK: - Sections
    @ViewBuilder
    private var headerSection: some View {
        Card {
            HStack(spacing: 12) {
                // FIX: Use the correct AvatarView initializer
                AvatarView(.pet(species: viewModel.pet.species, gender: viewModel.pet.gender, name: viewModel.pet.name, imageData: viewModel.pet.photoData), size: .lg)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.pet.name).font(.headline)
                    Text(viewModel.pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)
                    
                    Label(viewModel.visitTimer.formattedElapsed, systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.accent)
                        .monospacedDigit()
                        .padding(.top, 2)
                }
                Spacer()
            }
        }
    }
    
    private var servicesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Services Performed").font(.subheadline.weight(.semibold))
                // FIX: Use the correct 'Chip' component and binding syntax
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.allServices) { service in
                        Chip.selectable(
                            service.name,
                            isSelected: Binding(
                                get: { viewModel.isServiceSelected(service) },
                                set: { _, _  in viewModel.toggleService(service) }
                            )
                        )
                    }
                }
            }
        }
    }
    
    private var notesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session Notes").font(.subheadline.weight(.semibold))
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
                
                Text("Behavior Tags").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
    
    private var photosSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before & After Photos").font(.subheadline.weight(.semibold))
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
    
    private var chargeSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Payment Details").font(.subheadline.weight(.semibold))
                
                labeledContent("Amount") {
                    TextField("$0.00", text: $viewModel.amountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: viewModel.amountString) { newValue in
                            viewModel.setAmountDirectly(newValue)
                        }
                        .onSubmit {
                            viewModel.formatAmountInput()
                        }
                }
                
                labeledContent("Method") {
                    Picker("Payment Method", selection: $viewModel.selectedPaymentMethod) {
                        ForEach(Payment.Method.allCases) { m in Text(m.displayName).tag(m) }
                    }
                    .labelsHidden()
                }
                
                if viewModel.requiresExternalReference {
                    labeledContent("Reference") {
                        TextField(viewModel.referencePlaceholder, text: $viewModel.externalReference)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
                
                Divider()
                
                VStack(spacing: 8) {
                    // FIX: Access the final total from the ViewModel
                    HStack { Text("Total").fontWeight(.semibold); Spacer(); Text(viewModel.finalTotalString).fontWeight(.semibold) }
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
            Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Confirm", action: confirmAndDismiss)
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
        Button(action: confirmAndDismiss) {
            HStack {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Complete Checkout")
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
            if let data = imageData, let image = Image(platformImage: data) {
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
