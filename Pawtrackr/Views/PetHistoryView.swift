//  PetHistoryView.swift
//  Pawtrackr
//
//  Shows a single pet’s full grooming history in reverse chronological order,
//  matching the "Max's History" timeline mock.
//  Each card displays: date, duration, services chips, amount, payment method, notes.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PetHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshID = UUID()

    @Bindable var pet: Pet

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        timelineHeader
                        timeline
                    }
                    .padding(.top, 8)
                    .animation(.easeInOut, value: pet.visits)
                }
                .id(refreshID)
            }
            .overlay(
                Rectangle()
                    .fill(pet.gender == .male ? Color.blue : Color.pink)
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .top),
                alignment: .top
            )
            .navigationTitle("\(pet.name)'s History")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.blue)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .visitDidComplete)) { _ in
                refreshID = UUID()
            }
        }
    }

    // MARK: - Header (profile summary)

    private var header: some View {
        Card {
            HStack(spacing: 12) {
                #if os(macOS)
                if let data = pet.photoData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay(Circle().stroke(DS.ColorToken.gender(pet.gender).opacity(0.9), lineWidth: 2))
                } else {
                    SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 64)
                }
                #else
                if let data = pet.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay(Circle().stroke(DS.ColorToken.gender(pet.gender).opacity(0.9), lineWidth: 2))
                } else {
                    SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 64)
                }
                #endif

                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.name).font(.title3.weight(.semibold))
                    Text(profileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        if let ageText = ageText { Pill(text: ageText, style: .filled(tint: .yellow.opacity(0.15), text: .yellow)) }
                        if let breed = pet.breed, !breed.isEmpty {
                            Pill(text: breed, style: .filled(tint: .blue.opacity(0.12), text: .primary))
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pet.name), \(pet.gender.displayName.lowercased()) \(pet.species.displayName).")
        .padding(.horizontal)
    }

    private var profileSubtitle: String {
        let speciesText = pet.species.displayName
        if let breed = pet.breed, !breed.isEmpty { return "\(breed) • \(speciesText)" }
        return speciesText
    }

    private var ageText: String? {
        // This is a placeholder; you would calculate the age from pet.birthdate here
        return nil
    }

    // MARK: - Timeline header

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Grooming History").font(.headline)
            Text("All past grooming sessions").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(spacing: 12) {
            ForEach(sortedVisits, id: \.persistentModelID) { visit in
                VisitTimelineCard(visit: visit)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, 24)
    }

    private var sortedVisits: [Visit] {
        pet.visits.sorted {
            ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt)
        }
    }
}

// MARK: - Visit timeline card

private struct VisitTimelineCard: View {
    let visit: Visit

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(DS.ColorToken.gender(visit.pet.gender))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let endedAt = visit.endedAt {
                                Label {
                                    Text("\(visit.startedAt.formatted(date: .numeric, time: .shortened)) - \(endedAt.formatted(date: .numeric, time: .shortened))")
                                } icon: {
                                    Image(systemName: "calendar")
                                }
                                .font(.subheadline.weight(.semibold))
                            } else {
                                Label {
                                    Text(visit.startedAt.formatted(date: .abbreviated, time: .shortened))
                                } icon: {
                                    Image(systemName: "calendar")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            if let dur = durationString {
                                Text("Duration: \(dur)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(visit.totalUSDString)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !visit.items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Services:").font(.footnote).foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(visit.items, id: \.persistentModelID) { item in
                                    Pill(text: item.name)
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if let beforeData = visit.beforePhotoData {
                            #if os(macOS)
                            if let img = NSImage(data: beforeData) {
                                VStack(spacing: 4) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
                                        .accessibilityLabel("Before photo")
                                    Text("Before").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            #else
                            if let img = UIImage(data: beforeData) {
                                VStack(spacing: 4) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
                                        .accessibilityLabel("Before photo")
                                    Text("Before").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            #endif
                        }

                        if let afterData = visit.afterPhotoData {
                            #if os(macOS)
                            if let img = NSImage(data: afterData) {
                                VStack(spacing: 4) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
                                        .accessibilityLabel("After photo")
                                    Text("After").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            #else
                            if let img = UIImage(data: afterData) {
                                VStack(spacing: 4) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
                                        .accessibilityLabel("After photo")
                                    Text("After").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            #endif
                        }
                    }

                    if let pm = visit.payment?.method {
                        HStack {
                            Text("Payment Method:").font(.footnote).foregroundStyle(.secondary)
                            Text(pm.displayName).font(.footnote.weight(.medium))
                            Spacer()
                        }
                    }

                    if let notes = visit.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes:").font(.footnote).foregroundStyle(.secondary)
                            Text(notes)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var durationString: String? {
        let end = visit.endedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(visit.startedAt))
        guard seconds > 0 else { return nil }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }
}


// MARK: - Removed Display helpers
// These extensions were duplicates and caused build errors.
// The correct versions are in Formatters.swift and Payment.swift.
