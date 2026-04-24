
//
//  NewClientSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData
import Observation

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
                Card {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.primary)
                            .frame(width: 44, height: 44)
                            .background(DS.ColorToken.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("new_client.capture_hint", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("new_client.owner", comment: "")).font(.subheadline.weight(.semibold))
                        inputField(NSLocalizedString("new_client.first_name", comment: ""), text: $viewModel.first)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                        inputField(NSLocalizedString("new_client.last_name", comment: ""), text: $viewModel.last)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                        inputField(NSLocalizedString("new_client.phone", comment: ""), text: $viewModel.phone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                            .onChange(of: viewModel.phone) {
                                let digits = viewModel.phone.filter(\.isNumber)
                                let clampedDigits = String(digits.prefix(10))
                                let formatted = PhoneUtils.formatAsYouType(clampedDigits, includeExtension: false)
                                if viewModel.phone != formatted {
                                    viewModel.phone = formatted
                                }
                            }
                        inputField(NSLocalizedString("new_client.email", comment: ""), text: $viewModel.email)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            #endif
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        inputField(NSLocalizedString("new_client.address", comment: ""), text: $viewModel.address)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                    }
                }

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
                                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                                    inputField(NSLocalizedString("new_client.contact_phone", comment: ""), text: $contact.phone)
                                        #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                                        .onChange(of: contact.phone) {
                                            let digits = contact.phone.filter(\.isNumber)
                                            let clampedDigits = String(digits.prefix(10))
                                            let formatted = PhoneUtils.formatAsYouType(clampedDigits, includeExtension: false)
                                            if contact.phone != formatted {
                                                contact.phone = formatted
                                            }
                                        }
                                }
                                .padding()
                                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

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
                                // Gender accent bar at top
                                Rectangle()
                                    .fill(DS.ColorToken.gender(pet.gender))
                                    .frame(height: 4)

                                VStack(alignment: .leading, spacing: 16) {
                                    // Photo section
                                    HStack {
                                        Spacer()
                                        ImagePicker(imageData: $pet.photoData) {
                                            VStack(alignment: .center, spacing: 8) {
                                                AvatarView(
                                                    .pet(
                                                        species: pet.species,
                                                        gender: pet.gender,
                                                        name: pet.name,
                                                        imageData: pet.photoData
                                                    ),
                                                    size: .lg
                                                )
                                                Text(NSLocalizedString("new_client.choose_photo", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)

                                    // Pet name
                                    inputField(NSLocalizedString("new_client.pet_name", comment: ""), text: $pet.name)
                                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif

                                    // Species picker - segmented style
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(NSLocalizedString("add_pet.species", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Picker(NSLocalizedString("add_pet.species", comment: ""), selection: $pet.species) {
                                            Text(Species.dog.displayName).tag(Species.dog)
                                            Text(Species.cat.displayName).tag(Species.cat)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    // Gender picker - segmented style
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(NSLocalizedString("add_pet.gender", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Picker(NSLocalizedString("add_pet.gender", comment: ""), selection: $pet.gender) {
                                            Text(PetGender.male.displayName).tag(PetGender.male as PetGender?)
                                            Text(PetGender.female.displayName).tag(PetGender.female as PetGender?)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    // Breed and Color in a row
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "pawprint.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(NSLocalizedString("add_pet.breed", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            TextField("", text: $pet.breed)
                                                #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                                                .disableAutocorrection(true)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(DS.ColorToken.border, lineWidth: 1)
                                                )
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "paintpalette.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(NSLocalizedString("add_pet.color", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            TextField("", text: $pet.color)
                                                #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                                                .disableAutocorrection(true)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(DS.ColorToken.border, lineWidth: 1)
                                                )
                                        }
                                    }

                                    // Birthday section
                                    VStack(alignment: .leading, spacing: 8) {
                                        Toggle(isOn: $pet.hasBirthdate.animation()) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "birthday.cake.fill")
                                                    .foregroundStyle(.orange)
                                                Text(NSLocalizedString("new_client.set_birthdate", comment: ""))
                                            }
                                        }
                                        if pet.hasBirthdate {
                                            DatePicker(NSLocalizedString("new_client.birthdate", comment: ""), selection: $pet.birthdate, in: ...Date(), displayedComponents: .date)
                                                .datePickerStyle(.compact)
                                        }
                                    }
                                    .padding(12)
                                    .background(DS.ColorToken.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    // Health notes
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "cross.case.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.red.opacity(0.8))
                                            Text(NSLocalizedString("new_client.health_notes", comment: ""))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        TextField("", text: $pet.health)
                                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            #endif
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(DS.ColorToken.border, lineWidth: 1)
                                            )
                                    }
                                }
                                .padding()
                            }
                            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.ColorToken.border.opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(DS.ColorToken.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("new_client.new_client", comment: ""))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.createClient()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if viewModel.appError == nil && !viewModel.showDuplicateAlert {
                            dismiss()
                        }
                    }
                } label: {
                    Label(NSLocalizedString("common.create", comment: ""), systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(viewModel.isSaving)
            }
        }
        .alert(item: $viewModel.appError) { error in
            Alert(
                title: Text(NSLocalizedString("new_client.cannot_create_client", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
        .alert(NSLocalizedString("new_client.client_exists", comment: ""), isPresented: $viewModel.showDuplicateAlert) {
            Button(NSLocalizedString("new_client.open", comment: "")) {
                if let id = viewModel.duplicateClientID {
                    NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [ClientOpenKey.clientID.rawValue: id])
                }
                dismiss()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("new_client.client_exists_message", comment: ""))
        }
    }
}

fileprivate func inputField(_ title: String, text: Binding<String>) -> some View {
    TextField(title, text: text)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.ColorToken.border, lineWidth: 1)
        )
}
