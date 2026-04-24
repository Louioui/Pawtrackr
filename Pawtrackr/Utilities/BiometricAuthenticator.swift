import Foundation
import LocalAuthentication

enum BiometricType {
    case none
    case touchID
    case faceID
}

final class BiometricAuthenticator {
    /// Returns the available biometric type on this device.
    /// Creates a fresh LAContext each time to get accurate state.
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .none:
            return .none
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .faceID // Treat Apple Vision Pro optic ID as face-based
        @unknown default:
            return .none
        }
    }

    /// Authenticates the user using biometrics.
    /// Creates a fresh LAContext to avoid reusing invalidated contexts.
    func authenticate(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async {
                completion(false, error)
            }
            return
        }

        let reason = NSLocalizedString("biometric.reason", comment: "Biometric authentication reason")
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
            DispatchQueue.main.async {
                completion(success, authenticationError)
            }
        }
    }

    /// Async/await version of authenticate for modern Swift concurrency.
    @MainActor
    func authenticate() async -> (success: Bool, error: Error?) {
        await withCheckedContinuation { continuation in
            authenticate { success, error in
                continuation.resume(returning: (success, error))
            }
        }
    }
}
