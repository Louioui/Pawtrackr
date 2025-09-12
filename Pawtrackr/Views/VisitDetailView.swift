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
    @Environment(\.modelContext) private var modelContext
    
    let visit: Visit
    @StateObject private var visitTimer = VisitTimer()
    @State private var showCheckout = false
    @State private var previewData: Data? = nil
    @State private var previewTitle: String = ""
    
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
            .navigationTitle(NSLocalizedString("visit.title", comment: ""))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                // Rely on the system-provided back button to avoid duplicates
                ToolbarItem(placement: .primaryAction) {
                    let csv = exportCSVForVisit()
                    ShareLink(
                        item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_Visit.csv"),
                        preview: SharePreview("Pawtrackr_Visit.csv", icon: Image(systemName: "doc.text.fill"))
                    ) {
                        Label("common.export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(csv.isEmpty)
                    .accessibilityHint(csv.isEmpty ? "No data to export" : "Shares a CSV summary of this visit")
                }
                // New: Check Out / Resume Checkout action available until payment is attached
                ToolbarItem(placement: .bottomBar) {
                    if visit.payment == nil {
                        Button {
                            // Do not persist an interim completion; present checkout and let it finalize.
                            showCheckout = true
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(visit.endedAt == nil ? "Check Out" : "Resume Checkout")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityLabel("Open checkout to complete payment")
                    }
                }
            }
            .fullScreenCover(isPresented: $showCheckout) {
                CheckoutView(pet: visit.pet)
            }
            .fullScreenCover(item: Binding(
                get: {
                    previewData.map { PreviewItem(data: $0, title: previewTitle) }
                },
                set: { newValue in
                    if let v = newValue { previewData = v.data; previewTitle = v.title } else { previewData = nil; previewTitle = "" }
                }
            )) { item in
                PhotoPreview(imageData: item.data, title: item.title)
            }
            .onAppear {
                visitTimer.load(startedAt: visit.startedAt, endedAt: visit.endedAt)
            }
        }
    }
    
    // MARK: - Header (pet summary)
    
    private var header: some View {
        Card(accent: .top(.color(DS.ColorToken.gender(visit.pet.gender)))) {
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
                if visit.isPaid {
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
                    Chip(total, style: .tinted, size: .sm, tint: Color.accentColor)
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
                        Label(NSLocalizedString("visit.when", comment: ""), systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(range)
                            .font(.subheadline)
                    }
                    Divider().opacity(0.1)
                    HStack {
                        Label(NSLocalizedString("visit.duration", comment: ""), systemImage: "hourglass")
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
                        Label(NSLocalizedString("visit.payment", comment: ""), systemImage: payment.method.systemImage)
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
    
    @ViewBuilder
    private var servicesCard: some View {
        // Split into simpler subviews to aid type-checking
        if visit.items.isEmpty { servicesEmptyCard } else { servicesContentCard }
    }
    
    private var servicesEmptyCard: some View {
        Card {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("visit.no_services", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No services recorded for this visit")
        }
        .padding(.horizontal)
    }
    
    private var servicesContentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("visit.services_performed", comment: ""))
                    .font(.subheadline.weight(.semibold))
                
                // Chips row (consistent with History/Checkout)
                servicesChips
                
                Divider().opacity(0.08)
                
                // Compact price list
                servicesPriceList
                
                Divider().opacity(0.08)
                
                HStack {
                    Text(NSLocalizedString("visit.total", comment: ""))
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
        .padding(.horizontal)
    }
    
    private var servicesChips: some View {
        let items: [VisitItem] = Array(visit.items)
        return FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items, id: \.uuid) { (item: VisitItem) in
                Chip(item.displayName, style: .tinted, size: .sm, tint: .blue)
                    .accessibilityLabel("Service \(item.displayName)")
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var servicesPriceList: some View {
        let items: [VisitItem] = Array(visit.items)
        return VStack(spacing: 8) {
            ForEach(items, id: \.uuid) { (item: VisitItem) in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.displayName + (item.quantity > 1 ? " ×\(item.quantity)" : ""))
                        .font(.subheadline)
                    Spacer()
                    Text(item.lineTotalString)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
    
    // MARK: - Photos (Before / After)
    
    private var photosCard: some View {
        Group {
            if visit.beforePhotoData == nil && visit.afterPhotoData == nil {
                EmptyView()
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("visit.photos", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            photoBox(title: "Before", data: visit.beforePhotoData)
                            photoBox(title: "After", data: visit.afterPhotoData)
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
            Button {
                if let data { previewData = data; previewTitle = title }
            } label: {
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
                .buttonStyle(.plain)
                .frame(width: 180, height: 180)
                .accessibilityLabel(Text(String(format: NSLocalizedString("visit.photo_a11y_label_fmt", comment: ""), title)))
                .accessibilityHint(Text(NSLocalizedString("visit.photo_a11y_hint", comment: "")))
            }
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
                            Text(NSLocalizedString("visit.no_notes", comment: ""))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("visit.notes", comment: ""))
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
    
    // Wrapper type to drive fullScreenCover(item:)
fileprivate struct PreviewItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}
