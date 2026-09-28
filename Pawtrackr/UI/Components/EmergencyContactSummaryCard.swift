//
//  EmergencyContactSummaryCard.swift
//  Pawtrackr
//

import SwiftUI

struct EmergencyContactSummaryCard: View {
    let contacts: [EmergencyContact]
    let ownerPhone: String?
    let ownerEmail: String?
    let onAdd: () -> Void
    let onEdit: (EmergencyContact) -> Void
    let onDelete: (EmergencyContact) -> Void

    private var missingItems: [String] {
        var values: [String] = []
        if contacts.isEmpty { values.append("Emergency contact") }
        if (ownerPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.append("Owner phone") }
        if (ownerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.append("Owner email") }
        return values
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Emergency Contacts", systemImage: "cross.case.fill")
                        .font(.headline)
                    Spacer()
                    Button(action: onAdd) {
                        Label("Add Contact", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add emergency contact")
                }

                if !missingItems.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.ColorToken.warning)
                        Text("Missing: \(missingItems.joined(separator: ", "))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.ColorToken.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if contacts.isEmpty {
                    Text("Add a backup person staff can call if the owner is unreachable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(contacts, id: \.uuid) { contact in
                            emergencyContactRow(contact)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("clientDetail.emergencyContacts")
    }

    private func emergencyContactRow(_ contact: EmergencyContact) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "phone.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.ColorToken.success)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(contactSubtitle(contact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let urlString = PhoneUtils.telURLString(contact.phone), let url = URL(string: urlString) {
                    Button {
                        URLOpener.open(url)
                    } label: {
                        Image(systemName: "phone.fill")
                    }
                    .accessibilityLabel("Call \(contact.name)")
                }

                Button {
                    onEdit(contact)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit \(contact.name)")

                Button(role: .destructive) {
                    onDelete(contact)
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete \(contact.name)")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func contactSubtitle(_ contact: EmergencyContact) -> String {
        let phone = PhoneUtils.display(contact.phone) ?? contact.phone
        if let relation = contact.relation?.trimmingCharacters(in: .whitespacesAndNewlines), !relation.isEmpty {
            return "\(relation) • \(phone)"
        }
        return phone
    }
}
