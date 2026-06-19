//
//  NewClientSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData
import Observation
import PhotosUI
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct NewClientSheet: View {
    private enum FocusField: Hashable {
        case firstName
        case lastName
        case phone
        case email
        case address
        case contactName(UUID)
        case contactPhone(UUID)
        case petName(UUID)
        case petBreed(UUID)
        case petColor(UUID)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(WalkthroughController.self) private var walkthrough: WalkthroughController?
    private let modelContext: ModelContext
    @State private var viewModel: NewClientViewModel?
    @State private var didFocusInitialField = false
    @FocusState private var focusedField: FocusField?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var body: some View {
        sheetContent
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 540, maxWidth: 640, minHeight: 560, idealHeight: 680)
        #endif
        .onAppear {
            if viewModel == nil {
                viewModel = NewClientViewModel(modelContext: modelContext)
            }
            focusInitialFieldIfNeeded()
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let walkthrough {
            navigationContent
                .walkthroughOverlay(walkthrough, presenting: .newClient)
        } else {
            navigationContent
        }
    }

    private var navigationContent: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    formContent(viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func formContent(_ viewModel: NewClientViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: 16) {
                // Owner Info Card
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("new_client.owner", comment: "")).font(.subheadline.weight(.semibold))
                        inputField(
                            NSLocalizedString("new_client.first_name", comment: ""),
                            text: $viewModel.first,
                            accessibilityIdentifier: "newClient.firstName",
                            validationError: viewModel.validationError(for: .first),
                            focus: .firstName,
                            nextFocus: .lastName
                        )
                        .onChange(of: viewModel.first) { _, _ in viewModel.clearValidationError(for: .first) }

                        inputField(
                            NSLocalizedString("new_client.last_name", comment: ""),
                            text: $viewModel.last,
                            accessibilityIdentifier: "newClient.lastName",
                            validationError: viewModel.validationError(for: .last),
                            focus: .lastName,
                            nextFocus: .phone
                        )
                        .onChange(of: viewModel.last) { _, _ in viewModel.clearValidationError(for: .last) }

                        inputField(
                            NSLocalizedString("new_client.phone", comment: ""),
                            text: $viewModel.phone,
                            accessibilityIdentifier: "newClient.phone",
                            validationError: viewModel.validationError(for: .phone),
                            focus: .phone,
                            nextFocus: .email
                        )
                            .phoneFieldFormatting($viewModel.phone)
                            .onChange(of: viewModel.phone) { _, _ in viewModel.clearValidationError(for: .phone) }

                        inputField(
                            NSLocalizedString("new_client.email", comment: ""),
                            text: $viewModel.email,
                            accessibilityIdentifier: "newClient.email",
                            validationError: viewModel.validationError(for: .email),
                            focus: .email,
                            nextFocus: .address
                        )
                        .onChange(of: viewModel.email) { _, _ in viewModel.clearValidationError(for: .email) }

                        inputField(
                            NSLocalizedString("new_client.address", comment: ""),
                            text: $viewModel.address,
                            accessibilityIdentifier: "newClient.address",
                            focus: .address,
                            nextFocus: firstPetFocus(in: viewModel)
                        )
                    }
                }
                .walkthroughTarget(.ncOwner)
                .padding(.horizontal)

                // Emergency Contacts Card
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(NSLocalizedString("new_client.emergency_contacts", comment: "")).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.addContact()
                            } label: {
                                Label(NSLocalizedString("new_client.add", comment: ""), systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        if viewModel.contacts.isEmpty {
                            Text(NSLocalizedString("new_client.add_contact_hint", comment: ""))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($viewModel.contacts) { $contact in
                                VStack(alignment: .leading, spacing: 8) {
                                    inputField(
                                        NSLocalizedString("new_client.contact_name", comment: ""),
                                        text: $contact.name,
                                        focus: .contactName(contact.id),
                                        nextFocus: .contactPhone(contact.id)
                                    )
                                    inputField(
                                        NSLocalizedString("new_client.contact_phone", comment: ""),
                                        text: $contact.phone,
                                        focus: .contactPhone(contact.id),
                                        nextFocus: firstPetFocus(in: viewModel)
                                    )
                                        .phoneFieldFormatting($contact.phone)
                                }
                                .padding()
                                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Pet Management Card
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(NSLocalizedString("new_client.pets", comment: "")).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.addPet()
                            } label: {
                                Label(NSLocalizedString("new_client.add_pet", comment: ""), systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                        if viewModel.pets.isEmpty {
                            Text(NSLocalizedString("new_client.add_pet_hint", comment: ""))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach($viewModel.pets) { $pet in
                            VStack(alignment: .leading, spacing: 0) {
                                // Gender accent bar
                                Rectangle()
                                    .fill(DS.ColorToken.gender(pet.gender))
                                    .frame(height: 4)

                                VStack(alignment: .leading, spacing: 8) {
                                    // Photo section
                                    HStack {
                                        Spacer()
                                        ImagePicker(imageData: $pet.photoData) {
                                            VStack(alignment: .center, spacing: 8) {
                                                AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .lg)
                                                Text(NSLocalizedString("new_client.choose_photo", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }

                                    inputField(
                                        NSLocalizedString("new_client.pet_name", comment: ""),
                                        text: $pet.name,
                                        focus: .petName(pet.id),
                                        nextFocus: .petBreed(pet.id)
                                    )

                                    HStack(spacing: 12) {
                                        inputField(
                                            NSLocalizedString("add_pet.breed", comment: ""),
                                            text: $pet.breed,
                                            focus: .petBreed(pet.id),
                                            nextFocus: .petColor(pet.id)
                                        )
                                        inputField(
                                            NSLocalizedString("add_pet.color", comment: ""),
                                            text: $pet.color,
                                            focus: .petColor(pet.id),
                                            nextFocus: nil,
                                            submitLabel: .done
                                        )
                                    }

                                    Picker(NSLocalizedString("new_client.species", comment: ""), selection: $pet.species) {
                                        ForEach(Species.allCases) { species in
                                            Text(species.rawValue.capitalized).tag(species)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    Picker(NSLocalizedString("new_client.gender", comment: ""), selection: $pet.gender) {
                                        Text(PetGender.male.displayName).tag(PetGender.male as PetGender?)
                                        Text(PetGender.female.displayName).tag(PetGender.female as PetGender?)
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding()
                            }
                            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.ColorToken.border.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                .walkthroughTarget(.ncPets)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(NSLocalizedString("new_client.new_client", comment: ""))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { dismiss() }
                    .accessibilityIdentifier("newClient.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Logger.newClient.info("Create button tapped")
                    Task {
                        let outcome = await viewModel.createClient()
                        Logger.newClient.info("Create button outcome: \(String(describing: outcome))")
                        if outcome == .created {
                            if let createdClientID = viewModel.createdClientID {
                                walkthrough?.focusClientDetail(createdClientID)
                            }
                            if walkthrough?.currentStep?.presents == .newClient {
                                walkthrough?.completePresentation(.newClient)
                            }
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Label(NSLocalizedString("common.create", comment: ""), systemImage: "checkmark.circle.fill")
                    }
                }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("newClient.create")
                // NOTE: deliberately NOT `.walkthroughAnchor(.ncSave)`. Toolbar items
                // live in a UINavigationBar and report bogus anchor bounds, which made
                // the spotlight cut a large/mis-placed hole (form looked un-dimmed and
                // the bubble arrow pointed at nothing). The `.ncSave` step falls back to
                // a deterministic platform-specific action rect instead.
            }
        }
        .alert(
            Text(NSLocalizedString("common.error", comment: "")),
            isPresented: Binding(
                get: { viewModel.appError != nil },
                set: { if !$0 { viewModel.appError = nil } }
            ),
            presenting: viewModel.appError
        ) { _ in
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func inputField(
        _ title: String,
        text: Binding<String>,
        accessibilityIdentifier: String? = nil,
        validationError: String? = nil,
        focus: FocusField,
        nextFocus: FocusField?,
        submitLabel: SubmitLabel = .next
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text)
                .optionalAccessibilityIdentifier(accessibilityIdentifier)
                .focused($focusedField, equals: focus)
                .submitLabel(submitLabel)
                .onSubmit {
                    focusedField = nextFocus
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(validationError == nil ? DS.ColorToken.border : DS.ColorToken.danger, lineWidth: validationError == nil ? 1 : 1.5)
                )

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(DS.ColorToken.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(accessibilityIdentifier ?? "field").error")
            }
        }
    }

    private func focusInitialFieldIfNeeded() {
        guard !didFocusInitialField else { return }
        guard walkthrough?.currentStep?.presents != .newClient else { return }
        didFocusInitialField = true
        DispatchQueue.main.async {
            focusedField = .firstName
        }
    }

    private func firstPetFocus(in viewModel: NewClientViewModel) -> FocusField? {
        guard let pet = viewModel.pets.first else { return nil }
        return .petName(pet.id)
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

private extension Logger {
    static let newClient = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "NewClient")
}
