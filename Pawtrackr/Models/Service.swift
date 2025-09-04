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
    var basePrice: Decimal?
    
    /// An estimated duration in minutes, useful for scheduling.
    var defaultDurationMinutes: Int?
    
    /// If `false`, this service will not appear in selection lists for new visits.
    var isEnabled: Bool

    // MARK: - Init
    init(name: String,
         category: Category? = nil,
         systemIcon: String? = nil,
         basePrice: Decimal? = nil,
         defaultDurationMinutes: Int? = nil,
         isEnabled: Bool = true)
    {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.systemIcon = systemIcon?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.basePrice = basePrice?.roundedMoney()
        self.defaultDurationMinutes = defaultDurationMinutes.map { max(0, $0) }
        self.isEnabled = isEnabled
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
    }
}

// MARK: - Nested Category Enum
extension Service {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case groom = "Grooming"
        case addOn = "Add-on"
        case care = "Special Care"
        
        var id: String { rawValue }
    }
}


// MARK: - Seed Data & Previews
extension Service {
    static let bath   = Service(name: "Bath",    category: .groom, systemIcon: "shower.fill",        basePrice: 45, defaultDurationMinutes: 45)
    static let trim   = Service(name: "Trim",    category: .groom, systemIcon: "scissors",           basePrice: 35, defaultDurationMinutes: 30)
    static let nails  = Service(name: "Nails",   category: .addOn, systemIcon: "hand.raised.fill",   basePrice: 15, defaultDurationMinutes: 10)
    static let ears   = Service(name: "Ears",    category: .addOn, systemIcon: "ear.and.waveform",   basePrice: 12, defaultDurationMinutes: 10)
    static let teeth  = Service(name: "Teeth",   category: .addOn, systemIcon: "mouth.fill",         basePrice: 10, defaultDurationMinutes: 10)
    static let deshed = Service(name: "De-shed", category: .care,  systemIcon: "line.3.crossed.swirl.circle.fill", basePrice: 25, defaultDurationMinutes: 25)
}
