//
//  Service.swift
//  Pawtrackr
//
//  SwiftData model for a catalog service (e.g., Bath, Trim, Nails).
//  - This represents the canonical service definition.
//  - When added to a visit, its name and price are snapshotted into a `VisitItem`.
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 8/28/25.
//

import Foundation
import SwiftData

@Model
final class Service {
    // MARK: - Properties
    // Non-optional properties have defaults for CloudKit compatibility.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModifiedBy: UUID = DeviceIdentity.currentID

    /// The display name for the service (e.g., "Full Groom").
    var name: String = ""

    /// The category this service belongs to.
    var category: Category?

    /// The name of an SF Symbol to display next to the service.
    var systemIcon: String?

    /// The default price for the service. This can be overridden on a per-visit basis.
    var basePrice: Decimal? {
        didSet {
            if let basePrice, basePrice < 0 {
                self.basePrice = .zero
            }
        }
    }
    
    /// An estimated duration in minutes, useful for scheduling.
    var defaultDurationMinutes: Int?
    
    /// If `false`, this service will not appear in selection lists for new visits.
    var isEnabled: Bool = true

    /// If `true`, this service is considered a package deal.
    var isPackage: Bool = false

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \VisitItem.service) var visitItems: [VisitItem]? = []

    // MARK: - Init
    init(name: String,
         category: Category? = nil,
         systemIcon: String? = nil,
         basePrice: Decimal? = nil,
         defaultDurationMinutes: Int? = nil,
         isEnabled: Bool = true,
         isPackage: Bool = false)
    {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.lastModifiedBy = DeviceIdentity.currentID
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.systemIcon = systemIcon?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.basePrice = basePrice?.roundedMoney()
        self.defaultDurationMinutes = defaultDurationMinutes.map { max(0, $0) }
        self.isEnabled = isEnabled
        self.isPackage = isPackage
    }

    // MARK: - Derived
    
    /// The price to use by default when this service is added to a visit.
    var effectiveBasePrice: Decimal { basePrice ?? .zero }
    
    // MARK: - Mutating API (explicitly updates timestamps)
    func rename(_ newName: String) {
        self.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        didUpdate()
    }

    func setCategory(_ newCategory: Category?) {
        self.category = newCategory
        didUpdate()
    }

    func setSystemIcon(_ newSymbol: String?) {
        self.systemIcon = newSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        didUpdate()
    }

    func setBasePrice(_ newPrice: Decimal?) {
        self.basePrice = newPrice?.roundedMoney()
        didUpdate()
    }

    func setDefaultDurationMinutes(_ minutes: Int?) {
        self.defaultDurationMinutes = minutes.map { max(0, $0) }
        didUpdate()
    }

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        didUpdate()
    }
    
    // MARK: - Private Helpers
    
    private func didUpdate() {
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
    }
}

extension Service: Identifiable {
    var id: UUID { uuid }
}

extension Service {
    static let obsoleteCheckoutServiceNames: Set<String> = ["basic groom"]

    var isObsoleteCheckoutService: Bool {
        Self.obsoleteCheckoutServiceNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

// MARK: - Nested Category Enum
extension Service {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case groom = "Grooming"
        case addOn = "Add-on"
        case care = "Special Care"
        case package = "Package"
        
        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .groom:
                return AppLocalization.localized("service.category.groom", value: rawValue)
            case .addOn:
                return AppLocalization.localized("service.category.add_on", value: rawValue)
            case .care:
                return AppLocalization.localized("service.category.care", value: rawValue)
            case .package:
                return AppLocalization.localized("service.category.package", value: rawValue)
            }
        }
    }
}

enum DefaultServiceCatalog {
    struct Definition {
        let englishName: String
        let localizationKey: String
        let category: Service.Category?
        let icon: String?
        let isPackage: Bool

        var localizedName: String {
            AppLocalization.localized(localizationKey, value: englishName)
        }
    }

    static let definitions: [Definition] = [
        Definition(englishName: "Full Package", localizationKey: "service.default.full_package", category: .package, icon: "sparkles", isPackage: true),
        Definition(englishName: "Basic Package", localizationKey: "service.default.basic_package", category: .package, icon: "archivebox.fill", isPackage: true),
        Definition(englishName: "Spa Package", localizationKey: "service.default.spa_package", category: .package, icon: "leaf.fill", isPackage: true),
        Definition(englishName: "Bath", localizationKey: "service.default.bath", category: .groom, icon: "shower.fill", isPackage: false),
        Definition(englishName: "Haircut", localizationKey: "service.default.haircut", category: .groom, icon: "scissors", isPackage: false),
        Definition(englishName: "De-shedding", localizationKey: "service.default.deshedding", category: .addOn, icon: "line.3.crossed.swirl.circle.fill", isPackage: false),
        Definition(englishName: "Anal Glands Expression", localizationKey: "service.default.anal_glands", category: .addOn, icon: "dot.circle", isPackage: false),
        Definition(englishName: "Face Grooming", localizationKey: "service.default.face_grooming", category: .addOn, icon: "mustache.fill", isPackage: false),
        Definition(englishName: "Paw Trim", localizationKey: "service.default.paw_trim", category: .addOn, icon: "pawprint.fill", isPackage: false),
        Definition(englishName: "Hygiene Area Trim", localizationKey: "service.default.hygiene_area_trim", category: .addOn, icon: "person.fill.viewfinder", isPackage: false),
        Definition(englishName: "Knots and Matting Fee", localizationKey: "service.default.matting_fee", category: .addOn, icon: "exclamationmark.triangle.fill", isPackage: false),
        Definition(englishName: "Flea & Ticks Treatment", localizationKey: "service.default.flea_tick", category: .addOn, icon: "ladybug.fill", isPackage: false),
        Definition(englishName: "Hair Dye", localizationKey: "service.default.hair_dye", category: .addOn, icon: "paintpalette.fill", isPackage: false)
    ]

    static var localizedNamesByEnglishName: [String: String] {
        Dictionary(uniqueKeysWithValues: definitions.map { ($0.englishName, $0.localizedName) })
    }

    static var allKnownLocalizedNamesByEnglishName: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: definitions.map { definition in
            var names = Set([definition.englishName.lowercased()])
            for lprojName in ["en", "es", "es-419"] {
                if let url = Bundle.main.url(forResource: lprojName, withExtension: "lproj"),
                   let bundle = Bundle(url: url) {
                    let localized = bundle.localizedString(forKey: definition.localizationKey, value: definition.englishName, table: nil)
                    names.insert(localized.lowercased())
                }
            }
            return (definition.englishName, names)
        })
    }

    /// Returns the current-language display name for one of Pawtrackr's built-in services.
    static func localizedName(forEnglishName englishName: String) -> String {
        localizedNamesByEnglishName[englishName] ?? englishName
    }

    /// Resolves a known localized built-in service name back to its English seed identity.
    static func englishName(forKnownName serviceName: String) -> String? {
        let normalized = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allKnownLocalizedNamesByEnglishName.first { $0.value.contains(normalized) }?.key
    }
}


// MARK: - Seed Data & Previews
extension Service {
    // Packages
    static let fullPackage  = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Full Package"),  category: .package, systemIcon: "sparkles", isPackage: true)
    static let basicPackage = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Basic Package"), category: .package, systemIcon: "archivebox.fill", isPackage: true)
    static let spaPackage   = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Spa Package"),   category: .package, systemIcon: "leaf.fill", isPackage: true)

    // Main Services
    static let bath         = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Bath"),     category: .groom, systemIcon: "shower.fill")
    static let haircut      = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Haircut"),  category: .groom, systemIcon: "scissors")

    // Add-Ons
    static let deshedding   = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "De-shedding"),             category: .addOn, systemIcon: "line.3.crossed.swirl.circle.fill")
    static let analGlands   = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Anal Glands Expression"), category: .addOn, systemIcon: "dot.circle")
    static let faceGrooming = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Face Grooming"),           category: .addOn, systemIcon: "mustache.fill")
    static let pawTrim      = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Paw Trim"),                category: .addOn, systemIcon: "pawprint.fill")
    static let hygieneTrim  = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Hygiene Area Trim"),       category: .addOn, systemIcon: "person.fill.viewfinder")
    static let knotsFee     = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Knots and Matting Fee"),   category: .addOn, systemIcon: "exclamationmark.triangle.fill")
    static let fleaAndTick  = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Flea & Ticks Treatment"),  category: .addOn, systemIcon: "ladybug.fill")
    static let hairDye      = Service(name: DefaultServiceCatalog.localizedName(forEnglishName: "Hair Dye"),                category: .addOn, systemIcon: "paintpalette.fill")
}
