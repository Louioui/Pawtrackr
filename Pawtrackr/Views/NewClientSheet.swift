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
    @State private var emergencyName = ""
    @State private var emergencyPhone = ""

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
                Section(NSLocalizedString("new_client.owner_section", comment: "")) {
                    TextField("new_client.first_name_required", text: $first)
                    #if os(iOS)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && first.trimmed.isEmpty) {
                        Text(NSLocalizedString("new_client.error.first_required", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.last_name_required", text: $last)
                    #if os(iOS)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && last.trimmed.isEmpty) {
                        Text(NSLocalizedString("new_client.error.last_required", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.phone_required", text: $phone)
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
                        Text(NSLocalizedString("new_client.error.phone_invalid", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.email_optional", text: $email)
                    #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && !email.trimmed.isEmpty && !isValidEmail(email)) {
                        Text(NSLocalizedString("new_client.error.email_invalid", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.address_optional", text: $address)
                    #if os(iOS)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.next)
                    #endif
                    TextField("new_client.emergency_name_optional", text: $emergencyName)
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    TextField("new_client.emergency_phone_optional", text: $emergencyPhone)
                        .autocorrectionDisabled()
                        .onChange(of: emergencyPhone) { _, newValue in
                            if let pretty = PhoneUtils.display(newValue) { emergencyPhone = pretty }
                        }
                    #if os(iOS)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .submitLabel(.done)
                    #endif
                }

                // MARK: Pet Info
                Section {
                    HStack {
                        Text(NSLocalizedString("new_client.pets_section", comment: "")).font(.headline)
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
                        Text(NSLocalizedString("new_client.pets_hint", comment: ""))
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }
                }
                if attemptedSubmit && !hasAtLeastOneValidPet {
                    Text(NSLocalizedString("new_client.error.pet_required", comment: "")).font(.caption).foregroundStyle(.red)
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
                        Text(NSLocalizedString("new_client.photo_hint", comment: "")).font(.caption).foregroundStyle(.secondary)
                        Text(NSLocalizedString("new_client.photo_subhint", comment: "")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)

                        TextField("new_client.pet_name_required", text: $p.name)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif
                        if attemptedSubmit && p.name.trimmed.isEmpty {
                            Text(NSLocalizedString("new_client.error.pet_name_required", comment: "")).font(.caption).foregroundStyle(.red)
                        }

                        Picker(NSLocalizedString("new_client.species", comment: ""), selection: $p.species) {
                            Text(NSLocalizedString("species.dog", comment: "")).tag(Species.dog)
                            Text(NSLocalizedString("species.cat", comment: "")).tag(Species.cat)
                        }

                        Picker(NSLocalizedString("new_client.gender", comment: ""), selection: $p.gender) {
                            // Restrict to Male or Female only
                            Text(NSLocalizedString("gender.male", comment: "")).tag(PetGender.male)
                            Text(NSLocalizedString("gender.female", comment: "")).tag(PetGender.female)
                        }

                        TextField("new_client.breed_optional", text: $p.breed)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif
                        TextField("new_client.color_optional", text: $p.color)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                        #endif

                        // Extra fields (captured for future use; uncomment assignments below when your model includes them)
                        TextField("new_client.health_optional", text: $p.health)
                        #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                        #endif
                        TextField("new_client.behavior_optional", text: $p.behaviorCSV)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.next)
                        #endif

                        // Notes removed per request
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

                Button { pets.append(TempPet(index: pets.count + 1)) } label: { Label(NSLocalizedString("new_client.add_pet", comment: ""), systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityHint(NSLocalizedString("new_client.add_pet_a11y", comment: ""))
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle("new_client.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.create") {
                        attemptedSubmit = true
                        if !createClient() {
                            if alertText.isEmpty { alertText = NSLocalizedString("new_client.error.double_check", comment: "") }
                            showAlert = true
                        }
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Create client")
                    .accessibilityHint("Saves the owner and pet information")
                }
            }
            .alert(NSLocalizedString("new_client.cannot_create_title", comment: ""), isPresented: $showAlert) {
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
        pets.contains { !$0.name.trimmed.isEmpty && $0.gender != nil }
    }

    // MARK: - Actions
    private func createClient() -> Bool {
        guard let e164 = PhoneUtils.toE164(phone) else {
            alertText = NSLocalizedString("new_client.error.phone_invalid_long", comment: "")
            return false
        }
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            alertText = NSLocalizedString("new_client.error.email_invalid_long", comment: "")
            return false
        }

        // Optional: normalize emergency contact if present
        var emergencyE164: String? = nil
        if !emergencyPhone.trimmed.isEmpty {
            emergencyE164 = PhoneUtils.toE164(emergencyPhone)
            if emergencyE164 == nil {
                alertText = NSLocalizedString("new_client.error.emergency_invalid", comment: "")
                return false
            }
        }

        // Prevent duplicate client by primary phone
        do {
            let desc = FetchDescriptor<Client>(
                predicate: #Predicate { $0.phone == e164 }
            )
            if let existing = try? ctx.fetch(desc), !existing.isEmpty {
                alertText = NSLocalizedString("new_client.error.duplicate_phone", comment: "")
                return false
            }
        }

        // Create Client
        let client = Client(firstName: canonicalPersonName(first),
                            lastName: canonicalPersonName(last),
                            phone: e164)
        if !email.trimmed.isEmpty { client.email = email.trimmed.lowercased() }
        if !address.trimmed.isEmpty { client.address = address.trimmed }
        if emergencyE164 != nil || !emergencyName.trimmed.isEmpty {
            client.setEmergencyContact(name: emergencyName.trimmed.isEmpty ? nil : emergencyName.trimmed,
                                       phone: emergencyE164)
        }

        // Create Pets
        pets.forEach { tp in
            guard !tp.name.trimmed.isEmpty, let gender = tp.gender else { return }
            let pet = Pet(name: tp.name.trimmed, species: tp.species)
            pet.gender = gender
            if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.trimmed }
            if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed }
            if let data = tp.photoData { pet.photoData = data }

            // Store structured fields directly on the model
            if !tp.health.trimmed.isEmpty { pet.setHealth(tp.health.trimmed) }
            let parsedTags = FormValidators.parseBehaviorTagsCSV(tp.behaviorCSV)
            if !parsedTags.isEmpty { pet.setBehaviorTags(parsedTags) }
            // Notes removed per request

            pet.owner = client
        }

        // Persist
        ctx.insert(client)
        do {
            try ctx.save()
            dismiss()
            return true
        } catch {
            alertText = String(format: NSLocalizedString("common.save_failed", comment: ""), error.localizedDescription)
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
    var gender: PetGender? = .male
    var breed = ""
    var color = ""
    var health = ""          // free-text, stored later when Pet has this property
    var behaviorCSV = ""     // “Calm, Cooperative”, stored later when Pet has tags
    var photoData: Data? = nil
}

// MARK: - Small helpers
private struct PetAvatar: View {
    var photoData: Data?
    var species: Species
    var gender: PetGender?
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
            SpeciesAndGenderIcons.badge(for: species, gender: gender ?? .male, size: size)
                .accessibilityLabel(gender.map { "\(species.displayName), \($0.displayName)" } ?? species.displayName)
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
            SpeciesAndGenderIcons.badge(for: species, gender: gender ?? .male, size: size)
                .accessibilityLabel(gender.map { "\(species.displayName), \($0.displayName)" } ?? species.displayName)
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
// ep validation consistent app-wide.
