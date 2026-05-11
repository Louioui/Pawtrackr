

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
    @State private var pulse: Bool = false

    var body: some View {
        // FIX: Use the correct Card initializer with a Card.Accent struct.
        Card(elevation: .regular, accent: isInProgress ? .leading(.color(DS.ColorToken.success), thickness: 4) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                header
                phoneInfo
                petsInfo
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if let phone = client.phone, !phone.isEmpty {
                // FIX: Use correct PhoneUtils methods and guard against iOS-only APIs.
                #if canImport(UIKit)
                if let telStr = PhoneUtils.telURLString(phone), let telURL = URL(string: telStr) {
                    Link(destination: telURL) {
                        Label("Call \(PhoneUtils.display(phone) ?? phone)", systemImage: "phone.fill")
                    }
                }
                if let smsStr = PhoneUtils.smsURLString(phone), let smsURL = URL(string: smsStr) {
                    Link(destination: smsURL) {
                        Label("Text Message", systemImage: "message.fill")
                    }
                }
                #endif
            }
        }
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
                
                if let namespace {
                    // Hidden anchor for name transition if needed
                    Color.clear.frame(width: 0, height: 0)
                        .matchedGeometryEffect(id: "name-\(client.id)", in: namespace)
                }
            }
            
            Spacer()
            // FIX: Replaced 'Pill' with the correct 'Chip' component.
            if isInProgress {
                Chip.success("In Session")
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
