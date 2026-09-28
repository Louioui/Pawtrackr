//
//  PetGenderNameBadge.swift
//  Pawtrackr
//

import SwiftUI

struct PetGenderNameBadge: View {
    let pet: Pet
    var showsDescriptor = false
    var maxNameWidth: CGFloat = 170

    var body: some View {
        HStack(spacing: 6) {
            SpeciesAndGenderIcons.genderDot(for: pet.gender, size: 9, isDecorative: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(pet.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxNameWidth, alignment: .leading)
                if showsDescriptor {
                    Text(pet.shortDescriptor)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.caption.weight(showsDescriptor ? .semibold : .regular))
        .foregroundStyle(.primary)
        .padding(.vertical, showsDescriptor ? 5 : 3)
        .padding(.horizontal, 8)
        .background(DS.ColorToken.gender(pet.gender).opacity(0.12), in: Capsule())
        .overlay(
            Capsule().stroke(DS.ColorToken.gender(pet.gender).opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pet.name), \(pet.gender.displayName)")
    }
}

struct HouseholdGenderStrip: View {
    let pets: [Pet]
    var maxVisible = 5

    private var visiblePets: [Pet] {
        Array(pets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(maxVisible))
    }

    var body: some View {
        HStack(spacing: -3) {
            ForEach(visiblePets) { pet in
                SpeciesAndGenderIcons.genderDot(for: pet.gender, size: 10, isDecorative: true)
                    .background(Circle().fill(DS.ColorToken.surface))
                    .accessibilityHidden(true)
            }
            if pets.count > maxVisible {
                Text("+\(pets.count - maxVisible)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard !pets.isEmpty else { return "No pets" }
        let grouped = Dictionary(grouping: pets, by: { $0.gender.displayName })
        return grouped
            .map { "\($0.value.count) \($0.key)" }
            .sorted()
            .joined(separator: ", ")
    }
}
