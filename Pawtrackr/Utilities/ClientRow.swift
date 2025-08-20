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
        HStack(spacing: 12) {
            if let pet = client.pets.sorted(by: { $0.name < $1.name }).first {
                Rectangle()
                    .fill(pet.gender == .male ? Color.blue : Color.pink)
                    .frame(width: 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(client.fullName)
                    .font(.headline)
                    .lineLimit(1)

                if let pet = client.pets.sorted(by: { $0.name < $1.name }).first {
                    Text("\(pet.name) • \(pet.breed ?? pet.species.rawValue.capitalized)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if client.pets.contains(where: { $0.visits.contains(where: { $0.endedAt == nil }) }) {
                    Label("In Session", systemImage: "scissors")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
            #if os(macOS)
                .fill(Color(nsColor: .windowBackgroundColor))
            #else
                .fill(Color(.systemBackground))
            #endif
                .shadow(radius: 2)
        )
        .onTapGesture {
            onTap?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        if let phone = formattedPhone {
            return "\(client.fullName), phone \(phone)" + (inProgress ? ", in progress" : "")
        } else {
            return client.fullName + (inProgress ? ", in progress" : "")
        }
    }

    private var formattedPhone: String? {
        if let phoneRaw = client.phone, !phoneRaw.isEmpty {
            return formatPhoneFallback(phoneRaw)
        }
        return nil
    }

    // Naive inference: any pet with a Visit that has no endedAt means "in progress"
    private static func hasActiveVisit(client: Client) -> Bool {
        for pet in client.pets {
            if pet.visits.contains(where: { $0.endedAt == nil }) { return true }
        }
        return false
    }

    private func formatPhoneFallback(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.suffix(4)
            return "(\(a)) \(b)-\(c)"
        }
        return raw
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
