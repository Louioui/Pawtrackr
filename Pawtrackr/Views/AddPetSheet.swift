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
    @State private var healthNotes: String = ""
    @State private var hasBirthdate: Bool = false
    @State private var birthdate: Date = Date()

    // Image picking - Corrected to use Data?
    @State private var avatarImageData: Data? = nil

    // Alerts
    @State private var appError: AppError? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Pet card with gender accent
                    VStack(alignment: .leading, spacing: 0) {
                        // Gender accent bar at top
                        Rectangle()
                            .fill(DS.ColorToken.gender(selectedGender))
                            .frame(height: 4)

                        VStack(alignment: .leading, spacing: 16) {
                            // Photo section
                            HStack {
                                Spacer()
                                ImagePicker(imageData: $avatarImageData) {
                                    VStack(alignment: .center, spacing: 8) {
                                        AvatarView(
                                            .pet(
                                                species: selectedSpecies,
                                                gender: selectedGender,
                                                name: petName,
                                                imageData: avatarImageData
                                            ),
                                            size: .lg
                                        )
                                        Text(NSLocalizedString("add_pet.choose_photo", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)

                            // Pet name
                            petInputField(NSLocalizedString("add_pet.name", comment: ""), text: $petName)
                                .accessibilityIdentifier("addPet.name")
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                                .disableAutocorrection(true)

                            // Species picker - segmented style
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("add_pet.species", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker(NSLocalizedString("add_pet.species", comment: ""), selection: Binding($selectedSpecies, replacingNilWith: .dog)) {
                                    Text(Species.dog.displayName).tag(Species.dog as Species)
                                    Text(Species.cat.displayName).tag(Species.cat as Species)
                                }
                                .pickerStyle(.segmented)
                            }

                            // Gender picker - segmented style
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("add_pet.gender", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker(NSLocalizedString("add_pet.gender", comment: ""), selection: $selectedGender) {
                                    Text(PetGender.male.displayName).tag(PetGender.male)
                                    Text(PetGender.female.displayName).tag(PetGender.female)
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
                                    TextField("", text: $breed)
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
                                    TextField("", text: $color)
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
                                Toggle(isOn: $hasBirthdate.animation()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "birthday.cake.fill")
                                            .foregroundStyle(.orange)
                                        Text(NSLocalizedString("add_pet.set_birthdate", comment: ""))
                                    }
                                }
                                if hasBirthdate {
                                    DatePicker(NSLocalizedString("add_pet.birthdate", comment: ""), selection: $birthdate, in: ...Date(), displayedComponents: .date)
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
                                    Text(NSLocalizedString("add_pet.health_notes", comment: ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                TextField("", text: $healthNotes)
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
                .padding()
            }
            .background(DS.ColorToken.background.ignoresSafeArea())
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .navigationTitle(NSLocalizedString("add_pet.title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                        .accessibilityIdentifier("addPet.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) { savePet() }
                        .disabled(petName.trimmed.isEmpty || selectedSpecies == nil)
                        .accessibilityHint(petName.trimmed.isEmpty ? "Enter a pet name to enable save" : "Saves this pet to the client")
                        .accessibilityIdentifier("addPet.save")
                }
            }
            .alert(item: $appError) { error in
                Alert(
                    title: Text(NSLocalizedString("add_pet.unable_to_save", comment: "")),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
        }
#if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
        .accessibilityElement(children: .contain)
    }

    private func petInputField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.ColorToken.border, lineWidth: 1)
            )
    }

    private func savePet() {
        guard let species = selectedSpecies else {
            appError = .validation(.custom(message: NSLocalizedString("add_pet.select_species", comment: "")))
            return
        }
        let trimmedName = canonicalPetName(petName)
        guard !trimmedName.isEmpty else {
            appError = .validation(.custom(message: NSLocalizedString("add_pet.name_empty", comment: "")))
            return
        }

        let newPet = Pet(name: trimmedName, species: species, gender: selectedGender)

        let trimmedBreed = canonicalOptionalWord(breed)
        let trimmedColor = canonicalOptionalWord(color)
        let trimmedHealth = canonicalOptionalWord(healthNotes)

        if let trimmedBreed { newPet.breed = trimmedBreed }
        if let trimmedColor { newPet.color = trimmedColor }
        if let trimmedHealth { newPet.health = trimmedHealth }
        if hasBirthdate { newPet.setBirthdate(birthdate) }

        newPet.photoData = avatarImageData
        newPet.owner = client

        client.pets = (client.pets ?? []) + [newPet]
        modelContext.insert(newPet)

        do {
            try modelContext.save()
            HapticManager.notify(.success)
            dismiss()
        } catch {
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "adding pet")
            appError = .database(NSLocalizedString("add_pet.save_error", comment: "") + "\n\(error.localizedDescription)")
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
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    if let container = try? ModelContainer(for: schema, configurations: config) {
        let c = Client(firstName: "Sarah", lastName: "Johnson", phone: "(555) 123-4567")
        container.mainContext.insert(c)
        return AddPetSheet(client: c)
            .modelContainer(container)
    } else {
        return Text("Preview Unavailable")
    }
}
