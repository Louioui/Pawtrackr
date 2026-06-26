//
//  EditClientSheet.swift
//  Pawtrackr
//
//  Allows editing owner/contact info for an existing client.
//

import SwiftUI
import SwiftData

struct EditClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    let client: Client

    // Editable fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var address: String = ""

    // Alerts
    @State private var appError: AppError? = nil
    @State private var attemptedSubmit = false

    init(client: Client) {
        self.client = client
        // State is initialized in .onAppear to ensure latest values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("new_client.owner_section", comment: "")) {
                    TextField(NSLocalizedString("new_client.first_name", comment: ""), text: $firstName)
                        .accessibilityIdentifier("editClient.firstName")
                        .textLengthLimit($firstName, to: TextInputLimits.name)
                    #if os(iOS)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    #endif
                    TextField(NSLocalizedString("new_client.last_name", comment: ""), text: $lastName)
                        .accessibilityIdentifier("editClient.lastName")
                        .textLengthLimit($lastName, to: TextInputLimits.name)
                    #if os(iOS)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    #endif
                    TextField(NSLocalizedString("new_client.phone", comment: ""), text: $phone)
                        .accessibilityIdentifier("editClient.phone")
                        .phoneFieldFormatting($phone)
                        .textLengthLimit($phone, to: TextInputLimits.phone)
                    TextField(NSLocalizedString("new_client.email", comment: ""), text: $email)
                        .accessibilityIdentifier("editClient.email")
                        .textLengthLimit($email, to: TextInputLimits.email)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    TextField(NSLocalizedString("new_client.address", comment: ""), text: $address)
                        .accessibilityIdentifier("editClient.address")
                        .textLengthLimit($address, to: TextInputLimits.address)
                    #if os(iOS)
                    .textContentType(.fullStreetAddress)
                    #endif
                }

                // Notes intentionally omitted from client edit per requirements.
            }
            .navigationTitle(NSLocalizedString("client_details.edit", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { dismiss() }
                        .accessibilityIdentifier("editClient.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        attemptedSubmit = true
                        save()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("editClient.save")
                }
            }
            .alert(item: $appError) { error in
                Alert(
                    title: Text(NSLocalizedString("common.error", comment: "")),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
            .onAppear(perform: loadFromClient)
        }
    }

    private func loadFromClient() {
        firstName = client.firstName
        lastName = client.lastName
        phone = client.phone.flatMap { PhoneUtils.display($0) } ?? ""
        email = client.email ?? ""
        address = client.address ?? ""
        // Notes not editable here.
    }

    private var isValid: Bool {
        !firstName.trimmed.isEmpty &&
        !lastName.trimmed.isEmpty &&
        (phone.trimmed.isEmpty || PhoneUtils.toE164(phone) != nil) &&
        (email.trimmed.isEmpty || isValidEmail(email))
    }

    private func save() {
        var e164: String? = nil
        if !phone.trimmed.isEmpty {
            guard let valid = PhoneUtils.toE164(phone) else {
                appError = .validation(.invalidPhoneNumber)
                return
            }
            e164 = valid
        }
        if !email.trimmed.isEmpty && !isValidEmail(email) {
            appError = .validation(.custom(message: NSLocalizedString("new_client.error.email_invalid_long", comment: "")))
            return
        }

        // Apply updates
        client.setFirstName(firstName)
        client.setLastName(lastName)
        client.setPhone(e164)
        client.setEmail(email.trimmed.isEmpty ? nil : email.trimmed)
        client.setAddress(address.trimmed.isEmpty ? nil : address.trimmed)
        // Notes not modified here.

        do {
            try ctx.save()
            CloudKitMonitor.shared.recordLocalChange("Saved client")
            dismiss()
        } catch {
            appError = .database(String(format: NSLocalizedString("common.save_failed", comment: ""), error.localizedDescription))
        }
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
