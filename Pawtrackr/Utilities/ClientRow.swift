//
//  ClientRow.swift
//  Pawtrackr
//
//  Reusable row for Clients list.
//  Shows: owner name, phone, optional "In Progress" badge when any pet is checked in,
//  and stacked pet avatars (dog/cat, blue=male, pink=female). Tappable via onTap.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ClientRow: View {
    let client: Client
    var inProgress: Bool
    var onTap: (() -> Void)?

    init(client: Client, inProgress: Bool? = nil, onTap: (() -> Void)? = nil) {
        self.client = client
        // If explicit flag not provided, infer from any active visit among this client's pets
        if let inProgress = inProgress {
            self.inProgress = inProgress
        } else {
            self.inProgress = ClientRow.hasActiveVisit(client: client)
        }
        self.onTap = onTap
    }

    var body: some View {
        let primaryPet = client.pets.sorted(by: { $0.name < $1.name }).first
        Card(
            elevation: .regular,
            accent: inProgress ? .leading(.color(DS.ColorToken.success), thickness: 4) : nil
        ) {
            HStack(spacing: 12) {
                // Avatars (up to 3 pets)
                HStack(spacing: -8) {
                    ForEach(Array(client.pets.sorted(by: { $0.name < $1.name }).prefix(3)), id: \.persistentModelID) { pet in
                        IconCircle(size: .sm, style: .auto(species: pet.species, gender: pet.gender), lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(client.fullName)
                        .font(.headline)
                        .lineLimit(1)

                    if let pet = primaryPet {
                        Text("\(pet.name) • \(pet.breed ?? pet.species.rawValue.capitalized)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        // Phone actions (Call + SMS) with graceful fallback to plain text
                        if let phone = formattedPhone {
                            if let tel = PhoneUtils.telURLString(phone), let sms = PhoneUtils.smsURLString(phone),
                               let telURL = URL(string: tel), let smsURL = URL(string: sms) {
                                HStack(spacing: 10) {
                                    Link(destination: telURL) {
                                        Image(systemName: "phone.fill")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Call \(phone)")

                                    Link(destination: smsURL) {
                                        Image(systemName: "message.fill")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Text \(phone)")
                                }
                            } else {
                                Label(phone, systemImage: "phone")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if inProgress {
                            Text(NSLocalizedString("status.in_session", comment: ""))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DS.ColorToken.success, in: Capsule())
                                .foregroundStyle(.white)
                                .accessibilityLabel(Text(NSLocalizedString("a11y.in_session", comment: "")))
                        }
                    }
                }
                Spacer()
            }
        }
        .onTapGesture { onTap?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        if let phone = formattedPhone {
            return "\(client.fullName), phone \(phone)" + (inProgress ? ", in session" : "")
        } else {
            return client.fullName + (inProgress ? ", in session" : "")
        }
    }

    private var formattedPhone: String? {
        guard let phoneRaw = client.phone, !phoneRaw.isEmpty else { return nil }
        return PhoneUtils.display(phoneRaw)
    }

    // Naive inference: any pet with a Visit that has no endedAt means "in progress"
    private static func hasActiveVisit(client: Client) -> Bool {
        for pet in client.pets {
            if pet.visits.contains(where: { $0.endedAt == nil }) { return true }
        }
        return false
    }
}

// MARK: - Preview

struct ClientRow_Previews: PreviewProvider {
    static var previews: some View {
        // Minimal fakes for preview only
        let owner = Client(firstName: "Sarah", lastName: "Johnson", phone: "5551234567")
        let max = Pet(name: "Max", species: .dog)
        max.gender = .male
        let bella = Pet(name: "Bella", species: .dog)
        bella.gender = .female
        let kitty = Pet(name: "Mimi", species: .cat)
        kitty.gender = .female
        owner.pets = [max, bella, kitty]

        return VStack(spacing: 12) {
            ClientRow(client: owner, inProgress: true)
            ClientRow(client: owner, inProgress: false)
        }
        .padding()
#if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
#else
        .background(Color(.systemGroupedBackground))
#endif
        .previewLayout(.sizeThatFits)
    }
}
