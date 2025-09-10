//
//  AddPetSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData
// Design tokens for colors/spacing/typography
import Observation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct AddPetSheet: View {
    // Parent context & dismissal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Target owner
    @Bindable var client: Client

    // Form state
    @State private var petName: String = ""
    @State private var selectedSpecies: Species? = .dog
    @State private var selectedGender: PetGender = .male
    @State private var breed: String = ""
    @State private var color: String = ""
    @State private var notes: String = ""

    // Image picking - Corrected to use Data?
    @State private var avatarImageData: Data? = nil

    // Alerts
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = "Unable to Save"
    @State private var alertMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Photo") {
                    HStack(spacing: 16) {
                        ImagePicker(imageData: $avatarImageData,
                                    allowsEditing: true,
                                    maxDimension: 2048,
                                    jpegQuality: 0.8) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 84, height: 84)

                                if let data = avatarImageData {
                                    #if canImport(UIKit)
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(.white, lineWidth: 2))
                                            .overlay(Circle().stroke(DS.ColorToken.gender(selectedGender), lineWidth: 2))
                                    }
                                    #elseif canImport(AppKit)
                                    if let image = NSImage(data: data) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(.white, lineWidth: 2))
                                            .overlay(Circle().stroke(DS.ColorToken.gender(selectedGender), lineWidth: 2))
                                    }
                                    #endif
                                } else {
                                    Image(systemName: "camera")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel("Add pet photo")
                        Text("Tap photo to choose image")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pet Info") {
                    TextField("Name", text: $petName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)

                    Picker("Species", selection: Binding($selectedSpecies, replacingNilWith: .dog)) {
                        ForEach(Species.allCases, id: \.self) { species in
                            Text(species.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Gender", selection: $selectedGender) {
                        ForEach(PetGender.allCases, id: \.self) { gender in
                            Text(gender.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Breed (optional)", text: $breed)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                    TextField("Color (optional)", text: $color)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                }

                Section("Notes") {
                    TextField("Behavior, allergies, instructions…", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .overlay(
                Rectangle()
                    .fill(DS.ColorToken.gender(selectedGender))
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .top),
                alignment: .top
            )
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .navigationTitle("Add Pet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePet() }
                        .disabled(petName.trimmed.isEmpty || selectedSpecies == nil)
                        .accessibilityHint(petName.trimmed.isEmpty ? "Enter a pet name to enable save" : "Saves this pet to the client")
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
        .accessibilityElement(children: .contain)
    }

    private func savePet() {
        guard let species = selectedSpecies else {
            alertMessage = "Select a species."
            showAlert = true
            return
        }
        let trimmedName = canonicalPetName(petName)
        guard !trimmedName.isEmpty else {
            alertMessage = "Pet name can't be empty."
            showAlert = true
            return
        }

        let newPet = Pet(name: trimmedName, species: species, gender: selectedGender)

        let trimmedBreed = canonicalOptionalWord(breed)
        let trimmedColor = canonicalOptionalWord(color)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedBreed { newPet.breed = trimmedBreed }
        if let trimmedColor { newPet.color = trimmedColor }
        if !trimmedNotes.isEmpty { newPet.notes = trimmedNotes }

        newPet.photoData = avatarImageData
        newPet.owner = client

        client.pets.append(newPet)
        modelContext.insert(newPet)

        do {
            try modelContext.save()
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            dismiss()
        } catch {
            alertMessage = "We couldn't save this pet. Please try again.\n\(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Normalization

/// Title-cases common pet name patterns and trims whitespace.
private func canonicalPetName(_ raw: String) -> String {
    let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !base.isEmpty else { return "" }
    // Handle simple possessives / prefixes as needed later.
    return base.split(separator: " ").map { part in
        part.split(separator: "-").map { seg in
            var s = String(seg)
            if s.count >= 2 {
                let first = s.removeFirst()
                return String(first).uppercased() + s
            }
            return s.uppercased()
        }.joined(separator: "-")
    }.joined(separator: " ")
}

/// Returns a capitalized word/string or nil if the trimmed input is empty.
private func canonicalOptionalWord(_ raw: String) -> String? {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    return t.split(separator: " ").map { String($0).capitalized }.joined(separator: " ")
}

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith defaultValue: Value) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}

#Preview {
    // Lightweight preview with an in-memory model
    let schema = Schema([Client.self, Pet.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let c = Client(firstName: "Sarah", lastName: "Johnson", phone: "(555) 123-4567")
    container.mainContext.insert(c)

    return AddPetSheet(client: c)
        .modelContainer(container)
}
