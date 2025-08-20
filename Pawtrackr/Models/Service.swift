//
//  Service.swift
//  Pawtrackr
//
//  SwiftData model for a service performed during a visit
//  (e.g., Bath, Trim, Nails). Used for chips in Recent/Pet History,
//  and selected in Checkout.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Service: Identifiable {
    // MARK: - Identity
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Core fields
    /// Display name shown in chips (e.g., “Bath”, “Trim”)
    var name: String

    /// Optional SF Symbol name to show alongside the pill (e.g., "scissors", "shower")
    var systemIcon: String?

    /// Optional default price for the service; UI may override per visit
    var defaultPrice: Decimal?

    /// Whether this service is actively offered (hide from pickers if false)
    var isEnabled: Bool

    // MARK: - Relations

    // MARK: - Init
    init(name: String,
         systemIcon: String? = nil,
         defaultPrice: Decimal? = nil,
         isEnabled: Bool = true)
    {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name
        self.systemIcon = systemIcon
        self.defaultPrice = defaultPrice
        self.isEnabled = isEnabled
    }

    // MARK: - Derived
    var displayName: String { name }

    func touch() { updatedAt = Date() }
}

// MARK: - Presets (optional helpers for seeding)

extension Service {
    static let bath = Service(name: "Bath", systemIcon: "shower")
    static let trim = Service(name: "Trim", systemIcon: "scissors")
    static let nails = Service(name: "Nails", systemIcon: "hand.raised.fill")
    static let ears = Service(name: "Ears", systemIcon: "ear")
    static let teeth = Service(name: "Teeth", systemIcon: "tooth.fill")
    static let deshed = Service(name: "De-shed", systemIcon: "broom.fill")
}
