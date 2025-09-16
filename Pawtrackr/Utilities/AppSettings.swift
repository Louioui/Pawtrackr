
import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @Published var isBiometricLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricLockEnabled, forKey: "isBiometricLockEnabled")
        }
    }

    private let biometricKey = "isBiometricLockEnabled"

    init() {
        // Read initial value from UserDefaults, default to true
        self.isBiometricLockEnabled = UserDefaults.standard.object(forKey: biometricKey) as? Bool ?? true
        // Register default value if not already set
        UserDefaults.standard.register(defaults: [biometricKey: true])
    }
}
