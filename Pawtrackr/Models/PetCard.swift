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
    @StateObject private var visitTimer = VisitTimer()
    @State private var pulse: Bool = false

    // MARK: - Derived
    private var isActive: Bool { activeVisit?.endedAt == nil && activeVisit != nil }

    private var elapsedString: String {
        guard let v = activeVisit else { return "" }
        if v.endedAt != nil { return v.durationString }
        return visitTimer.formattedElapsed
    }

    // MARK: - View
    var body: some View {
        Card(accent: .top(.color(DS.ColorToken.gender(pet.gender)))) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .md)

                VStack(alignment: .leading, spacing: 6) {
                    // Title + badge + trailing details chevron
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(pet.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isActive { inProgressBadge }
                        }
                        Spacer()
                        Button(action: onViewDetails) {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(DS.ColorToken.surface, in: Circle())
                                .accessibilityLabel("View details")
                        }
                        .buttonStyle(.plain)
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
                        // Prominent, centered live timer with subtle pulse and green accent
                        HStack {
                            Spacer(minLength: 0)
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.ColorToken.success)
                                VStack(spacing: 2) {
                                    Text(elapsedString)
                                        .font(.title2.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(DS.ColorToken.success)
                                    Text("In Session")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DS.ColorToken.success)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [
                                        DS.ColorToken.success.opacity(0.18),
                                        DS.ColorToken.success.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            , in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.ColorToken.success.opacity(0.25), lineWidth: 1)
                            )
                            .scaleEffect(pulse ? 1.03 : 1.0)
                            .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                            .onDisappear { pulse = false }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(visitTimer.accessibilityElapsedLabel)
                    } else if let last = pet.visits.filter({ $0.isCompleted }).sorted(by: { $0.sortKeyDate > $1.sortKeyDate }).first {
                        Text("Last Visit: \(last.sortKeyDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Actions: Keep Check In here; move Check Out into Visit Details screen
                    HStack(spacing: 8) {
                        Button(action: onCheckIn) {
                            Label("Check In", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActive)

                        Button(action: onViewDetails) {
                            Label("View Details", systemImage: "chevron.right")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
        .leftAccentRail(isActive ? DS.ColorToken.session : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .onChange(of: scenePhase) { _, phase in
            // When returning to foreground, snap any durations to now so the timer text is fresh
            if phase == .active && isActive {
                visitTimer.sceneBecameActive()
            }
        }
        .onAppear { syncTimer() }
        .onChange(of: activeVisit?.startedAt) { _ in syncTimer() }
        .onChange(of: activeVisit?.endedAt) { _ in syncTimer() }
        .onChange(of: isActive) { _, nowActive in
            // Start/stop pulse when the session toggles
            if nowActive {
                pulse = true
            } else {
                pulse = false
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
        if isActive { parts.append("In session \(visitTimer.accessibilityElapsedLabel)") }
        return parts.joined(separator: ", ")
    }

    private var genderLabel: String { pet.gender == .male ? "Male" : "Female" }

    private var speciesLabel: String { pet.species.displayName }

    // MARK: - Timer sync
    private func syncTimer() {
        guard let v = activeVisit else { visitTimer.reset(); return }
        visitTimer.load(startedAt: v.startedAt, endedAt: v.endedAt)
    }
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
