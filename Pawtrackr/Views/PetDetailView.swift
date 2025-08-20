//
//  PetDetailView.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//

import SwiftUI
import SwiftData
import Combine // Added: To fix 'Publishers' not found error

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Bindable var pet: Pet

    // UI state
    @State private var showCheckoutSheet = false
    @State private var showHistorySheet = false // Added: To handle "View History" action
    @State private var tick = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Gender accent line
                Rectangle()
                    .fill(DS.ColorToken.gender(pet.gender))
                    .frame(height: 3)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: 12) {
                        header
                        actionRow
                        visitsSection
                    }
                    .padding(.top, 8)
                }
            }
            // .navigationBarTitleDisplayMode(.inline) // Removed: Not available on macOS
            .navigationTitle(pet.name)
            .toolbar {
                ToolbarItem(placement: .navigation) { // Use .navigation for macOS leading items
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showCheckoutSheet) {
                // NOTE: This assumes 'InlineCheckoutSheet' is made accessible from its original file.
                // You should move its struct definition out of 'ClientDetailView'.
                CheckoutView(pet: pet) // Using full checkout for consistency
            }
            .sheet(isPresented: $showHistorySheet) { // Added: Sheet for history view
                PetHistoryView(pet: pet)
            }
            .onReceive(timer) { tick = $0 }
        }
    }

    // MARK: - Header

    private var header: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pet.name)
                            .font(.title3.weight(.semibold))
                        if isActive {
                            // Corrected: Use the .style parameter for Pill
                            Pill(text: "In Session", style: .filled(tint: .blue.opacity(0.12), text: .blue))
                        }
                    }
                    Text("\(pet.species.displayName)\(pet.breed.flatMap { ", \($0)" } ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let c = pet.color, !c.isEmpty {
                        Text(c).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let n = pet.notes, !n.isEmpty {
                        Text(n)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pet.name), \(pet.gender.displayName.lowercased()) \(pet.species.rawValue). \(isActive ? "In session" : "Not in session").")

            if isActive, let d = durationString {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    Text(d)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                }
                .padding(10)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal) // Added padding to match other views
    }

    private var avatar: some View {
        Group {
#if os(macOS)
            if let data = pet.photoData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(Circle().stroke(DS.ColorToken.gender(pet.gender).opacity(0.9), lineWidth: 2))
            } else {
                SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 72)
            }
#else
            if let data = pet.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(Circle().stroke(DS.ColorToken.gender(pet.gender).opacity(0.9), lineWidth: 2))
            } else {
                SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 72)
            }
#endif
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Corrected: Replaced undefined function with state change
            Button { showHistorySheet = true } label: {
                actionCapsule(title: "View History", icon: "doc.text.magnifyingglass")
            }
            Button { checkIn() } label: {
                actionCapsule(title: "Check In", icon: "play.circle.fill")
            }
            .disabled(isActive)
            .opacity(isActive ? 0.4 : 1)

            Button { checkOut() } label: {
                actionCapsule(title: "Check Out", icon: "checkmark.circle.fill", gradient: true)
            }
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func actionCapsule(title: String, icon: String, gradient: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                Capsule().fill(Color.gray.opacity(0.12))
                if gradient {
                    Capsule().fill(
                        LinearGradient(colors: [.green, .green.opacity(0.8)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                }
            }
        )
        .foregroundStyle(gradient ? .white : .primary) // Added foreground style for gradient
    }

    // MARK: - Visits

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Visits").font(.headline)
                Spacer()
            }
            ForEach(sortedVisits, id: \.persistentModelID) { visit in
                NavigationLink {
                    VisitDetailView(visit: visit)
                } label: {
                    VisitRowCompact(visit: visit)
                }
                .buttonStyle(.plain)
            }
            if sortedVisits.isEmpty {
                ContentUnavailableView("No visits yet", systemImage: "calendar.badge.plus", description: Text("Check in to start history."))
            }
        }
        .padding(.horizontal)
    }

    private var sortedVisits: [Visit] {
        pet.visits.sorted { (a, b) in
            (a.endedAt ?? a.startedAt) > (b.endedAt ?? b.startedAt)
        }
    }

    // MARK: - Session Helpers

    private var isActive: Bool { activeVisit != nil }

    private var activeVisit: Visit? {
        pet.visits.first(where: { $0.endedAt == nil })
    }

    private var durationString: String? {
        guard let start = activeVisit?.startedAt else { return nil }
        let seconds = Int(Date().timeIntervalSince(start))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    }

    private func checkIn() {
        guard !isActive else { return }
        let v = Visit(pet: pet)
        v.startedAt = Date()
        pet.visits.append(v)
        // Note: SwiftData automatically handles inserting the new visit through the relationship
        try? ctx.save()
    }

    private func checkOut() {
        // Corrected: Removed unused 'v' constant
        guard activeVisit != nil else { return }
        showCheckoutSheet = true
    }

    private func completeCheckout(amount: Decimal, method: Payment.Method, notes: String?) {
        guard let v = activeVisit else { return }
        v.endedAt = Date()
        v.total = amount // Set total on the visit
        let pmt = Payment(amount: amount, method: method)
        pmt.paidAt = Date()
        if let n = notes, !n.isEmpty {
            pmt.note = n
            v.notes = (v.notes ?? "") + (v.notes == nil ? "" : "\n") + n
        }
        v.payment = pmt
        // Note: SwiftData automatically handles inserting the payment through the relationship
        do {
            try ctx.save()
            NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: ["petID": pet.persistentModelID])
        } catch {
            print("Save error: \(error)")
        }
        showCheckoutSheet = false
    }
}

// MARK: - Compact Visit Row (condensed list cell)

private struct VisitRowCompact: View {
    let visit: Visit

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(DS.ColorToken.gender(visit.pet.gender))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(visit.startedAt, style: .date)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(duration)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if !visit.items.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                Pill(text: item.name, style: .filled())
                            }
                        }
                    }
                    if let notes = visit.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }

    private var duration: String {
        let end = visit.endedAt ?? Date() // Use current time if still active for running total
        let seconds = Int(end.timeIntervalSince(visit.startedAt))
        guard seconds > 0 else { return "0m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
