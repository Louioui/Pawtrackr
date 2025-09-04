

//
//  ClientCard.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI

struct ClientCard: View {
    let client: Client
    
    // IMPROVEMENT: Logic is self-contained within the card.
    private var isInProgress: Bool { client.hasActiveVisit }

    var body: some View {
        // FIX: Use the correct Card initializer with a Card.Accent struct.
        Card(accent: isInProgress ? .top(.color(DS.ColorToken.success)) : nil) {
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
                if let telURL = URL(string: PhoneUtils.telURLString(phone) ?? "") {
                    Link(destination: telURL) {
                        Label("Call \(PhoneUtils.display(phone) ?? phone)", systemImage: "phone.fill")
                    }
                }
                if let smsURL = URL(string: PhoneUtils.smsURLString(phone) ?? "") {
                    Link(destination: smsURL) {
                        Label("Text Message", systemImage: "message.fill")
                    }
                }
                #endif
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(client.fullName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
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
                ForEach(client.pets.prefix(3)) { pet in
                    AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name), size: .sm, ringWidth: 2)
                }
            }
            
            Text(client.pets.map(\.name).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 16)
            
            Spacer()
            timeBadge
        }
    }

    @ViewBuilder
    private var timeBadge: some View {
        // PERFORMANCE: TimelineView efficiently updates the timer without re-rendering the whole list.
        if let activeVisit = client.mostRecentActiveVisit {
            TimelineView(.everyMinute) { context in
                let duration = Formatters.durationString(from: activeVisit.startedAt, to: context.date)
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.success)
                    .fontWeight(.medium)
            }
        } else if let lastEnded = client.mostRecentEndedAt {
            Text("Last visit: \(lastEnded, style: .relative)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
