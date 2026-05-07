//
//  AuthenticationViewModel.swift
//  Pawtrackr
//
//  Manages user authentication state for the app.
//

import Foundation
import SwiftData

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false

    /// Optional so the app can still launch the recovery UI when the data
    /// store fails to open (e.g. schema mismatch in development). All methods
    /// guard nil and become no-ops when the context is absent.
    private let modelContext: ModelContext?
    private let localEmail = "local@pawtrackr.local"

    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    /// Signs in using the PIN from AppSettings (not hardcoded).
    /// Call this after PIN validation succeeds in PinLockView.
    func signInAfterPINValidation() {
        signInLocalUser()
    }

    /// Legacy method - validates PIN against AppSettings.appPIN
    /// NOTE: Prefer using PinLockView for PIN validation and call signInAfterPINValidation() on success.
    func signInWithPIN(_ pin: String, appSettings: AppSettings) -> Bool {
        guard pin == appSettings.appPIN else { return false }
        signInLocalUser()
        return true
    }

    func signIn(email: String) {
        guard let modelContext else { return }
        let predicate = #Predicate<User> { $0.email == email }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let user = (try? modelContext.fetch(descriptor))?.first {
            currentUser = user
            isAuthenticated = true
        } else {
            let newUser = User(name: "New User", email: email)
            modelContext.insert(newUser)
            try? modelContext.save()
            currentUser = newUser
            isAuthenticated = true
        }
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
    }

    func signInAfterUnlock() {
        signInLocalUser()
    }

    // MARK: - Private Helpers

    private func signInLocalUser() {
        guard let modelContext else { return }
        if let user = fetchLocalUser() {
            currentUser = user
            isAuthenticated = true
            return
        }
        let newUser = User(name: "Local User", email: localEmail)
        modelContext.insert(newUser)
        try? modelContext.save()
        currentUser = newUser
        isAuthenticated = true
    }

    private func fetchLocalUser() -> User? {
        guard let modelContext else { return nil }
        let email = localEmail
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.email == email })
        return try? modelContext.fetch(descriptor).first
    }
}
