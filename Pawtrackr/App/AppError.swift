//
//  AppError.swift
//  Pawtrackr
//
//  Centralized error handling for the application.
//

import Foundation

enum AppError: LocalizedError, Identifiable, Equatable {
    case database(String)
    case validation(ValidationError)
    case network(String)
    case authentication(String)
    case unknown(String)
    
    var id: String {
        switch self {
        case .database(let msg): return "db-\(msg)"
        case .validation(let error): return "val-\(error.id)"
        case .network(let msg): return "net-\(msg)"
        case .authentication(let msg): return "auth-\(msg)"
        case .unknown(let msg): return "unk-\(msg)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .database(let message):
            return String(format: AppLocalization.localized("app_error.database_fmt", value: "Database Error: %@"), message)
        case .validation(let error):
            return error.localizedDescription
        case .network(let message):
            return String(format: AppLocalization.localized("app_error.network_fmt", value: "Network Error: %@"), message)
        case .authentication(let message):
            return String(format: AppLocalization.localized("app_error.authentication_fmt", value: "Authentication Error: %@"), message)
        case .unknown(let message):
            return String(format: AppLocalization.localized("app_error.unknown_fmt", value: "An unexpected error occurred: %@"), message)
        }
    }
    
    var failureReason: String? {
        switch self {
        case .database:
            return AppLocalization.localized("app_error.database_reason", value: "The local database encountered an issue.")
        case .validation:
            return AppLocalization.localized("app_error.validation_reason", value: "The information provided is invalid.")
        case .network:
            return AppLocalization.localized("app_error.network_reason", value: "There was a problem connecting to the service.")
        case .authentication:
            return AppLocalization.localized("app_error.authentication_reason", value: "You are not authorized to perform this action.")
        case .unknown:
            return AppLocalization.localized("app_error.unknown_reason", value: "Something went wrong.")
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .database:
            return AppLocalization.localized("app_error.database_recovery", value: "Try restarting the app. If the problem persists, contact support.")
        case .validation:
            return AppLocalization.localized("app_error.validation_recovery", value: "Please check the fields and try again.")
        case .network:
            return AppLocalization.localized("app_error.network_recovery", value: "Please check your internet connection and try again.")
        case .authentication:
            return AppLocalization.localized("app_error.authentication_recovery", value: "Please log in again.")
        case .unknown:
            return AppLocalization.localized("app_error.unknown_recovery", value: "Try again later.")
        }
    }
}
