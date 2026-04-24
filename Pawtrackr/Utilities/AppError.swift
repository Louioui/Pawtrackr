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
            return "Database Error: \(message)"
        case .validation(let error):
            return error.localizedDescription
        case .network(let message):
            return "Network Error: \(message)"
        case .authentication(let message):
            return "Authentication Error: \(message)"
        case .unknown(let message):
            return "An unexpected error occurred: \(message)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .database:
            return "The local database encountered an issue."
        case .validation:
            return "The information provided is invalid."
        case .network:
            return "There was a problem connecting to the service."
        case .authentication:
            return "You are not authorized to perform this action."
        case .unknown:
            return "Something went wrong."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .database:
            return "Try restarting the app. If the problem persists, contact support."
        case .validation:
            return "Please check the fields and try again."
        case .network:
            return "Please check your internet connection and try again."
        case .authentication:
            return "Please log in again."
        case .unknown:
            return "Try again later."
        }
    }
}
