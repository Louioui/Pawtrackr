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
                Section("Owner Information") {
                    TextField("First Name", text: $firstName)
                    #if os(iOS)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    #endif
                    TextField("Last Name", text: $lastName)
                    #if os(iOS)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    #endif
                    TextField("Phone", text: $phone)
                        .autocorrectionDisabled()
                        .onChange(of: phone) { _, newValue in
                            if let pretty = PhoneUtils.display(newValue) { phone = pretty }
                        }
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
                    TextField("Email", text: $email)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    TextField("Address", text: $address)
                    #if os(iOS)
                    .textContentType(.fullStreetAddress)
                    #endif
                }

                // Notes intentionally omitted from client edit per requirements.
            }
            .navigationTitle("Edit Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        attemptedSubmit = true
                        save()
                    }
                    .disabled(!isValid)
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
            appError = .validation(.custom(message: "Email address looks invalid."))
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
            dismiss()
        } catch {
            appError = .database("Save failed. Please try again.\n\n\(error.localizedDescription)")
        }
    }

    private func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
