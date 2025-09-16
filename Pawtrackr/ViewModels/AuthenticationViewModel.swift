
import Foundation
import SwiftData

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func signIn(email: String) {
        let predicate = #Predicate<User> { $0.email == email }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let user = (try? modelContext.fetch(descriptor))?.first {
            currentUser = user
            isAuthenticated = true
        } else {
            // For simplicity, we are creating a new user if one doesn't exist.
            let newUser = User(name: "New User", email: email)
            modelContext.insert(newUser)
            currentUser = newUser
            isAuthenticated = true
        }
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
    }
}
