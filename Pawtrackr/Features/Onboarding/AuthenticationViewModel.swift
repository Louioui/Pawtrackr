//
//  AuthenticationViewModel.swift
//  Pawtrackr
//
//  Manages user authentication state for the app.
//

import Foundation
import SwiftData
import Observation
import OSLog

@MainActor
@Observable
final class AuthenticationViewModel {
    var currentUser: User?
    var isAuthenticated = false

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
    @discardableResult
    func signInAfterPINValidation() -> Bool {
        signInLocalUser()
    }

    /// Legacy method - validates PIN against AppSettings.appPIN
    /// NOTE: Prefer using PinLockView for PIN validation and call signInAfterPINValidation() on success.
    func signInWithPIN(_ pin: String, appSettings: AppSettings) -> Bool {
        guard pin == appSettings.appPIN else { return false }
        // Propagate the actual outcome — if the model context isn't
        // available (recovery-mode launch), the local user can't be
        // created and we mustn't tell the caller authentication
        // succeeded.
        return signInLocalUser()
    }

    func signIn(email: String) {
        guard let modelContext else { return }
        if let user = fetchUser(byEmail: email) {
            currentUser = user
            isAuthenticated = true
            return
        }
        let newUser = User(name: "New User", email: email)
        modelContext.insert(newUser)
        persist(modelContext, label: "signIn(email:)")
        currentUser = newUser
        isAuthenticated = true
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
    }

    @discardableResult
    func signInAfterUnlock() -> Bool {
        signInLocalUser()
    }

    // MARK: - Private Helpers

    /// Returns true when the local user was found-or-created and the VM
    /// is now in an authenticated state. Returns false in recovery-mode
    /// launches where there is no model context (and therefore no User
    /// table to read from).
    @discardableResult
    private func signInLocalUser() -> Bool {
        guard let modelContext else { return false }
        if let user = fetchUser(byEmail: localEmail) {
            currentUser = user
            isAuthenticated = true
            return true
        }
        let newUser = User(name: "Local User", email: localEmail)
        modelContext.insert(newUser)
        persist(modelContext, label: "signInLocalUser")
        currentUser = newUser
        isAuthenticated = true
        return true
    }

    /// Fetches at most one user matching the given email. The User table is single-row
    /// in practice, so the explicit fetchLimit is defense-in-depth + a hint to SwiftData's
    /// query planner. Errors are logged rather than silently swallowed.
    private func fetchUser(byEmail email: String) -> User? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.email == email })
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Logger.auth.error("User fetch failed for email lookup: \(String(describing: error))")
            return nil
        }
    }

    private func persist(_ context: ModelContext, label: String) {
        do {
            try context.save()
        } catch {
            Logger.auth.error("\(label) save failed: \(String(describing: error))")
        }
    }
}

private extension Logger {
    static let auth = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Auth")
}
