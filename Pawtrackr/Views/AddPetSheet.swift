//
//  AddPetSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData

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
                                            .overlay(Circle().stroke(selectedGender == .male ? Color.blue.opacity(0.9) : Color.pink.opacity(0.9), lineWidth: 2))
                                    }
                                    #elseif canImport(AppKit)
                                    if let image = NSImage(data: data) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 84, height: 84)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(.white, lineWidth: 2))
                                            .overlay(Circle().stroke(selectedGender == .male ? Color.blue.opacity(0.9) : Color.pink.opacity(0.9), lineWidth: 2))
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
                    TextField("Color (optional)", text: $color)
                }

                Section("Notes") {
                    TextField("Behavior, allergies, instructions…", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .overlay(
                Rectangle()
                    .fill(selectedGender == .male ? Color.blue : Color.pink)
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
                        .disabled(petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedSpecies == nil)
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
        .accessibilityElement(children: .contain)
    }

    private func savePet() {
        guard let species = selectedSpecies else { return }

        let trimmedName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        // ✅ FIXED: Changed 'var' to 'let' to resolve the compiler warning.
        let newPet = Pet(name: trimmedName, species: species, gender: selectedGender)
        let trimmedBreed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBreed.isEmpty { newPet.breed = trimmedBreed }
        if !trimmedColor.isEmpty { newPet.color = trimmedColor }
        if !trimmedNotes.isEmpty { newPet.notes = trimmedNotes }
        newPet.photoData = avatarImageData
        newPet.owner = client

        client.pets.append(newPet)

        modelContext.insert(newPet)
        try? modelContext.save()
        dismiss()
    }
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
