//
//  VisitDetailView.swift
//  Pawtrackr
//
//  Read-only detail view for a single Visit.
//  Shows pet, timestamps, duration, services, notes, total, and payment method.
//  Mirrors the design language used across PetHistory and RecentHistory.
//
//  Created by mac on 8/16/25.
//

import SwiftUI
import SwiftData

struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var visit: Visit

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DS.ColorToken.gender(visit.pet.gender))
                    .frame(height: 3)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: 12) {
                        header
                        metaCards
                        servicesCard
                        notesCard
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Visit Details")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.blue)
                    }
                }
#elseif os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button { dismiss() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
#endif
            }
        }
    }

    // MARK: - Header (pet summary)

    private var header: some View {
        Card {
            HStack(spacing: 12) {
                if let data = visit.pet.photoData {
                #if canImport(UIKit)
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        SpeciesAndGenderIcons.badge(for: visit.pet.species, gender: visit.pet.gender, size: 64)
                    }
                #elseif canImport(AppKit)
                    if let ns = NSImage(data: data) {
                        Image(nsImage: ns)
                            .resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        SpeciesAndGenderIcons.badge(for: visit.pet.species, gender: visit.pet.gender, size: 64)
                    }
                #else
                    SpeciesAndGenderIcons.badge(for: visit.pet.species, gender: visit.pet.gender, size: 64)
                #endif
                } else {
                    SpeciesAndGenderIcons.badge(for: visit.pet.species, gender: visit.pet.gender, size: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(visit.pet.name)
                        .font(.title3.weight(.semibold))
                    Text(petSubtitle(visit.pet))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let total = amountText {
                    Pill(text: total, style: .filled(tint: Color.green.opacity(0.12), text: Color.green))
                }
            }
        }
        .padding(.horizontal)
    }

    private func petSubtitle(_ pet: Pet) -> String {
        if let breed = pet.breed, !breed.isEmpty { return "\(breed) • \(pet.species.displayName)" }
        return pet.species.displayName
    }

    private var amountText: String? {
        visit.total > 0 ? visit.total.asCurrency : nil
    }

    // MARK: - Meta: timestamps, duration, payment

    private var metaCards: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Check-In", systemImage: "clock.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(visit.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                    Divider().opacity(0.1)
                    HStack {
                        Label("Check-Out", systemImage: "clock.badge.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text((visit.endedAt ?? visit.startedAt).formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                    Divider().opacity(0.1)
                    HStack {
                        Label("Duration", systemImage: "hourglass")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        TimelineView(.everyMinute) { _ in
                            Text(durationString)
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if let method = visit.payment?.method {
                Card {
                    HStack {
                        Label("Payment", systemImage: method.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(method.displayName)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var durationString: String {
        let end = visit.endedAt ?? Date()
        let seconds = max(0, Int(end.timeIntervalSince(visit.startedAt)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Services

    private var servicesCard: some View {
        Group {
            if visit.items.isEmpty {
                Card {
                    HStack {
                        Text("No services recorded").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Services Performed")
                            .font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 6) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                Pill(text: item.name)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Notes

    private var notesCard: some View {
        Group {
            if let n = visit.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline.weight(.semibold))
                        Text(n)
                            .font(.body)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}
