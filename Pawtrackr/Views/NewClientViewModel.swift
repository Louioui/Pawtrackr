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
    enum CreateClientOutcome: Equatable {
        case created
        case duplicateFound
        case failed
    }

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

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let repository: ClientRepositoryProtocol
    
    init(modelContext: ModelContext, repository: ClientRepositoryProtocol? = nil) {
        self.modelContext = modelContext
        self.repository = repository ?? ClientRepository(modelContainer: modelContext.container)
    }

    func addPet() {
        pets.append(TempPet(index: pets.count + 1))
    }
    
    func addContact() {
        contacts.append(TempContact(index: contacts.count + 1))
    }

    func createClient() async -> CreateClientOutcome {
        isSaving = true
        appError = nil

        defer { isSaving = false }

        do {
            try validate()
            
            let e164 = PhoneUtils.toE164(phone)
            if let e164, let existing = try await repository.findClient(byPhone: e164) {
                duplicateClientID = existing
                showDuplicateAlert = true
                return .duplicateFound
            }

            let newPets = pets.compactMap { tp -> NewPetData? in
                guard !tp.name.trimmed.isEmpty, let gender = tp.gender else { return nil }
                return NewPetData(
                    name: tp.name.capitalizedName,
                    species: tp.species,
                    gender: gender,
                    breed: tp.breed.trimmed.isEmpty ? nil : tp.breed.capitalizedName,
                    color: tp.color.trimmed.isEmpty ? nil : tp.color.trimmed.lowercased(),
                    photoData: tp.photoData,
                    health: tp.health.trimmed.isEmpty ? nil : tp.health.trimmed,
                    behaviorTags: Array(tp.behaviorTags),
                    birthdate: tp.hasBirthdate ? tp.birthdate : nil
                )
            }

            let newContacts = contacts.compactMap { c -> NewContactData? in
                let name = c.name.capitalizedName
                let relation = c.relation.trimmed.lowercased()
                let ph = c.phone.trimmed
                guard !name.isEmpty, let e164c = PhoneUtils.toE164(ph) else { return nil }
                return NewContactData(name: name, relation: relation.isEmpty ? nil : relation, phone: e164c)
            }

            let clientID: PersistentIdentifier
            if newPets.isEmpty && newContacts.isEmpty {
                let client = Client(
                    firstName: first.capitalizedName,
                    lastName: last.capitalizedName,
                    phone: e164 ?? "",
                    email: email.trimmed.lowercased()
                )
                client.address = address.trimmed
                modelContext.insert(client)
                try modelContext.save()
                CloudKitMonitor.shared.recordLocalChange("Created client")
                clientID = client.persistentModelID
            } else {
                clientID = try await repository.createClient(
                    firstName: first.capitalizedName,
                    lastName: last.capitalizedName,
                    phone: e164 ?? "",
                    email: email.trimmed.lowercased(),
                    address: address.trimmed,
                    pets: newPets,
                    contacts: newContacts
                )
                CloudKitMonitor.shared.recordLocalChange("Created client with related records")
            }

            NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                ClientDidCreateKey.clientID.rawValue: clientID,
                ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.created.rawValue
            ])
            NotificationCenter.default.post(name: .clientOpenRequested, object: nil, userInfo: [
                ClientOpenKey.clientID.rawValue: clientID
            ])
            
            HapticManager.notify(.success)
            return .created
        } catch let error as ValidationError {
            self.appError = .validation(error)
            return .failed
        } catch {
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "creating client")
            self.appError = .database(error.localizedDescription)
            return .failed
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
