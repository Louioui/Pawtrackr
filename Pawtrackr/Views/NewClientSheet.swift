
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

    // Emergency Contacts and Pets (pets optional at creation)
    @State private var contacts: [TempContact] = [TempContact(index: 1)]
    @State private var pets: [TempPet] = []

    // Alerts
    @State private var showAlert = false
    @State private var alertText = ""
    @State private var attemptedSubmit = false
    @State private var showInlineErrors = false
    @State private var invalidFields: [String] = []
    @State private var isSaving: Bool = false
    @State private var showDuplicateAlert: Bool = false
    @State private var duplicateClientID: PersistentIdentifier? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // MARK: Owner Info
                Section {
                    TextField("new_client.first_name_required", text: $first)
                        .id("first")
                        .modifier(Shake(animatableData: CGFloat(invalidFields.contains("first") ? 1 : 0)))
                    #if os(iOS)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && first.trimmed.isEmpty) {
                        Text(NSLocalizedString("new_client.error.first_required", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.last_name_required", text: $last)
                        .id("last")
                        .modifier(Shake(animatableData: CGFloat(invalidFields.contains("last") ? 1 : 0)))
                    #if os(iOS)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                    #endif
                    if (attemptedSubmit && last.trimmed.isEmpty) {
                        Text(NSLocalizedString("new_client.error.last_required", comment: "")).font(.caption).foregroundStyle(.red)
                    }
                    TextField("new_client.phone_required", text: $phone)
                        .id("phone")
                        .modifier(Shake(animatableData: CGFloat(invalidFields.contains("phone") ? 1 : 0)))
                        .autocorrectionDisabled()
                        .onChange(of: phone) { _, newValue in
                            guard !newValue.isEmpty else { return }
                            let formatted = PhoneUtils.formatAsYouType(newValue)
                            if formatted != newValue { phone = formatted }
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
                        .id("email")
                        .modifier(Shake(animatableData: CGFloat(invalidFields.contains("email") ? 1 : 0)))
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
                } header: {
                    Text(NSLocalizedString("new_client.owner_section", comment: ""))
                }

                // MARK: Emergency Contacts
                Section {
                    HStack {
                        Text("Emergency Contacts").font(.headline)
                        Spacer()
                        Button {
                            contacts.append(TempContact(index: contacts.count + 1))
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add emergency contact")
                    }
                    HStack {
                        Text("Add at least one contact we can reach during visits.")
                            .foregroundStyle(.secondary).font(.footnote)
                        Spacer()
                    }
                    ForEach($contacts) { $c in
                        HStack(spacing: 10) {
                            TextField("Name", text: $c.name)
                            TextField("Relation", text: $c.relation)
                            TextField("Phone", text: $c.phone)
                                .onChange(of: c.phone) { _, newValue in
                                    guard !newValue.isEmpty else { return }
                                    let formatted = PhoneUtils.formatAsYouType(newValue)
                                    if formatted != newValue { c.phone = formatted }
                                }
                            #if os(iOS)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                            #endif
                        }
                    }
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
                if attemptedSubmit && !hasAtLeastOneValidPetWithPhoto {
                    Text("At least one pet with a photo is required").font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 2)
                }

                ForEach($pets) { $p in
                    DisclosureGroup {
                        // Photo picker – photo required
                        HStack(spacing: 12) {
                            ImagePicker(imageData: $p.photoData, allowsEditing: true, maxDimension: 2048, jpegQuality: 0.8) {
                                PetAvatar(photoData: p.photoData, species: p.species, gender: p.gender)
                            }
                            .id("pet_photo_\(p.index)")
                            VStack(alignment: .leading) {
                        Text(NSLocalizedString("new_client.photo_hint", comment: "")).font(.caption).foregroundStyle(.secondary)
                        Text(NSLocalizedString("new_client.photo_subhint", comment: "")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        if attemptedSubmit && p.photoData == nil {
                            Text("Pet photo required").font(.caption).foregroundStyle(.red)
                        }

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
                        // Behavior Tags
                        Text("Behavior Tags").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(Pet.BehaviorTag.allCases) { tag in
                                Chip.selectable(
                                    tag.displayName,
                                    isSelected: Binding(
                                        get: { p.behaviorTags.contains(tag.rawValue) },
                                        set: { isSelected, _ in
                                            if isSelected { p.behaviorTags.insert(tag.rawValue) } else { p.behaviorTags.remove(tag.rawValue) }
                                        }
                                    )
                                )
                            }
                        }

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

                Button { pets.append(TempPet(index: pets.count + 1)) } label: { Label(NSLocalizedString("new_client.add_pet", comment: ""), systemImage: "pawprint.fill") }
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
                    Button(action: {
                        attemptedSubmit = true
                        guard !isSaving else { return }
                        if !createClient() {
                            if alertText.isEmpty { alertText = NSLocalizedString("new_client.error.double_check", comment: "") }
                            showAlert = true
                        }
                    }) {
                        if isSaving { ProgressView() } else { Text("common.create") }
                    }
                    .disabled(!isValid || isSaving)
                    .tint(.accentColor)
                    .accessibilityLabel("Create client")
                    .accessibilityHint("Saves the owner and pet information")
                }
            }
            .alert(NSLocalizedString("new_client.cannot_create_title", comment: ""), isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertText)
            }
            .alert("Client exists", isPresented: $showDuplicateAlert) {
                Button("Open", role: .none) {
                    if let id = duplicateClientID {
                        NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [ClientOpenKey.clientID.rawValue: id])
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A client with this phone already exists. Open that client?")
            }
            .onChange(of: scrollTarget) { _, target in
                if let t = target {
                    withAnimation(.easeInOut) { proxy.scrollTo(t, anchor: .center) }
                    DispatchQueue.main.async { scrollTarget = nil }
                }
            }
            }
        }
    }

    // MARK: - Validation
    private var isValid: Bool {
        let phoneOK = phone.trimmed.isEmpty || (PhoneUtils.toE164(phone) != nil)
        return !first.trimmed.isEmpty &&
               !last.trimmed.isEmpty &&
               phoneOK &&
               (email.trimmed.isEmpty || isValidEmail(email))
    }

    private var hasAtLeastOneValidPet: Bool { // no longer required, kept for UI hints
        pets.contains { !$0.name.trimmed.isEmpty && $0.gender != nil }
    }

    private var hasAtLeastOneValidPetWithPhoto: Bool {
        pets.contains { !$0.name.trimmed.isEmpty && $0.gender != nil && $0.photoData != nil }
    }

    // MARK: - Actions
    @State private var scrollTarget: String? = nil

    private func createClient() -> Bool {
        invalidFields.removeAll()

        if first.trimmed.isEmpty {
            invalidFields.append("first")
        }
        if last.trimmed.isEmpty {
            invalidFields.append("last")
        }
        if PhoneUtils.toE164(phone) == nil {
            invalidFields.append("phone")
        }
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            invalidFields.append("email")
        }

        if !hasAtLeastOneValidPetWithPhoto {
            invalidFields.append("pet_photo_1") // Assuming the first pet's photo is the target for scrolling
        }

        if !invalidFields.isEmpty {
            withAnimation(.default) {
                self.attemptedSubmit = true
            }
            scrollTarget = invalidFields.first
            return false
        }

        let e164 = PhoneUtils.toE164(phone)
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            alertText = NSLocalizedString("new_client.error.email_invalid_long", comment: "")
            return false
        }

        // Offer to open existing client if a valid phone matches
        if let e164, let matches = try? ctx.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.phone == e164 })), let existing = matches.first {
            duplicateClientID = existing.persistentModelID
            showDuplicateAlert = true
            return false
        }

        // Create Client
        let client = Client(firstName: canonicalPersonName(first),
                            lastName: canonicalPersonName(last),
                            phone: e164)
        if !email.trimmed.isEmpty { client.email = email.trimmed.lowercased() }
        if !address.trimmed.isEmpty { client.address = address.trimmed }

        // Create Pets (optional)
        pets.forEach { tp in
            guard !tp.name.trimmed.isEmpty, let gender = tp.gender else { return }
            let pet = Pet(name: tp.name.trimmed, species: tp.species)
            pet.gender = gender
            if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.trimmed }
            if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed }
            if let data = tp.photoData { pet.photoData = data }

            // Store structured fields directly on the model
            if !tp.health.trimmed.isEmpty { pet.setHealth(tp.health.trimmed) }
            if !tp.behaviorTags.isEmpty { pet.setBehaviorTags(Array(tp.behaviorTags)) }
            // Notes removed per request

            pet.owner = client
        }

        // Create Emergency Contacts (optional)
        for c in contacts {
            let name = c.name.trimmed
            let relation = c.relation.trimmed
            let ph = c.phone.trimmed
            let anyEntered = !name.isEmpty || !relation.isEmpty || !ph.isEmpty
            guard anyEntered else { continue }
            guard let e164c = PhoneUtils.toE164(ph), !name.isEmpty else { continue }
            let ec = EmergencyContact(name: name, relation: relation.isEmpty ? nil : relation, phone: e164c)
            ec.owner = client
            client.emergencyContacts.append(ec)
        }

        // Persist
        ctx.insert(client)
        do {
            isSaving = true
            try ctx.save()
            // Round‑trip verify by refetching the inserted client; prefer phone lookup if present, else best-effort by name
            var saved: Client? = nil
            if let e164 {
                let checkDesc = FetchDescriptor<Client>(predicate: #Predicate { $0.phone == e164 })
                saved = try (ctx.fetch(checkDesc)).first
            } else {
                let expectedFirst = canonicalPersonName(first)
                let expectedLast = canonicalPersonName(last)
                let checkDesc = FetchDescriptor<Client>(predicate: #Predicate { $0.firstName == expectedFirst && $0.lastName == expectedLast })
                saved = try (ctx.fetch(checkDesc)).first
            }
            if let saved {
                // Ensure canonical values persisted; if not, correct them and save again (strict enforcement)
                let expectedFirst = canonicalPersonName(first)
                let expectedLast = canonicalPersonName(last)
                var changed = false
                if saved.firstName != expectedFirst { saved.setFirstName(expectedFirst); changed = true }
                if saved.lastName != expectedLast { saved.setLastName(expectedLast); changed = true }
                if saved.phone != e164 { saved.setPhone(e164); changed = true }
                if !email.trimmed.isEmpty {
                    let expectedEmail = email.trimmed.lowercased()
                    if saved.email != expectedEmail { saved.setEmail(expectedEmail); changed = true }
                }
                if changed { try ctx.save() }
            }
            // Notify observers to auto-open this client in Client Center
            NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                ClientDidCreateKey.clientID.rawValue: client.persistentModelID,
                ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.created.rawValue
            ])
            HapticManager.notify(.success)
            dismiss()
            isSaving = false
            return true
        } catch {
            alertText = String(format: NSLocalizedString("common.save_failed", comment: ""), error.localizedDescription)
            isSaving = false
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
    var behaviorTags: Set<String> = []     // Set of tags
    var photoData: Data? = nil
}

private struct TempContact: Identifiable {
    let id = UUID()
    var index: Int
    var name: String = ""
    var relation: String = ""
    var phone: String = ""
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
                .overlay(
                    Group { if let g = gender { Circle().stroke(DS.ColorToken.gender(g), lineWidth: 3) } }
                )
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
                .overlay(
                    Group { if let g = gender { Circle().stroke(DS.ColorToken.gender(g), lineWidth: 3) } }
                )
                .accessibilityLabel("Pet photo")
                .accessibilityAddTraits(.isImage)
        }
        else {
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
