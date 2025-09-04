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
import UniformTypeIdentifiers

// Single-visit CSV wrapper for ShareLink
private struct CSVDoc: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in
            csv.data
        }
    }
}

struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var visit: Visit
    @StateObject private var visitTimer = VisitTimer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        metaCards
                        servicesCard
                        photosCard
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
                ToolbarItem(placement: .primaryAction) {
                    let csv = exportCSVForVisit()
                    ShareLink(
                        item: CSVDoc(data: Data(csv.utf8)),
                        preview: SharePreview("Pawtrackr_Visit.csv", icon: Image(systemName: "doc.text.fill"))
                    ) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(csv.isEmpty)
                    .accessibilityHint(csv.isEmpty ? "No data to export" : "Shares a CSV summary of this visit")
                }
            }
            .onAppear {
                visitTimer.load(startedAt: visit.startedAt, endedAt: visit.endedAt)
            }
        }
    }

    // MARK: - Header (pet summary)

    private var header: some View {
        Card(accentTopLine: DS.ColorToken.gender(visit.pet.gender)) {
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
                if visit.isSettled {
                    Text("Paid")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                } else if visit.isCompleted {
                    Text("Completed")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("In Progress")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                if let total = amountText {
                    Pill(text: total, style: .filled(tint: Color.accentColor.opacity(0.12), text: Color.accentColor))
                        .accessibilityLabel("Total \(total)")
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
        visit.total > 0 ? visit.totalCurrencyString : nil
    }

    // MARK: - Meta: timestamps, duration, payment

    private var metaCards: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    let range = Formatters.dateRangeString(from: visit.startedAt, to: visit.endedAt ?? visit.startedAt)
                    HStack {
                        Label("When", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(range)
                            .font(.subheadline)
                    }
                    Divider().opacity(0.1)
                    HStack {
                        Label("Duration", systemImage: "hourglass")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Group {
                            if visit.endedAt == nil {
                                Text(visitTimer.formattedElapsed)
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .accessibilityLabel(visitTimer.accessibilityElapsedLabel)
                            } else {
                                Text(Formatters.durationString(from: visit.startedAt, to: visit.endedAt ?? visit.startedAt))
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }

            if let payment = visit.payment {
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Payment", systemImage: payment.method.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(payment.method.displayName)
                                .font(.subheadline)
                            Text(payment.amountCurrencyString)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let ref = payment.externalReference, !ref.isEmpty {
                                Text("Ref: \(ref)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Services

    private var servicesCard: some View {
        Group {
            if visit.items.isEmpty {
                Card {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundStyle(.secondary)
                        Text("No services recorded")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No services recorded for this visit")
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Services Performed")
                            .font(.subheadline.weight(.semibold))

                        // Chips row (consistent with History/Checkout)
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                Pill(text: item.displayName,
                                     style: .tinted(tint: .blue.opacity(0.15), text: .blue))
                                    .accessibilityLabel("Service \(item.displayName)")
                                    .allowsHitTesting(false)
                            }
                        }

                        Divider().opacity(0.08)

                        // Compact price list
                        VStack(spacing: 8) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.displayName + (item.quantity > 1 ? " ×\(item.quantity)" : ""))
                                        .font(.subheadline)
                                    Spacer()
                                    Text(item.lineTotalCurrencyString)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }

                        Divider().opacity(0.08)

                        HStack {
                            Text("Total")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(visit.totalCurrencyString)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Total amount \(visit.totalCurrencyString)")
                    }
                }
                .accessibilityHint("Services performed and prices.")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Photos (Before / After)

    private var photosCard: some View {
        Group {
            if visit.photoBefore == nil && visit.photoAfter == nil {
                EmptyView()
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            photoBox(title: "Before", data: visit.photoBefore)
                            photoBox(title: "After", data: visit.photoAfter)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func photoBox(title: String, data: Data?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.gray.opacity(0.2))
                Group {
                    #if canImport(UIKit)
                    if let d = data, let ui = UIImage(data: d) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                    #elseif canImport(AppKit)
                    if let d = data, let ns = NSImage(data: d) {
                        Image(nsImage: ns)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                    #else
                    placeholder
                    #endif
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(width: 160, height: 160)
            .accessibilityLabel("\(title) photo")
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
            Text("No Photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        Group {
            let trimmed = visit.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                Card {
                    HStack {
                        Text("No notes")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline.weight(.semibold))
                        let attr = (try? AttributedString(markdown: trimmed)) ?? AttributedString(trimmed)
                        Text(attr)
                            .font(.body)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .accessibilityLabel("Notes, \(trimmed)")
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Export (CSV)

    private func exportCSVForVisit() -> String {
        // Header + single row for this Visit
        var lines: [String] = ["startedAt,endedAt,pet,owner,services,amount,payment,notes"]
        let started = Formatters.iso8601.string(from: visit.startedAt)
        let ended = visit.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""

        let petName = visit.pet.name.replacingOccurrences(of: "\"", with: "\"\"")
        let ownerName: String = {
            if let o = visit.pet.owner {
                return "\(o.firstName) \(o.lastName)".replacingOccurrences(of: "\"", with: "\"\"")
            }
            return ""
        }()

        // Use SNAPSHOT names from VisitItem to ensure historical integrity
        let services = visit.items
            .map { $0.displayName.replacingOccurrences(of: "\"", with: "\"\"") }
            .joined(separator: "; ")

        let amount = Formatters.currency.string(from: NSDecimalNumber(decimal: visit.total)) ?? "$0.00"
        let payment = (visit.payment?.method.displayName ?? "").replacingOccurrences(of: "\"", with: "\"\"")
        let notes = (visit.note ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "\"\"")

        lines.append("\(started),\(ended),\"\(petName)\",\"\(ownerName)\",\"\(services)\",\(amount),\"\(payment)\",\"\(notes)\"")
        return lines.joined(separator: "\n")
    }
}
