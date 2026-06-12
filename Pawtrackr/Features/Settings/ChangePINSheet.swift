import SwiftUI

struct ChangePINSheet: View {
    @Environment(AppSettings.self) private var appSettings
    @Binding var isPresented: Bool
    @State private var currentPIN: String = ""
    @State private var newPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var errorMessage: String? = nil

    /// No PIN has ever been chosen (e.g. the user finished onboarding passcode-free),
    /// so there is no current PIN to verify — this becomes a "set your first PIN"
    /// flow instead of a change. Prevents a dead-end where the user would have to
    /// guess the default code to set a real one.
    private var isInitialSetup: Bool { appSettings.lastPINChangeDate == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(isInitialSetup
                        ? NSLocalizedString("settings.pin.set", value: "Set PIN", comment: "")
                        : NSLocalizedString("settings.pin.change", value: "Change PIN", comment: "")) {
                    if !isInitialSetup {
                        SecureField(NSLocalizedString("settings.pin.current", value: "Current PIN", comment: ""), text: $currentPIN)
                    }
                    SecureField(NSLocalizedString("settings.pin.new", value: "New PIN", comment: ""), text: $newPIN)
                    SecureField(NSLocalizedString("settings.pin.confirm", value: "Confirm PIN", comment: ""), text: $confirmPIN)
                }
            }
            .navigationTitle(isInitialSetup
                             ? NSLocalizedString("settings.pin.set", value: "Set PIN", comment: "")
                             : NSLocalizedString("settings.pin.change", value: "Change PIN", comment: ""))
            .toolbar {
                Button(NSLocalizedString("common.save", value: "Save", comment: "")) { updatePIN() }
                Button(NSLocalizedString("common.cancel", value: "Cancel", comment: "")) { isPresented = false }
            }
            .alert(NSLocalizedString("common.error", value: "Error", comment: ""), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(NSLocalizedString("common.ok", value: "OK", comment: "")) { }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func updatePIN() {
        if !isInitialSetup {
            guard appSettings.validatePIN(currentPIN) else {
                errorMessage = NSLocalizedString("settings.pin.incorrect", value: "Incorrect PIN", comment: "")
                return
            }
        }
        guard newPIN == confirmPIN else {
            errorMessage = NSLocalizedString("settings.pin.mismatch", value: "PINs do not match", comment: "")
            return
        }
        guard appSettings.changePIN(to: newPIN) else {
            errorMessage = NSLocalizedString("settings.pin.invalid", value: "Enter a 4-digit PIN", comment: "")
            return
        }
        isPresented = false
    }
}
