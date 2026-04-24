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
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date
    
    /// The display name for the service (e.g., "Full Groom").
    @Attribute var name: String
    
    /// The category this service belongs to.
    @Attribute var category: Category?
    
    /// The name of an SF Symbol to display next to the service.
    var systemIcon: String?

    /// The default price for the service. This can be overridden on a per-visit basis.
    var basePrice: Decimal {
        didSet {
            if basePrice < 0 {
                basePrice = .zero
            }
        }
    }
    
    /// An estimated duration in minutes, useful for scheduling.
    var defaultDurationMinutes: Int?
    
    /// If `false`, this service will not appear in selection lists for new visits.
    var isEnabled: Bool

    /// If `true`, this service is considered a package deal.
    var isPackage: Bool

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
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.systemIcon = systemIcon?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.basePrice = basePrice?.roundedMoney() ?? .zero
        self.defaultDurationMinutes = defaultDurationMinutes.map { max(0, $0) }
        self.isEnabled = isEnabled
        self.isPackage = isPackage
    }

    // MARK: - Derived
    
    /// The price to use by default when this service is added to a visit.
    var effectiveBasePrice: Decimal { basePrice }
    
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
        self.basePrice = newPrice?.roundedMoney() ?? .zero
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
    }
}


// MARK: - Seed Data & Previews
extension Service {
    // Packages
    static let fullPackage  = Service(name: "Full Package",  category: .package, systemIcon: "sparkles", isPackage: true)
    static let basicPackage = Service(name: "Basic Package", category: .package, systemIcon: "archivebox.fill", isPackage: true)
    static let spaPackage   = Service(name: "Spa Package",   category: .package, systemIcon: "leaf.fill", isPackage: true)

    // Main Services
    static let bath         = Service(name: "Bath",     category: .groom, systemIcon: "shower.fill")
    static let haircut      = Service(name: "Haircut",  category: .groom, systemIcon: "scissors")

    // Add-Ons
    static let deshedding   = Service(name: "De-shedding",          category: .addOn, systemIcon: "line.3.crossed.swirl.circle.fill")
    static let analGlands   = Service(name: "Anal Glands Expression", category: .addOn, systemIcon: "dot.circle")
    static let faceGrooming = Service(name: "Face Grooming",        category: .addOn, systemIcon: "mustache.fill")
    static let pawTrim      = Service(name: "Paw Trim",             category: .addOn, systemIcon: "pawprint.fill")
    static let hygieneTrim  = Service(name: "Hygiene Area Trim",    category: .addOn, systemIcon: "person.fill.viewfinder")
    static let knotsFee     = Service(name: "Knots and Matting Fee",  category: .addOn, systemIcon: "exclamationmark.triangle.fill")
    static let fleaAndTick  = Service(name: "Flea & Ticks Treatment", category: .addOn, systemIcon: "ladybug.fill")
    static let hairDye      = Service(name: "Hair Dye",             category: .addOn, systemIcon: "paintpalette.fill")
}
