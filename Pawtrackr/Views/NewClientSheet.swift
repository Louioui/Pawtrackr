
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
                            Text("Capture the owner, an emergency contact, and at least one pet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Owner").font(.subheadline.weight(.semibold))
                        inputField("First Name *", text: $viewModel.first)
                            .textInputAutocapitalization(.words)
                        inputField("Last Name *", text: $viewModel.last)
                            .textInputAutocapitalization(.words)
                        inputField("Phone *", text: $viewModel.phone)
                            .keyboardType(.phonePad)
                            .onChange(of: viewModel.phone) {
                                let digits = viewModel.phone.filter(\.isNumber)
                                let clampedDigits = String(digits.prefix(10))
                                let formatted = PhoneUtils.formatAsYouType(clampedDigits, includeExtension: false)
                                if viewModel.phone != formatted {
                                    viewModel.phone = formatted
                                }
                            }
                        inputField("Email", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        inputField("Address", text: $viewModel.address)
                            .textInputAutocapitalization(.words)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Emergency Contacts").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.addContact()
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        if viewModel.contacts.isEmpty {
                            Text("Add at least one emergency contact so you can reach an owner quickly.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($viewModel.contacts) { $contact in
                                VStack(alignment: .leading, spacing: 8) {
                                    inputField("Name", text: $contact.name)
                                        .textInputAutocapitalization(.words)
                                    inputField("Phone", text: $contact.phone)
                                        .keyboardType(.phonePad)
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
                            Text("Pets").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                viewModel.addPet()
                            } label: {
                                Label("Add Pet", systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                        if viewModel.pets.isEmpty {
                            Text("Add at least one pet to create this client.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach($viewModel.pets) { $pet in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Spacer()
                                    ImagePicker(imageData: $pet.photoData) {
                                        VStack(alignment: .center, spacing: 12) {
                                            AvatarView(
                                                .pet(
                                                    species: pet.species,
                                                    gender: pet.gender,
                                                    name: pet.name,
                                                    imageData: pet.photoData
                                                ),
                                                size: .lg
                                            )
                                            Text("Choose Photo")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.bottom, 10)

                                inputField("Pet Name *", text: $pet.name)
                                    .textInputAutocapitalization(.words)
                                Picker("Species", selection: $pet.species) {
                                    ForEach(Species.allCases) { species in
                                        Text(species.rawValue.capitalized).tag(species)
                                    }
                                }
                                Picker("Gender", selection: $pet.gender) {
                                    Text("Male").tag(PetGender.male as PetGender?)
                                    Text("Female").tag(PetGender.female as PetGender?)
                                }

                                HStack {
                                    Image(systemName: "cross.case.fill")
                                        .foregroundStyle(.secondary)
                                    TextField("Health Notes (optional)", text: $pet.health)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.ColorToken.border, lineWidth: 1)
                                )
                                
                                Toggle("Set Birthdate", isOn: $pet.hasBirthdate.animation())
                                if pet.hasBirthdate {
                                    DatePicker("Birthdate", selection: $pet.birthdate, in: ...Date(), displayedComponents: .date)
                                }
                            }
                            .padding()
                            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding()
        }
        .background(DS.ColorToken.background.ignoresSafeArea())
        .navigationTitle("New Client")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.createClient()
                    if !viewModel.showAlert && !viewModel.showDuplicateAlert {
                        dismiss()
                    }
                } label: {
                    Label("Create", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(viewModel.isSaving)
            }
        }
        .alert("Cannot Create Client", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertText)
        }
        .alert("Client Exists", isPresented: $viewModel.showDuplicateAlert) {
            Button("Open") {
                if let id = viewModel.duplicateClientID {
                    NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [ClientOpenKey.clientID.rawValue: id])
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A client with this phone number already exists. Would you like to open their profile?")
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
