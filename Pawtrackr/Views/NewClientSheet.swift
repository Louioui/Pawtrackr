//
//  NewClientSheet.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NewClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    // Owner
    @State private var first = ""
    @State private var last  = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var emergency = ""

    // Pets buffer (at least one)
    @State private var pets: [TempPet] = [TempPet(index: 1)]

    var body: some View {
        NavigationStack {
            List {
                // MARK: Owner Info
                Section("Owner Information") {
                    TextField("First Name *", text: $first)
                    #if os(iOS)
                        .textContentType(.givenName)
                        .autocapitalization(.words)
                    #endif
                    TextField("Last Name *", text: $last)
                    #if os(iOS)
                        .textContentType(.familyName)
                        .autocapitalization(.words)
                    #endif
                    TextField("Phone *", text: $phone)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    #endif
                    TextField("Email (optional)", text: $email)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    #endif
                    TextField("Address (optional)", text: $address)
                    #if os(iOS)
                        .textContentType(.fullStreetAddress)
                    #endif
                    TextField("Emergency Contact (optional)", text: $emergency)
                }

                // MARK: Pet Info
                Section {
                    HStack {
                        Text("Pet Information").font(.headline)
                        Spacer()
                        Text("Add at least one").foregroundStyle(.secondary).font(.footnote)
                    }
                }

                ForEach($pets) { $p in
                    DisclosureGroup {
                        // Photo picker (optional) – replaces the icon when present
                        HStack(spacing: 12) {
                            ImagePicker(imageData: $p.photoData, allowsEditing: true, maxDimension: 2048, jpegQuality: 0.8) {
                                PetAvatar(photoData: p.photoData, species: p.species, gender: p.gender)
                            }
                            VStack(alignment: .leading) {
                                Text("Tap to add photo").font(.caption).foregroundStyle(.secondary)
                                Text("JPEG auto‑resized for storage").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)

                        TextField("Pet Name *", text: $p.name)

                        Picker("Species", selection: $p.species) {
                            Text("Dog").tag(Species.dog)
                            Text("Cat").tag(Species.cat)
                        }

                        Picker("Gender", selection: $p.gender) {
                            Text("Male").tag(PetGender.male)
                            Text("Female").tag(PetGender.female)
                            Text("Unknown").tag(PetGender.unknown)
                        }

                        TextField("Breed (optional)", text: $p.breed)
                        TextField("Color (optional)", text: $p.color)

                        // Extra fields (captured for future use; uncomment assignments below when your model includes them)
                        TextField("Health Issues (optional)", text: $p.health)
                        TextField("Behavior Tags (comma-separated, optional)", text: $p.behaviorCSV)

                        TextField("Notes (optional)", text: $p.notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    } label: {
                        HStack(spacing: 10) {
                            PetAvatar(photoData: p.photoData, species: p.species, gender: p.gender, size: 28)
                            Text(p.name.isEmpty ? "Pet #\(p.index)" : p.name).fontWeight(.medium)
                            Spacer()
                        }
                    }
                }

                Button {
                    pets.append(TempPet(index: pets.count + 1))
                } label: {
                    Label("Add Another Pet", systemImage: "plus")
                }
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle("Add New Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createClient() }
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Validation
    private var isValid: Bool {
        !first.trimmed.isEmpty &&
        !last.trimmed.isEmpty &&
        isValidUSPhone(phone) &&
        pets.contains { !$0.name.trimmed.isEmpty }
    }

    // MARK: - Actions
    private func createClient() {
        guard let e164 = normalizeUSPhone(phone) else {
            return
        }
        // Create Client
        let client = Client(firstName: first.trimmed,
                            lastName: last.trimmed,
                            phone: e164)
        if !email.trimmed.isEmpty { client.email = email.trimmed }
        if !address.trimmed.isEmpty { client.address = address.trimmed }
        if !emergency.trimmed.isEmpty { client.emergencyContact = emergency.trimmed }

        // Create Pets
        pets.forEach { tp in
            guard !tp.name.trimmed.isEmpty else { return }
            let pet = Pet(name: tp.name.trimmed, species: tp.species)
            pet.gender = tp.gender
            if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.trimmed }
            if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed }
            if !tp.notes.trimmed.isEmpty { pet.notes = tp.notes.trimmed }
            if let data = tp.photoData { pet.photoData = data }

            // If your Pet model later adds these properties, uncomment:
            // if !tp.health.trimmed.isEmpty { pet.health = tp.health.trimmed }
            // let tags = tp.behaviorCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            // if !tags.isEmpty { pet.behaviorTags = tags }

            pet.owner = client
        }

        // Persist
        ctx.insert(client)
        do {
            try ctx.save()
            dismiss()
        } catch {
            // You can present a user-facing alert here if desired
            print("Save error:", error)
        }
    }

    /// Digits-only helper
    private func digitsOnly(_ s: String) -> String { s.filter(\.isNumber) }

    /// Normalize a US phone number to E.164 (+1XXXXXXXXXX). Returns nil if invalid.
    private func normalizeUSPhone(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = digitsOnly(trimmed)
        var d = digits

        // Allow 11 digits starting with US country code "1"
        if d.count == 11, d.first == "1" {
            d.removeFirst()
        }

        // Require exactly 10 digits at this point
        guard d.count == 10 else { return nil }

        // Basic NANP sanity: area code and exchange cannot start with 0 or 1
        let areaFirst = d.first!
        let exchangeFirst = d.dropFirst(3).first!
        guard areaFirst >= "2" && areaFirst <= "9",
              exchangeFirst >= "2" && exchangeFirst <= "9" else {
            return nil
        }

        return "+1" + d
    }

    /// Boolean check for UI gating
    private func isValidUSPhone(_ raw: String) -> Bool {
        normalizeUSPhone(raw) != nil
    }
}

// MARK: - Temp Pet buffer
private struct TempPet: Identifiable {
    let id = UUID()
    var index: Int
    var name = ""
    var species: Species = .dog
    var gender: PetGender = .unknown
    var breed = ""
    var color = ""
    var health = ""          // free-text, stored later when Pet has this property
    var behaviorCSV = ""     // “Calm, Cooperative”, stored later when Pet has tags
    var notes = ""
    var photoData: Data? = nil
}

// MARK: - Small helpers
private struct PetAvatar: View {
    var photoData: Data?
    var species: Species
    var gender: PetGender
    var size: CGFloat = 56

    var body: some View {
        #if os(macOS)
        if let data = photoData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            SpeciesAndGenderIcons.badge(for: species, gender: gender, size: size)
        }
        #else
        if let data = photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            SpeciesAndGenderIcons.badge(for: species, gender: gender, size: size)
        }
        #endif
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
