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

    // Alerts
    @State private var showAlert = false
    @State private var alertText = ""
    @State private var attemptedSubmit = false
    @State private var showInlineErrors = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: Owner Info
                Section("Owner Information") {
                    TextField("First Name *", text: $first)
                    #if os(iOS)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && first.trimmed.isEmpty) {
                        Text("First name is required").font(.caption).foregroundStyle(.red)
                    }
                    TextField("Last Name *", text: $last)
                    #if os(iOS)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && last.trimmed.isEmpty) {
                        Text("Last name is required").font(.caption).foregroundStyle(.red)
                    }
                    TextField("Phone *", text: $phone)
                        .autocorrectionDisabled()
                        .onChange(of: phone) { _, newValue in
                            // Normalize live display using PhoneUtils; if unavailable, keep user input
                            if let pretty = PhoneUtils.display(newValue) { phone = pretty }
                        }
                    #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && PhoneUtils.toE164(phone) == nil) {
                        Text("Enter a valid US phone number").font(.caption).foregroundStyle(.red)
                    }
                    TextField("Email (optional)", text: $email)
                    #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && !email.trimmed.isEmpty && !isValidEmail(email)) {
                        Text("Email looks invalid").font(.caption).foregroundStyle(.red)
                    }
                    TextField("Address (optional)", text: $address)
                    #if os(iOS)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.next)
                    #endif
                    TextField("Emergency Contact (optional)", text: $emergency)
                    #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .submitLabel(.done)
                    #endif
                }

                // MARK: Pet Info
                Section {
                    HStack {
                        Text("Pet Information").font(.headline)
                        Spacer()
                        Text("\(pets.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(.thinMaterial, in: Capsule())
                            .accessibilityLabel("Pet forms \(pets.count)")
                    }
                    HStack {
                        Text("Add at least one (name + gender)")
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }
                }
                if attemptedSubmit && !hasAtLeastOneValidPet {
                    Text("Add at least one pet with a name and selected gender").font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 2)
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
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif
                        if attemptedSubmit && p.name.trimmed.isEmpty {
                            Text("Pet name is required").font(.caption).foregroundStyle(.red)
                        }

                        Picker("Species", selection: $p.species) {
                            Text("Dog").tag(Species.dog)
                            Text("Cat").tag(Species.cat)
                        }

                        Picker("Gender", selection: $p.gender) {
                            Text("Male").tag(PetGender.male)
                            Text("Female").tag(PetGender.female)
                            Text("Unknown").tag(PetGender.unknown)
                        }
                        if attemptedSubmit && p.gender == .unknown {
                            Text("Please choose a gender").font(.caption).foregroundStyle(.red)
                        }

                        TextField("Breed (optional)", text: $p.breed)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif
                        TextField("Color (optional)", text: $p.color)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif

                        // Extra fields (captured for future use; uncomment assignments below when your model includes them)
                        TextField("Health Issues (optional)", text: $p.health)
                        #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                        #endif
                        TextField("Behavior Tags (comma-separated, optional)", text: $p.behaviorCSV)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.next)
                        #endif

                        TextField("Notes (optional)", text: $p.notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                        #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                        #endif
                    } label: {
                        HStack(spacing: 10) {
                            PetAvatar(photoData: p.photoData, species: p.species, gender: p.gender, size: 28)
                            Text(p.name.isEmpty ? "Pet #\(p.index)" : p.name)
                                .fontWeight(.medium)
                                .accessibilityLabel(p.name.isEmpty ? "Pet number \(p.index)" : p.name)
                            Spacer()
                        }
                    }
                }
                .onDelete { indexSet in
                    var indices = Array(indexSet)
                    indices.sort(by: >)
                    for i in indices {
                        if pets.count > 1 {
                            pets.remove(at: i)
                        }
                    }
                    // Re-number remaining pet indices
                    for (i, _) in pets.enumerated() {
                        pets[i].index = i + 1
                    }
                }

                Button {
                    pets.append(TempPet(index: pets.count + 1))
                } label: {
                    Label("Add Another Pet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityHint("Adds a new pet form")
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
                    Button("Create") {
                        attemptedSubmit = true
                        if !createClient() {
                            if alertText.isEmpty { alertText = "Please double‑check the required fields and phone number." }
                            showAlert = true
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Create client")
                    .accessibilityHint("Saves the owner and pet information")
                }
            }
            .alert("Cannot Create Client", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertText)
            }
        }
    }

    // MARK: - Validation
    private var isValid: Bool {
        !first.trimmed.isEmpty &&
        !last.trimmed.isEmpty &&
        (PhoneUtils.toE164(phone) != nil) &&
        (email.trimmed.isEmpty || isValidEmail(email)) &&
        hasAtLeastOneValidPet
    }

    private var hasAtLeastOneValidPet: Bool {
        pets.contains { !$0.name.trimmed.isEmpty && $0.gender != .unknown }
    }

    // MARK: - Actions
    private func createClient() -> Bool {
        guard let e164 = PhoneUtils.toE164(phone) else {
            alertText = "Phone number must be a valid US number (10 digits)."
            return false
        }
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            alertText = "Email address looks invalid."
            return false
        }

        // Optional: normalize emergency contact if present
        var emergencyE164: String? = nil
        if !emergency.trimmed.isEmpty {
            emergencyE164 = PhoneUtils.toE164(emergency)
            if emergencyE164 == nil {
                alertText = "Emergency contact must be a valid US phone number."
                return false
            }
        }

        // Prevent duplicate client by primary phone
        do {
            let desc = FetchDescriptor<Client>(
                predicate: #Predicate { $0.phone == e164 }
            )
            if let existing = try? ctx.fetch(desc), !existing.isEmpty {
                alertText = "A client with this phone number already exists."
                return false
            }
        }

        // Create Client
        let client = Client(firstName: canonicalPersonName(first),
                            lastName: canonicalPersonName(last),
                            phone: e164)
        if !email.trimmed.isEmpty { client.email = email.trimmed.lowercased() }
        if !address.trimmed.isEmpty { client.address = address.trimmed }
        if let emergencyE164 { client.emergencyContact = emergencyE164 }

        // Create Pets
        pets.forEach { tp in
            guard !tp.name.trimmed.isEmpty else { return }
            let pet = Pet(name: tp.name.trimmed, species: tp.species)
            pet.gender = tp.gender
            if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.trimmed }
            if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed }
            if let data = tp.photoData { pet.photoData = data }

            // Consolidate extra fields into the canonical note if your model doesn’t yet have dedicated properties
            var noteParts: [String] = []
            if !tp.notes.trimmed.isEmpty { noteParts.append(tp.notes.trimmed) }
            if !tp.health.trimmed.isEmpty { noteParts.append("Health: \(tp.health.trimmed)") }
            let tags = tp.behaviorCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !tags.isEmpty { noteParts.append("Behavior: \(tags.joined(separator: ", "))") }
            if !noteParts.isEmpty {
                let joined = noteParts.joined(separator: "\n")
                // Prefer `notes` if available, else fall back to `note`
                #if compiler(>=6.0)
                pet.notes = joined
                #else
                pet.note = joined
                #endif
            }

            pet.owner = client
        }

        // Persist
        ctx.insert(client)
        do {
            try ctx.save()
            dismiss()
            return true
        } catch {
            alertText = "Save failed. Please try again.\n\n\(error.localizedDescription)"
            return false
        }
    }

    /// Basic email shape validation (local@domain)
    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Very permissive pattern: at least one char before and after '@' and a dot in the domain
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
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
                .accessibilityLabel("Pet photo")
                .accessibilityAddTraits(.isImage)
        } else {
            SpeciesAndGenderIcons.badge(for: species, gender: gender, size: size)
                .accessibilityLabel("\(species == .dog ? "Dog" : "Cat"), \(gender == .male ? "Male" : (gender == .female ? "Female" : "Gender unknown"))")
        }
        #else
        if let data = photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityLabel("Pet photo")
                .accessibilityAddTraits(.isImage)
        } else {
            SpeciesAndGenderIcons.badge(for: species, gender: gender, size: size)
                .accessibilityLabel("\(species == .dog ? "Dog" : "Cat"), \(gender == .male ? "Male" : (gender == .female ? "Female" : "Gender unknown"))")
        }
        #endif
    }
}


/// Title-cases common name patterns like "o'neil" → "O'Neil"
private func canonicalPersonName(_ raw: String) -> String {
    let base = raw.trimmed.lowercased()
    // Split on spaces and hyphens; capitalize first letters; handle O' prefixes
    let parts = base.split(separator: " ").map { part -> String in
        var p = String(part)
        if p.hasPrefix("o'"), p.count > 2 {
            let idx = p.index(p.startIndex, offsetBy: 2)
            let rest = p[idx...]
            return "O'" + rest.capitalized
        }
        // Hyphenated segments
        return p.split(separator: "-").map { String($0).capitalized }.joined(separator: "-")
    }
    return parts.joined(separator: " ")
}

// MARK: - PhoneUtils shims (reference)
// Phone display/normalization are centralized in PhoneUtils.
// Here we only reference PhoneUtils to keep validation consistent app-wide.
