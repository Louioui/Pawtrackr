//
//  VisitTimelineRow.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI

struct VisitTimelineRow: View {
    let visit: Visit

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(DS.ColorToken.gender(visit.pet.gender))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

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
                Text(visit.pet.name)
                    .font(.subheadline.weight(.semibold))
                Text(visit.dateRangeString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(visit.totalCurrencyString)
                .font(.subheadline.weight(.semibold))
        }
    }
    
    @ViewBuilder
    private var services: some View {
        if !visit.items.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(visit.items) { item in
                    Chip(item.displayName, style: .tinted, size: .sm)
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
