//
//  NewClientViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData
import Observation
import PhotosUI
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

    // Photo handling
    var photoSelection: PhotosPickerItem? = nil {
        didSet {
            Task { await loadAvatarImage() }
        }
    }
#if os(iOS)
    var avatarImage: UIImage? = nil
#elseif os(macOS)
    var avatarImage: NSImage? = nil
#endif

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

    private func loadAvatarImage() async {
        guard let item = photoSelection else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
#if os(iOS)
            self.avatarImage = UIImage(data: data)
#elseif os(macOS)
            self.avatarImage = NSImage(data: data)
#endif
        }
    }

    func addPet() {
        pets.append(TempPet(index: pets.count + 1))
    }
    
    func addContact() {
        contacts.append(TempContact(index: contacts.count + 1))
    }

    func createClient() async -> CreateClientOutcome {
        Logger.newClient.info("createClient enter: first='\(self.first)' last='\(self.last)' phone='\(self.phone)' isSaving=\(self.isSaving)")
        guard !isSaving else {
            Logger.newClient.warning("createClient ignored because a save is already in progress")
            return .failed
        }
        isSaving = true
        appError = nil

        defer { isSaving = false }

        do {
            try validate()
            Logger.newClient.info("createClient: validation passed")

            let e164 = PhoneUtils.toE164(phone)
            Logger.newClient.info("createClient: e164=\(e164 ?? "nil"); checking duplicates")
            if let e164, let existing = try await repository.findClient(byPhone: e164) {
                Logger.newClient.info("createClient: duplicate found")
                duplicateClientID = existing
                showDuplicateAlert = true
                appError = .validation(.custom(message: NSLocalizedString(
                    "new_client.duplicate_phone",
                    value: "A client with this phone number already exists.",
                    comment: ""
                )))
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

#if os(iOS)
            let avatarData = avatarImage?.jpegData(compressionQuality: 0.8)
#elseif os(macOS)
            let avatarData = avatarImage?.jpegData(compressionQuality: 0.8)
#endif

            let clientID = try await repository.createClient(
                firstName: first.capitalizedName,
                lastName: last.capitalizedName,
                phone: e164 ?? "",
                email: email.trimmed.lowercased(),
                address: address.trimmed,
                photoData: avatarData,
                pets: newPets,
                contacts: newContacts
            )
            Logger.newClient.info("createClient: saved client through repository")

            NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                ClientDidCreateKey.clientID.rawValue: clientID,
                ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.created.rawValue
            ])

            HapticManager.notify(.success)
            Logger.newClient.info("createClient: returning .created")
            return .created
        } catch let error as ValidationError {
            Logger.newClient.error("createClient: validation failed: \(error.localizedDescription)")
            self.appError = .validation(error)
            return .failed
        } catch {
            Logger.newClient.error("createClient: save/db error: \(String(describing: error))")
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
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}

private extension Logger {
    static let newClient = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "NewClient")
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

#if os(macOS)
extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif
