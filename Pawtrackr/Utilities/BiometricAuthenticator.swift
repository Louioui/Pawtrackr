import Foundation
import LocalAuthentication

enum BiometricType {
    case none
    case touchID
    case faceID
}

class BiometricAuthenticator {
    private let context = LAContext()
    private var error: NSError?

    func biometricType() -> BiometricType {
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        default:
            return .none
        }
    }

    func authenticate(completion: @escaping (Bool, Error?) -> Void) {
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }

        let reason = "Log in to your account"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
            DispatchQueue.main.async {
                completion(success, authenticationError)
            }
        }
    }
}
