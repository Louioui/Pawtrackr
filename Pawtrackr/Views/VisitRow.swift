//
//  VisitRow.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        // FIX: Use the correct Card initializer.
        Card(
            elevation: .regular,
            accent: .leading(.color(DS.ColorToken.gender(visit.pet?.gender)), thickness: 4)
        ) {
            HStack(alignment: .top, spacing: 12) {
                VStack {
                    AvatarView(.pet(species: visit.pet?.species, gender: visit.pet?.gender, name: visit.pet?.name ?? "Unknown"), size: .md)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    header
                    services
                    footer
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.pet?.owner?.fullName ?? "Unknown Owner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(visit.pet?.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(visit.totalCurrencyString)
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Amount \(visit.totalCurrencyString)")
        }
    }

    @ViewBuilder
    private var services: some View {
        if !visit.items.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(visit.items) { item in
                    // FIX: Replaced 'Pill' with the correct 'Chip' component.
                    Chip(item.displayName, style: .tinted, size: .xs)
                }
            }
        }
    }
    
    private var footer: some View {
        HStack {
            Label(visit.durationString, systemImage: "clock")
            Spacer()
            if let paymentMethod = visit.payment?.method {
                Label(paymentMethod.displayName, systemImage: paymentMethod.systemImage)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}
