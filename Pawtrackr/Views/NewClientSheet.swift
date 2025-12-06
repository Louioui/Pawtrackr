
//
//  NewClientSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData

struct NewClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NewClientViewModel

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: NewClientViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Owner Info
                Section(header: Text("Owner Information")) {
                    TextField("First Name *", text: $viewModel.first)
                    TextField("Last Name *", text: $viewModel.last)
                    TextField("Phone *", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                    TextField("Address", text: $viewModel.address)
                }
                
                // MARK: Emergency Contacts
                Section(header: Text("Emergency Contacts")) {
                    ForEach($viewModel.contacts) { $contact in
                        HStack {
                            TextField("Name", text: $contact.name)
                            TextField("Phone", text: $contact.phone)
                                .keyboardType(.phonePad)
                        }
                    }
                    Button("Add Emergency Contact") {
                        viewModel.addContact()
                    }
                }

                // MARK: Pet Info
                Section(header: Text("Pets")) {
                    ForEach($viewModel.pets) { $pet in
                        VStack {
                            TextField("Pet Name *", text: $pet.name)
                            Picker("Species", selection: $pet.species) {
                                ForEach(Species.allCases) { species in
                                    Text(species.rawValue.capitalized).tag(species)
                                }
                            }
                            Picker("Gender", selection: $pet.gender) {
                                Text("Male").tag(PetGender.male as PetGender?)
                                Text("Female").tag(PetGender.female as PetGender?)
                            }
                        }
                    }
                    Button("Add Pet") {
                        viewModel.addPet()
                    }
                }
            }
            .navigationTitle("New Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createClient()
                        if !viewModel.showAlert && !viewModel.showDuplicateAlert {
                            dismiss()
                        }
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
}
