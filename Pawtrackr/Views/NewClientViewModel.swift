//
//  NewClientViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData

@MainActor
class NewClientViewModel: ObservableObject {
    @Published var first = ""
    @Published var last  = ""
    @Published var phone = ""
    @Published var email = ""
    @Published var address = ""

    @Published var contacts: [TempContact] = [TempContact(index: 1)]
    @Published var pets: [TempPet] = []

    @Published var showAlert = false
    @Published var alertText = ""
    @Published var isSaving: Bool = false
    @Published var showDuplicateAlert: Bool = false
    @Published var duplicateClientID: PersistentIdentifier? = nil
    
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func addPet() {
        pets.append(TempPet(index: pets.count + 1))
    }
    
    func addContact() {
        contacts.append(TempContact(index: contacts.count + 1))
    }

    func createClient() {
        isSaving = true
        do {
            try validate()
            
            let e164 = PhoneUtils.toE164(phone)
            if let e164, let existing = try? modelContext.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.phone == e164 })).first {
                duplicateClientID = existing.persistentModelID
                showDuplicateAlert = true
                isSaving = false
                return
            }

            let client = Client(firstName: canonicalPersonName(first),
                                lastName: canonicalPersonName(last),
                                phone: e164)
            if !email.trimmed.isEmpty { client.email = email.trimmed.lowercased() }
            if !address.trimmed.isEmpty { client.address = address.trimmed }

            pets.forEach { tp in
                guard !tp.name.trimmed.isEmpty, let gender = tp.gender else { return }
                let pet = Pet(name: tp.name.trimmed, species: tp.species)
                pet.gender = gender
                if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.trimmed }
                if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed }
                if let data = tp.photoData { pet.photoData = data }
                if !tp.health.trimmed.isEmpty { pet.setHealth(tp.health.trimmed) }
                if !tp.behaviorTags.isEmpty { pet.setBehaviorTags(Array(tp.behaviorTags)) }
                pet.owner = client
            }

            for c in contacts {
                let name = c.name.trimmed
                let relation = c.relation.trimmed
                let ph = c.phone.trimmed
                guard !name.isEmpty, let e164c = PhoneUtils.toE164(ph) else { continue }
                let ec = EmergencyContact(name: name, relation: relation.isEmpty ? nil : relation, phone: e164c)
                ec.owner = client
                client.emergencyContacts.append(ec)
            }
            
            modelContext.insert(client)
            try modelContext.save()

            NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                ClientDidCreateKey.clientID.rawValue: client.persistentModelID,
                ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.created.rawValue
            ])
            NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [
                ClientOpenKey.clientID.rawValue: client.persistentModelID
            ])
            
            HapticManager.notify(.success)
            isSaving = false
        } catch {
            alertText = error.localizedDescription
            showAlert = true
            isSaving = false
        }
    }

    private func validate() throws {
        if first.trimmed.isEmpty {
            throw ValidationError.custom(message: "First name is required.")
        }
        if last.trimmed.isEmpty {
            throw ValidationError.custom(message: "Last name is required.")
        }
        if !phone.trimmed.isEmpty && PhoneUtils.toE164(phone) == nil {
            throw ValidationError.custom(message: "Please enter a valid phone number.")
        }
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            throw ValidationError.custom(message: "Please enter a valid email address.")
        }
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func canonicalPersonName(_ raw: String) -> String {
        let base = raw.trimmed.lowercased()
        let parts = base.split(separator: " ").map { part -> String in
            let p = String(part)
            if p.hasPrefix("o'"), p.count > 2 {
                let idx = p.index(p.startIndex, offsetBy: 2)
                let rest = p[idx...]
                return "O'" + rest.capitalized
            }
            return p.split(separator: "-").map { String($0).capitalized }.joined(separator: "-")
        }
        return parts.joined(separator: " ")
    }
}

// Temporary structs for form data
struct TempPet: Identifiable {
    let id = UUID()
    var index: Int
    var name = ""
    var species: Species = .dog
    var gender: PetGender? = .male
    var breed = ""
    var color = ""
    var health = ""
    var behaviorTags: Set<String> = []
    var photoData: Data? = nil
}

struct TempContact: Identifiable {
    let id = UUID()
    var index: Int
    var name: String = ""
    var relation: String = ""
    var phone: String = ""
}
