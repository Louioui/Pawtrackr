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
            VStack(alignment: .leading, spacing: 10) {
                topRow
                timingRow
                services
                footer
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                IconCircle(size: .md, style: .auto(species: visit.pet?.species, gender: visit.pet?.gender), lineWidth: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.pet?.name ?? "Unknown").font(.subheadline.weight(.semibold))
                    Text("\(visit.pet?.shortDescriptor ?? "") • \(visit.pet?.owner?.fullName ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if visit.isPaid {
                Text("Paid")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green))
                    .foregroundStyle(.white)
            } else if visit.isActive {
                Text("Processing")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
        }
    }

    private var timingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check-in").font(.caption).foregroundStyle(.secondary)
                Text(Formatters.timeOnly.string(from: visit.startedAt)).font(.subheadline.weight(.medium))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Check-out").font(.caption).foregroundStyle(.secondary)
                if let end = visit.endedAt {
                    Text(Formatters.timeOnly.string(from: end)).font(.subheadline.weight(.medium))
                } else {
                    Text("In Progress").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
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
            HStack(spacing: 14) {
                Label(visit.durationString, systemImage: "clock")
                Label(visit.totalCurrencyString, systemImage: "dollarsign.circle")
                if let paymentMethod = visit.payment?.method {
                    Label(paymentMethod.displayName, systemImage: paymentMethod.systemImage)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
