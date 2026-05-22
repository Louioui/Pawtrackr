//
//  ValidationError.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import Foundation

/// Centralized validation errors for Pawtrackr forms and actions.
/// Conforms to `LocalizedError` so SwiftUI alerts can show user-friendly messages.
public enum ValidationError: LocalizedError, Identifiable, Equatable {
    case emptyField(fieldName: String)
    case invalidPhoneNumber
    case invalidPIN
    case invalidAmount
    case invalidDateRange
    case custom(message: String)

    public var id: String { localizedDescription }

    public var errorDescription: String? {
        switch self {
        case .emptyField(let fieldName):
            return "The field \(fieldName) cannot be left blank."
        case .invalidPhoneNumber:
            return "Please enter a valid phone number."
        case .invalidPIN:
            return "The PIN you entered is not valid."
        case .invalidAmount:
            return "Please enter a valid amount."
        case .invalidDateRange:
            return "The selected date range is invalid."
        case .custom(let message):
            return message
        }
    }
}
