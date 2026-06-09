

//
//  ClientCard.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI

struct ClientCard: View {
    let client: Client
    var namespace: Namespace.ID? = nil
    
    // IMPROVEMENT: Logic is self-contained within the card.
    private var isInProgress: Bool { client.hasActiveVisit }
    private var needsAttention: Bool { (client.pets ?? []).contains { $0.needsAttention } }
    private var hasMissingInfo: Bool { client.phone == nil || client.email == nil }
    
    @State private var pulse: Bool = false

    var body: some View {
        // FIX: Use the correct Card initializer with a Card.Accent struct.
        let accentColor = isInProgress ? DS.ColorToken.success : (needsAttention ? Color.orange : nil)
        Card(elevation: .regular, accent: accentColor != nil ? .leading(.color(accentColor!), thickness: 4) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                header
                phoneInfo
                petsInfo
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let namespace {
                AvatarView(.client(name: client.fullName), size: .sm)
                    .matchedGeometryEffect(id: "avatar-\(client.id)", in: namespace)
            } else {
                AvatarView(.client(name: client.fullName), size: .sm)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(client.fullName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .id("name-\(client.id)")
            }
            
            Spacer()
            // FIX: Replaced 'Pill' with the correct 'Chip' component.
            if isInProgress {
                Chip.success("In Session")
            } else if needsAttention {
                Chip.warning(NSLocalizedString("clients.needs_attention", value: "Needs Attention", comment: ""))
            } else if hasMissingInfo {
                Chip.info("Missing Info")
            }
        }
    }

    @ViewBuilder
    private var phoneInfo: some View {
        if let phone = client.phone, !phone.isEmpty {
            Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private var petsInfo: some View {
        HStack(alignment: .center) {
            HStack(spacing: -12) { // Tighter stacking for avatars
                ForEach((client.pets ?? []).prefix(3)) { pet in
                    AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name), size: .sm, ringWidth: 2)
                }
            }
            
            Text((client.pets ?? []).map(\.name).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 16)
            
            Spacer()
        }
    }


}
