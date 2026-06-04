import SwiftUI

struct ChangePINSheet: View {
    @Environment(AppSettings.self) private var appSettings
    @Binding var isPresented: Bool
    @State private var currentPIN: String = ""
    @State private var newPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Change PIN") {
                    SecureField("Current PIN", text: $currentPIN)
                    SecureField("New PIN", text: $newPIN)
                    SecureField("Confirm PIN", text: $confirmPIN)
                }
            }
            .navigationTitle("Change PIN")
            .toolbar {
                Button("Update") { updatePIN() }
                Button("Cancel") { isPresented = false }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func updatePIN() {
        guard appSettings.validatePIN(currentPIN) else { errorMessage = "Incorrect PIN"; return }
        guard newPIN == confirmPIN else { errorMessage = "PINs do not match"; return }
        guard appSettings.changePIN(to: newPIN) else { errorMessage = "Invalid PIN"; return }
        isPresented = false
    }
}
