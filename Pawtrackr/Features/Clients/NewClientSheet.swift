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
    @Environment(\.dismiss) private var dismiss
    private let modelContext: ModelContext
    @State private var viewModel: NewClientViewModel?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var body: some View {
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
        .onAppear {
            if viewModel == nil {
                viewModel = NewClientViewModel(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func formContent(_ viewModel: NewClientViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: 16) {
                // Owner Photo Card
                OwnerPhotoCard(photoSelection: $viewModel.photoSelection, avatarImage: viewModel.avatarImage)
                .padding(.horizontal)

                // Owner Info Card
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("new_client.owner", comment: "")).font(.subheadline.weight(.semibold))
                        inputField(NSLocalizedString("new_client.first_name", comment: ""), text: $viewModel.first, accessibilityIdentifier: "newClient.firstName")
                        inputField(NSLocalizedString("new_client.last_name", comment: ""), text: $viewModel.last, accessibilityIdentifier: "newClient.lastName")
                        inputField(NSLocalizedString("new_client.phone", comment: ""), text: $viewModel.phone, accessibilityIdentifier: "newClient.phone")
                            .phoneFieldFormatting($viewModel.phone)
                        inputField(NSLocalizedString("new_client.email", comment: ""), text: $viewModel.email, accessibilityIdentifier: "newClient.email")
                        inputField(NSLocalizedString("new_client.address", comment: ""), text: $viewModel.address, accessibilityIdentifier: "newClient.address")
                    }
                }
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
                                    inputField(NSLocalizedString("new_client.contact_name", comment: ""), text: $contact.name)
                                    inputField(NSLocalizedString("new_client.contact_phone", comment: ""), text: $contact.phone)
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

                                    inputField(NSLocalizedString("new_client.pet_name", comment: ""), text: $pet.name)

                                    HStack(spacing: 12) {
                                        inputField(NSLocalizedString("add_pet.breed", comment: ""), text: $pet.breed)
                                        inputField(NSLocalizedString("add_pet.color", comment: ""), text: $pet.color)
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
                .padding(.horizontal)
            }
            .padding(.vertical)
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
                        if outcome == .created { dismiss() }
                    }
                } label: {
                    Label(NSLocalizedString("common.create", comment: ""), systemImage: "checkmark.circle.fill")
                }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("newClient.create")
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
    private func inputField(_ title: String, text: Binding<String>, accessibilityIdentifier: String? = nil) -> some View {
        TextField(title, text: text)
            .optionalAccessibilityIdentifier(accessibilityIdentifier)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.ColorToken.border, lineWidth: 1))
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

#if os(iOS)
private typealias OwnerAvatarImage = UIImage
#elseif os(macOS)
private typealias OwnerAvatarImage = NSImage
#endif

private struct OwnerPhotoCard: View {
    @Binding var photoSelection: PhotosPickerItem?
    let avatarImage: OwnerAvatarImage?

    var body: some View {
        Card {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                HStack(alignment: .center, spacing: 12) {
                    avatarPreview
                    Text(NSLocalizedString("new_client.photo_hint", value: "Tap to add owner photo", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let avatarImage {
            #if os(iOS)
            Image(uiImage: avatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            #elseif os(macOS)
            Image(nsImage: avatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            #endif
        } else {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DS.ColorToken.primary)
                .frame(width: 44, height: 44)
                .background(DS.ColorToken.primary.opacity(0.12), in: Circle())
        }
    }
}
