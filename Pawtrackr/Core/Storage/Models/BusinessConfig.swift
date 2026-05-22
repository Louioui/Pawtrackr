//
//  BusinessConfig.swift
//  Pawtrackr
//
//  Model to store business-specific branding and contact information.
//

import Foundation
import SwiftData

@Model
final class BusinessConfig {
    // Default required for CloudKit-backed SwiftData stores.
    var name: String = ""
    var email: String?
    var phone: String?
    var address: String?
    @Attribute(.externalStorage) var logoData: Data?
    var brandAccentColorHex: String = "#007AFF" // Default blue
    var logoPlacement: String = "topLeft"
    var isSetupComplete: Bool = false
    
    init(name: String = "", email: String? = nil, phone: String? = nil, address: String? = nil, logoData: Data? = nil, brandAccentColorHex: String = "#007AFF") {
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.logoData = logoData
        self.brandAccentColorHex = brandAccentColorHex
    }
    
    static var `default`: BusinessConfig {
        BusinessConfig(name: "Pawtrackr Grooming")
    }
}
