//
//  PetCard.swift
//  Pawtrackr
//
//  Created by mac on 8/28/25.
//

import SwiftUI
import SwiftData

/// Compact, tappable card that shows a pet, its current session state, and quick actions.
struct PetCard: View {
    // MARK: - Inputs
    let pet: Pet
    /// If a visit is in progress for this pet, pass it here (nil when idle)
    let activeVisit: Visit?
    let onViewDetails: () -> Void
    let onCheckIn: () -> Void
    let onCheckOut: () -> Void

    // MARK: - State / Environment
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Derived
    private var isActive: Bool { activeVisit?.endedAt == nil && activeVisit != nil }

    private var elapsedString: String {
        guard let v = activeVisit else { return "" }
        // If the visit has ended somehow, show a range; otherwise duration
        if let end = v.endedAt { return Formatters.dateRangeString(from: v.startedAt, to: end) }
        return Formatters.durationString(from: v.startedAt, to: .now)
    }

    // MARK: - View
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .md)

                VStack(alignment: .leading, spacing: 6) {
                    // Title + badge
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pet.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isActive { inProgressBadge }
                    }

                    // Subline (breed / color)
                    if let breed = pet.breed, !breed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(breed)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Timer / last visit line
                    if isActive {
                        Label(elapsedString, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(DS.ColorToken.success)
                            .accessibilityLabel("Checked in for \(elapsedString)")
                    } else if let last = pet.visits.filter({ $0.isCompleted }).sorted(by: { $0.sortKeyDate > $1.sortKeyDate }).first {
                        Text("Last Visit: \(last.sortKeyDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Actions
                    HStack(spacing: 8) {
                        if isActive {
                            Button(role: .none, action: onCheckOut) {
                                Label("Check Out", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DS.ColorToken.success)
                        } else {
                            Button(action: onCheckIn) {
                                Label("Check In", systemImage: "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(action: onViewDetails) {
                            Label("View Details", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
        // Top accent line using DS gender color (replaces old Card initializer params)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.ColorToken.gender(pet.gender))
                .frame(height: 3)
        }
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(DS.ColorToken.success)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .onChange(of: scenePhase) { _, phase in
            // When returning to foreground, snap any durations to now so the timer text is fresh
            if phase == .active && isActive {
                // Trigger a small redraw by touching an ephemeral state if you add one later.
                // For now, the computed `elapsedString` uses .now and will naturally refresh on next tick.
            }
        }
    }

    // MARK: - Subviews
    private var inProgressBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(DS.ColorToken.success).frame(width: 6, height: 6).accessibilityHidden(true)
            Text("In Session").font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.ColorToken.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(DS.ColorToken.success)
        .accessibilityLabel("In session")
    }

    private var accessibilitySummary: String {
        var parts: [String] = [pet.name]
        parts.append(genderLabel)
        parts.append(speciesLabel)
        if isActive { parts.append("In session \(elapsedString)") }
        return parts.joined(separator: ", ")
    }

    private var genderLabel: String { pet.gender == .male ? "Male" : "Female" }

    private var speciesLabel: String { pet.species == .dog ? "Dog" : "Cat" }
}

// MARK: - Preview
#if DEBUG
struct PetCard_Previews: PreviewProvider {
    static var previews: some View {
        let owner = Client(firstName: "Sarah", lastName: "Johnson", phone: "+15551234567")
        let pet1 = Pet(name: "Max", species: .dog, gender: .male)
        let pet2 = Pet(name: "Bella", species: .cat, gender: .female)
        owner.pets.append(contentsOf: [pet1, pet2])

        let active = Visit(pet: pet1)

        return VStack(spacing: 16) {
            PetCard(pet: pet1, activeVisit: active, onViewDetails: {}, onCheckIn: {}, onCheckOut: {})
            PetCard(pet: pet2, activeVisit: nil, onViewDetails: {}, onCheckIn: {}, onCheckOut: {})
        }
        .padding()
        .modelContainer(for: [Client.self, Pet.self, Visit.self, VisitItem.self, Payment.self], inMemory: true)
        .previewDisplayName("Pet Card Variants")
    }
}
#endif
