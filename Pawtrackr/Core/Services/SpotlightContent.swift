//
//  SpotlightContent.swift
//  Pawtrackr
//
//  The pure half of Spotlight: identifiers, what an item says, and when the
//  app may index at all. SpotlightIndexer does the I/O; everything here is a
//  value-in, value-out function so it can be unit-tested.
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Identifiers

/// A Spotlight item's unique identifier: "client-<uuid>" or "pet-<uuid>".
/// The same strings come back in `CSSearchableItemActivityIdentifier` when
/// the user taps a result, so indexing and deep links share this one parser.
enum SpotlightIdentifier: Hashable, Sendable {
    case client(UUID)
    case pet(UUID)

    static let clientPrefix = "client-"
    static let petPrefix = "pet-"
    static let clientDomain = "com.pawtrackr.clients"
    static let petDomain = "com.pawtrackr.pets"

    /// Parses an identifier Spotlight handed back. Anything that isn't exactly
    /// a known prefix followed by a UUID is rejected.
    init?(_ rawValue: String) {
        if rawValue.hasPrefix(Self.clientPrefix),
           let uuid = UUID(uuidString: String(rawValue.dropFirst(Self.clientPrefix.count))) {
            self = .client(uuid)
        } else if rawValue.hasPrefix(Self.petPrefix),
                  let uuid = UUID(uuidString: String(rawValue.dropFirst(Self.petPrefix.count))) {
            self = .pet(uuid)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .client(let uuid): return Self.clientPrefix + uuid.uuidString
        case .pet(let uuid): return Self.petPrefix + uuid.uuidString
        }
    }

    var uuid: UUID {
        switch self {
        case .client(let uuid), .pet(let uuid): return uuid
        }
    }

    var domainIdentifier: String {
        switch self {
        case .client: return Self.clientDomain
        case .pet: return Self.petDomain
        }
    }

    var contentURL: URL? {
        switch self {
        case .client(let uuid): return URL(string: "pawtrackr://client/\(uuid.uuidString)")
        case .pet(let uuid): return URL(string: "pawtrackr://pet/\(uuid.uuidString)")
        }
    }
}

// MARK: - Snapshots

/// What Spotlight needs from a Client, copied out on the model's own thread so
/// the indexer's queue never touches a SwiftData object.
struct SpotlightClientSnapshot: Equatable, Sendable {
    var id: UUID
    var firstName: String
    var lastName: String
    var phone: String?
    var email: String?
    var petNames: [String]

    init(id: UUID, firstName: String, lastName: String, phone: String?, email: String?, petNames: [String]) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.petNames = petNames
    }

    init(client: Client) {
        self.init(
            id: client.uuid,
            firstName: client.firstName,
            lastName: client.lastName,
            phone: client.phone,
            email: client.email,
            petNames: (client.pets ?? []).filter { $0.archivedAt == nil }.map(\.name)
        )
    }
}

/// What Spotlight needs from a Pet, including the owner's name and phone so a
/// search for the owner's number finds the pet too.
struct SpotlightPetSnapshot: Equatable, Sendable {
    var id: UUID
    var name: String
    var species: Species
    var gender: PetGender
    var breed: String?
    var color: String?
    var ownerFirstName: String?
    var ownerLastName: String?
    var ownerPhone: String?
    /// The stored thumbnail only. The full photo is never handed to Spotlight:
    /// a rebuild would otherwise hold every original image of the book at once.
    var thumbnailData: Data?

    init(
        id: UUID,
        name: String,
        species: Species,
        gender: PetGender,
        breed: String?,
        color: String?,
        ownerFirstName: String?,
        ownerLastName: String?,
        ownerPhone: String?,
        thumbnailData: Data?
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.gender = gender
        self.breed = breed
        self.color = color
        self.ownerFirstName = ownerFirstName
        self.ownerLastName = ownerLastName
        self.ownerPhone = ownerPhone
        self.thumbnailData = thumbnailData
    }

    init(pet: Pet) {
        let owner = pet.owner
        self.init(
            id: pet.uuid,
            name: pet.name,
            species: pet.species,
            gender: pet.gender,
            breed: pet.breed,
            color: pet.color,
            ownerFirstName: owner?.firstName,
            ownerLastName: owner?.lastName,
            ownerPhone: owner?.phone,
            thumbnailData: pet.thumbnailData
        )
    }
}

// MARK: - Item content

/// Everything one Spotlight result shows or matches on.
struct SpotlightItemContent: Equatable, Sendable {
    var identifier: SpotlightIdentifier
    var title: String
    var description: String
    var keywords: [String]
    /// Shown by Spotlight as callable numbers and matched by digit searches.
    var phoneNumbers: [String]
    var thumbnailData: Data?
}

enum SpotlightContentBuilder {
    /// `(key, English fallback) -> text`. Production reads the app's language
    /// override; tests pass a specific .lproj bundle.
    typealias Localizer = (_ key: String, _ value: String) -> String

    static let appLocalizer: Localizer = { key, value in
        AppLocalization.localized(key, value: value)
    }

    // MARK: Client

    /// "Client · 2 pets · (555) 123-4567", with the phone in `phoneNumbers`
    /// and its digit forms in `keywords`.
    static func clientContent(_ client: SpotlightClientSnapshot, localized: Localizer = appLocalizer) -> SpotlightItemContent {
        let fullName = joinedName(first: client.firstName, last: client.lastName)
        let title = fullName.isEmpty
            ? localized("insights.lapsed.unnamed_client", "Unnamed client")
            : fullName
        let kind = localized("spotlight.client.kind", "Client")

        let petCount = client.petNames.count
        let petsText: String
        switch petCount {
        case 0:
            petsText = localized("spotlight.client.no_pets", "No pets")
        case 1:
            petsText = localized("spotlight.client.one_pet", "1 pet")
        default:
            petsText = String(format: localized("spotlight.client.pets_fmt", "%d pets"), petCount)
        }

        let phone = trimmedNonEmpty(client.phone)
        let email = trimmedNonEmpty(client.email)
        var descriptionParts = [kind, petsText]
        if let phone {
            descriptionParts.append(PhoneUtils.display(phone) ?? phone)
        } else if let email {
            descriptionParts.append(email)
        }

        var keywords = [
            "client", "customer", "owner", kind,
            fullName, client.firstName, client.lastName
        ]
        if let phone { keywords += phoneKeywords(for: phone) }
        if let email { keywords.append(email) }
        keywords += client.petNames

        return SpotlightItemContent(
            identifier: .client(client.id),
            title: title,
            description: descriptionParts.joined(separator: " · "),
            keywords: uniqueKeywords(keywords),
            phoneNumbers: phone.map(phoneNumbers(for:)) ?? [],
            thumbnailData: nil
        )
    }

    // MARK: Pet

    /// "Golden Retriever · Dog · Owner: Ava Martinez". The owner's phone is in
    /// `keywords` so "5551234" finds the pet as well as the owner.
    static func petContent(_ pet: SpotlightPetSnapshot, localized: Localizer = appLocalizer) -> SpotlightItemContent {
        let speciesName: String
        switch pet.species {
        case .dog: speciesName = localized("species.dog", "Dog")
        case .cat: speciesName = localized("species.cat", "Cat")
        }
        let genderName: String
        switch pet.gender {
        case .male: genderName = localized("gender.male", "Male")
        case .female: genderName = localized("gender.female", "Female")
        }

        let petName = pet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let breed = trimmedNonEmpty(pet.breed)
        let ownerName = joinedName(first: pet.ownerFirstName ?? "", last: pet.ownerLastName ?? "")
        let ownerPhone = trimmedNonEmpty(pet.ownerPhone)

        var descriptionParts: [String] = []
        if let breed { descriptionParts.append(breed) }
        descriptionParts.append(speciesName)
        if !ownerName.isEmpty {
            descriptionParts.append(String(format: localized("spotlight.pet.owner_fmt", "Owner: %@"), ownerName))
        }

        var keywords = [
            "pet", "grooming", "animal",
            petName, speciesName, genderName,
            breed ?? "", pet.color ?? "",
            ownerName, pet.ownerFirstName ?? "", pet.ownerLastName ?? ""
        ]
        if let ownerPhone { keywords += phoneKeywords(for: ownerPhone) }

        return SpotlightItemContent(
            identifier: .pet(pet.id),
            title: petName.isEmpty ? speciesName : petName,
            description: descriptionParts.joined(separator: " · "),
            keywords: uniqueKeywords(keywords),
            phoneNumbers: [],
            thumbnailData: pet.thumbnailData
        )
    }

    // MARK: Phones

    /// E.164 and the national display form for a US number; the stored text
    /// as typed when PhoneUtils can't read it.
    static func phoneNumbers(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let e164 = PhoneUtils.toE164(trimmed) else { return [trimmed] }
        return uniqueKeywords([e164, PhoneUtils.display(trimmed, includeExtension: false) ?? ""])
    }

    /// Every form someone might type: as stored, E.164, "(555) 123-4567",
    /// all digits, the 10 national digits, and the last four.
    static func phoneKeywords(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var tokens = [trimmed]
        if let e164 = PhoneUtils.toE164(trimmed) { tokens.append(e164) }
        if let display = PhoneUtils.display(trimmed, includeExtension: false) { tokens.append(display) }
        let digits = String(trimmed.filter(\.isASCIIDigit))
        if !digits.isEmpty {
            tokens.append(digits)
            if digits.count == 11, digits.first == "1" {
                tokens.append(String(digits.dropFirst()))
            }
            if digits.count >= 7 {
                tokens.append(String(digits.suffix(4)))
            }
        }
        return uniqueKeywords(tokens)
    }

    // MARK: Item

    static func searchableItem(for content: SpotlightItemContent) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = content.title
        attributes.displayName = content.title
        attributes.contentDescription = content.description
        attributes.keywords = content.keywords
        if !content.phoneNumbers.isEmpty {
            attributes.phoneNumbers = content.phoneNumbers
            attributes.supportsPhoneCall = true
        }
        if let thumbnail = content.thumbnailData {
            attributes.thumbnailData = thumbnail
        }
        attributes.relatedUniqueIdentifier = content.identifier.rawValue
        attributes.contentURL = content.identifier.contentURL
        return CSSearchableItem(
            uniqueIdentifier: content.identifier.rawValue,
            domainIdentifier: content.identifier.domainIdentifier,
            attributeSet: attributes
        )
    }

    // MARK: Helpers

    static func uniqueKeywords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func joinedName(first: String, last: String) -> String {
        [first, last]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - Privacy policy

/// Whether Pawtrackr may put clients and pets in Spotlight.
///
/// Product choice: Spotlight shows client names, phone numbers and pet photos
/// on the Home Screen search without unlocking the app. When App Lock is on
/// AND this device has a PIN (the only state in which the lock really
/// engages, see `PinLockGate` and `AppLockProtectionStatus`), Pawtrackr
/// removes all its items and indexes nothing. Turning the lock off (or losing
/// the PIN) re-indexes the whole book. To flip the product choice, change
/// this one function.
enum SpotlightPrivacyPolicy {
    static func allowsIndexing(isLockEnabled: Bool, isPINSet: Bool) -> Bool {
        !(isLockEnabled && isPINSet)
    }
}

extension AppSettings {
    var spotlightAllowsIndexing: Bool {
        SpotlightPrivacyPolicy.allowsIndexing(isLockEnabled: isLockEnabled, isPINSet: isPINSet)
    }
}

// MARK: - Index state machine

/// What the index was last left as, persisted so a launch knows whether the
/// index matches the current format and privacy setting.
enum SpotlightIndexState: Equatable, Sendable {
    /// Every Pawtrackr item was removed because the privacy policy said so.
    case cleared
    /// A full rebuild in `format` finished.
    case built(format: Int)

    init?(storedValue: String?) {
        guard let storedValue else { return nil }
        if storedValue == "cleared" {
            self = .cleared
        } else if storedValue.hasPrefix("built."), let format = Int(storedValue.dropFirst("built.".count)) {
            self = .built(format: format)
        } else {
            return nil
        }
    }

    var storedValue: String {
        switch self {
        case .cleared: return "cleared"
        case .built(let format): return "built.\(format)"
        }
    }
}

enum SpotlightIndexAction: Equatable, Sendable {
    case none
    case removeAll
    case rebuild
}

enum SpotlightIndexPlan {
    /// Bump when the item content changes so existing books are rebuilt once.
    /// 2 = phone numbers/keywords, owner phone on pets, localized descriptions.
    static let currentFormat = 2

    /// What to do when the privacy policy is (re)published. `previous` is nil
    /// for the first publish of this process.
    static func onPolicyChange(previous: Bool?, current: Bool, stored: SpotlightIndexState?) -> SpotlightIndexAction {
        if !current {
            switch previous {
            case .some(false):
                return .none
            case .some(true):
                // This process may have indexed edits since the last clear,
                // whatever the stored state says.
                return .removeAll
            case .none:
                // First publish of a launch: an earlier launch may already
                // have cleared the index for the same reason.
                return stored == .cleared ? .none : .removeAll
            }
        }
        // Lock turned off (or the PIN went away) while running: rebuild now.
        // The first publish of a launch leaves rebuilding to the launch check,
        // which runs once the local store is ready.
        return previous == false ? .rebuild : .none
    }

    /// What the launch check does once the container is ready.
    static func atLaunch(allowsIndexing: Bool, stored: SpotlightIndexState?) -> SpotlightIndexAction {
        guard allowsIndexing else {
            return stored == .cleared ? .none : .removeAll
        }
        return stored == .built(format: currentFormat) ? .none : .rebuild
    }
}
