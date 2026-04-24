//
//  NewClientViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
final class NewClientViewModel {
    var first = ""
    var last  = ""
    var phone = ""
    var email = ""
    var address = ""

    var contacts: [TempContact] = [TempContact(index: 1)]
    var pets: [TempPet] = [TempPet(index: 1)]

    var appError: AppError? = nil
    var isSaving: Bool = false
    var showDuplicateAlert: Bool = false
    var duplicateClientID: PersistentIdentifier? = nil

    @ObservationIgnored private let repository: ClientRepositoryProtocol
    
    init(modelContext: ModelContext, repository: ClientRepositoryProtocol? = nil) {
        self.repository = repository ?? ClientRepository(modelContainer: modelContext.container)
    }

    func addPet() {
        pets.append(TempPet(index: pets.count + 1))
    }
    
    func addContact() {
        contacts.append(TempContact(index: contacts.count + 1))
    }

    func createClient() {
        isSaving = true
        appError = nil
        
        Task {
            do {
                try validate()
                
                let e164 = PhoneUtils.toE164(phone)
                if let e164, let existing = try await repository.findClient(byPhone: e164) {
                    duplicateClientID = existing.persistentModelID
                    showDuplicateAlert = true
                    isSaving = false
                    return
                }

                let client = Client(firstName: first.capitalizedName,
                                    lastName: last.capitalizedName,
                                    phone: e164)
                if !email.trimmed.isEmpty { client.email = email.trimmed.lowercased() }
                if !address.trimmed.isEmpty { client.address = address.trimmed }

                pets.forEach { tp in
                    guard !tp.name.trimmed.isEmpty, let gender = tp.gender else { return }
                    let pet = Pet(name: tp.name.capitalizedName, species: tp.species)
                    pet.gender = gender
                    if !tp.breed.trimmed.isEmpty { pet.breed = tp.breed.capitalizedName }
                    if !tp.color.trimmed.isEmpty { pet.color = tp.color.trimmed.lowercased() }
                    if let data = tp.photoData { pet.photoData = data }
                    if !tp.health.trimmed.isEmpty { pet.setHealth(tp.health.trimmed) }
                    if !tp.behaviorTags.isEmpty { pet.setBehaviorTags(Array(tp.behaviorTags)) }
                    if tp.hasBirthdate { pet.setBirthdate(tp.birthdate) }
                    pet.owner = client
                }

                for c in contacts {
                    let name = c.name.capitalizedName
                    let relation = c.relation.trimmed.lowercased()
                    let ph = c.phone.trimmed
                    guard !name.isEmpty, let e164c = PhoneUtils.toE164(ph) else { continue }
                    let ec = EmergencyContact(name: name, relation: relation.isEmpty ? nil : relation, phone: e164c)
                    ec.owner = client
                    client.emergencyContacts.append(ec)
                }
                
                try await repository.saveClient(client)

                NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                    ClientDidCreateKey.clientID.rawValue: client.persistentModelID,
                    ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.created.rawValue
                ])
                NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [
                    ClientOpenKey.clientID.rawValue: client.persistentModelID
                ])
                
                HapticManager.notify(.success)
                isSaving = false
            } catch let error as ValidationError {
                self.appError = .validation(error)
                isSaving = false
            } catch {
                self.appError = .database(error.localizedDescription)
                isSaving = false
            }
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
        
        // Filter out completely empty pet entries if they exist
        let nonHeroPets = pets.filter { !$0.name.trimmed.isEmpty }
        if nonHeroPets.isEmpty {
            throw ValidationError.custom(message: "Add at least one pet with a name before creating this client.")
        }
        
        // Ensure all pets in the list have names if they have other data
        for (idx, pet) in pets.enumerated() {
            if !pet.name.trimmed.isEmpty && pet.gender == nil {
                throw ValidationError.custom(message: "Please select a gender for \(pet.name.trimmed).")
            }
            // If the user started typing a name, but left it empty, but filled breed or something else
            if pet.name.trimmed.isEmpty && (!pet.breed.trimmed.isEmpty || !pet.color.trimmed.isEmpty) {
                throw ValidationError.custom(message: "Pet #\(idx + 1) needs a name.")
            }
        }
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
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
    var hasBirthdate: Bool = false
    var birthdate: Date = Date()
}

struct TempContact: Identifiable {
    let id = UUID()
    var index: Int
    var name: String = ""
    var relation: String = ""
    var phone: String = ""
}
