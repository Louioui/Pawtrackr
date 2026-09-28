//
//  LoyaltySimulatorCard.swift
//  Pawtrackr
//

import SwiftUI

struct LoyaltySimulatorCard: View {
    @State private var ticketTotal: Double = 80

    private let tiers: [(points: Int, title: String)] = [
        (50, "Nail Grind"),
        (100, "Blueberry Facial"),
        (150, "15% Off Add-On"),
        (200, "$20 Groom Credit"),
        (500, "Free Basic Groom Credit")
    ]

    private var earnedPoints: Int {
        Int(ticketTotal.rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Loyalty Points", systemImage: "giftcard.fill")
                .font(.headline)

            Text("What are Loyalty Points? Every time a client completes a grooming visit, they earn points based on their spent total, like 1 point per $1 spent. Clients can redeem these points for free add-ons like nail grinds, blueberry facials, or discounts on future grooms.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ticket")
                    Spacer()
                    Text(ticketTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: $ticketTotal, in: 0...200, step: 5)
                    .accessibilityIdentifier("onboarding.loyaltySimulator.slider")
                HStack {
                    Label("\(earnedPoints) points", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("No extra math")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.success)
                }
            }
            .padding(12)
            .background(DS.ColorToken.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(tiers, id: \.points) { tier in
                    Label(tier.title, systemImage: earnedPoints >= tier.points ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(earnedPoints >= tier.points ? DS.ColorToken.success : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
        .padding()
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hairlineBorder(DS.ColorToken.border, cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
