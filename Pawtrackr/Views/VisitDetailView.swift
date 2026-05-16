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
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let visit: Visit
    private let heroNamespace: Namespace.ID?
    @StateObject private var visitTimer = VisitTimer()
    @State private var showCheckout = false
    @State private var previewData: Data? = nil
    @State private var previewTitle: String = ""

    init(visit: Visit, heroNamespace: Namespace.ID? = nil) {
        self.visit = visit
        self.heroNamespace = heroNamespace
    }

    private var usesTabletLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    private var contentHorizontalPadding: CGFloat {
        usesTabletLayout ? 24 : 16
    }

    private var contentSpacing: CGFloat {
        usesTabletLayout ? 16 : 12
    }

    var body: some View {
        visitContent
            .navigationTitle(NSLocalizedString("visit.title", comment: ""))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { toolbarContent }
            .modifier(VisitCheckoutModifier(showCheckout: $showCheckout, visit: visit))
            .modifier(VisitPreviewModifier(previewItem: previewItemBinding))
            .onAppear {
                visitTimer.load(startedAt: visit.startedAt, endedAt: visit.endedAt)
            }
    }

    private var visitContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                header

                if usesTabletLayout {
                    tabletDetailLayout
                } else {
                    compactDetailLayout
                }
            }
            .frame(maxWidth: usesTabletLayout ? 1040 : nil)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, usesTabletLayout ? 18 : 8)
            .padding(.bottom, usesTabletLayout ? 28 : 16)
        }
        .background(detailBackground.ignoresSafeArea())
    }

    private var detailBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    private var compactDetailLayout: some View {
        VStack(spacing: contentSpacing) {
            timelineCard
            paymentCard
            servicesCard
            photosCard
            notesCard
            behaviorTagsCard
        }
    }

    private var tabletDetailLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    timelineCard
                    servicesCard
                    notesCard
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(spacing: 16) {
                    paymentCard
                    photosCard
                    behaviorTagsCard
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            compactDetailLayout
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            exportButton
        }
        checkoutToolbarItem
    }

    private var exportButton: some View {
        let csv = exportCSVForVisit()
        return ShareLink(
            item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_Visit.csv"),
            preview: SharePreview("Pawtrackr_Visit.csv", icon: Image(systemName: "doc.text.fill"))
        ) {
            Label(NSLocalizedString("common.export", comment: ""), systemImage: "square.and.arrow.up")
        }
        .disabled(csv.isEmpty)
        .accessibilityHint(csv.isEmpty ? NSLocalizedString("sharelink.accessibility.hint.no_data_to_export", comment: "") : NSLocalizedString("sharelink.accessibility.hint.export_visit", comment: ""))
    }

    @ToolbarContentBuilder
    private var checkoutToolbarItem: some ToolbarContent {
        #if os(iOS)
        if !usesTabletLayout {
            ToolbarItem(placement: .bottomBar) {
                checkoutButton
            }
        }
        #else
        ToolbarItem(placement: .secondaryAction) {
            checkoutButton
        }
        #endif
    }

    @ViewBuilder
    private var checkoutButton: some View {
        if visit.payment == nil {
            Button {
                showCheckout = true
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(visit.endedAt == nil ? NSLocalizedString("visit.check_out", comment: "") : NSLocalizedString("visit.resume_checkout", comment: ""))
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel(NSLocalizedString("visit.checkout_a11y", value: "Open checkout to complete payment", comment: ""))
        }
    }

    private var previewItemBinding: Binding<PreviewItem?> {
        Binding(
            get: { previewData.map { PreviewItem(data: $0, title: previewTitle) } },
            set: { newValue in
                if let v = newValue {
                    previewData = v.data
                    previewTitle = v.title
                } else {
                    previewData = nil
                    previewTitle = ""
                }
            }
        )
    }
    
    // MARK: - Header (pet summary) 
    
    private var header: some View {
        Card(elevation: .regular, accent: .leading(.color(DS.ColorToken.gender(visit.pet?.gender)), thickness: 4)) {
            HStack(spacing: 12) {
                heroAvatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(visit.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: ""))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(petSubtitle(visit.pet))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                if visit.isPaid {
                    Text(NSLocalizedString("status.paid", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                } else if visit.isCompleted {
                    Text(NSLocalizedString("status.completed", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(NSLocalizedString("status.in_session", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                if let total = amountText {
                    Chip(total, style: .tinted, size: .sm, tint: Color.accentColor)
                        .accessibilityLabel(String(format: NSLocalizedString("visit.total_a11y_fmt", value: "Total %@", comment: ""), total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func petSubtitle(_ pet: Pet?) -> String {
        guard let pet = pet else { return "" }
        if let breed = pet.breed, !breed.isEmpty { return "\(breed) • \(pet.species.displayName)" }
        return pet.species.displayName
    }

    @ViewBuilder
    private var heroAvatar: some View {
        let avatar = AvatarView(
            .pet(
                species: visit.pet?.species,
                gender: visit.pet?.gender,
                name: visit.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: ""),
                imageData: visit.pet?.photoData,
                thumbnailData: visit.pet?.thumbnailData
            ),
            size: .lg
        )

        if let heroNamespace {
            avatar.matchedGeometryEffect(id: heroID, in: heroNamespace)
        } else {
            avatar
        }
    }

    private var heroID: String {
        "visit-avatar-\(visit.uuid.uuidString)"
    }
    
    private var amountText: String? {
        visit.total > 0 ? visit.totalCurrencyString : nil
    }
    
    // MARK: - Timing & Payment

    private var timelineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(NSLocalizedString("visit.when", comment: ""), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))

                Divider().opacity(0.08)

                detailRow(
                    icon: "arrow.down.circle.fill",
                    title: NSLocalizedString("visit.check_in_time", comment: ""),
                    value: visit.startedAt.formatted(date: .abbreviated, time: .shortened)
                )

                detailRow(
                    icon: "arrow.up.circle.fill",
                    title: NSLocalizedString("visit.check_out_time", comment: ""),
                    value: visit.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? NSLocalizedString("visit.in_progress", comment: "")
                )

                detailRow(
                    icon: "clock.fill",
                    title: NSLocalizedString("visit.duration", comment: ""),
                    value: visit.durationString
                )
            }
        }
    }

    private var paymentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(NSLocalizedString("visit.payment", comment: ""), systemImage: visit.payment?.method.systemImage ?? "creditcard")
                    .font(.subheadline.weight(.semibold))

                Divider().opacity(0.08)

                if let payment = visit.payment {
                    detailRow(
                        icon: payment.method.systemImage,
                        title: payment.method.displayName,
                        value: payment.amountCurrencyString
                    )

                    if let ref = payment.externalReference, !ref.isEmpty {
                        Text(String(format: NSLocalizedString("visit.ref_fmt", comment: ""), ref))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Label(NSLocalizedString("visit.payment_pending", comment: ""), systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let total = amountText {
                    HStack(alignment: .firstTextBaseline) {
                        Text(NSLocalizedString("visit.total", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        Text(total)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: NSLocalizedString("visit.total_amount_a11y_fmt", value: "Total amount %@", comment: ""), total))
                }

                if visit.payment == nil && usesTabletLayout {
                    checkoutButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
    
    // MARK: - Services
    
    @ViewBuilder
    private var servicesCard: some View {
        // Split into simpler subviews to aid type-checking
        if (visit.items ?? []).isEmpty { servicesEmptyCard } else { servicesContentCard }
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
            .accessibilityLabel(NSLocalizedString("visit.no_services_a11y", value: "No services recorded for this visit", comment: ""))
        }
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
                .accessibilityLabel(String(format: NSLocalizedString("visit.total_amount_a11y_fmt", value: "Total amount %@", comment: ""), visit.totalCurrencyString))
            }
        }
        .accessibilityHint(NSLocalizedString("visit.services_hint", value: "Services performed and prices.", comment: ""))
    }
    
    private var servicesChips: some View {
        let items: [VisitItem] = Array(visit.items ?? [])
        return FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items, id: \.uuid) { (item: VisitItem) in
                Chip(item.displayName, style: .tinted, size: .sm, tint: .blue)
                    .accessibilityLabel(String(format: NSLocalizedString("visit.service_a11y_fmt", value: "Service %@", comment: ""), item.displayName))
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var servicesPriceList: some View {
        let items: [VisitItem] = Array(visit.items ?? [])
        return VStack(spacing: 8) {
            ForEach(items, id: \.uuid) { (item: VisitItem) in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.displayName + (item.quantity > 1 ? " ×\(item.quantity)" : ""))
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text(item.lineTotalString)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
        }
    }
    
    // MARK: - Photos (Before / After) 
    
    @State private var showTransformation = false

    private var photosCard: some View {
        Group {
            if visit.beforePhotoData == nil && visit.afterPhotoData == nil {
                EmptyView()
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(NSLocalizedString("visit.photos", comment: ""))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if visit.beforePhotoData != nil && visit.afterPhotoData != nil {
                                Button {
                                    showTransformation = true
                                } label: {
                                    Label(NSLocalizedString("transformation.title_short", value: "Transformation", comment: ""), systemImage: "sparkles.tv")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.blue)
                            }
                        }
                        
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                photoBox(title: NSLocalizedString("photobox.before", comment: ""), data: visit.beforePhotoData)
                                photoBox(title: NSLocalizedString("photobox.after", comment: ""), data: visit.afterPhotoData)
                            }

                            VStack(spacing: 12) {
                                photoBox(title: NSLocalizedString("photobox.before", comment: ""), data: visit.beforePhotoData)
                                photoBox(title: NSLocalizedString("photobox.after", comment: ""), data: visit.afterPhotoData)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTransformation) {
            TransformationView(beforeData: visit.beforePhotoData, afterData: visit.afterPhotoData, petName: visit.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: ""))
        }
    }
    
    @ViewBuilder
    private func photoBox(title: String, data: Data?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                        if let d = data, let ui = ImageCache.shared.image(data: d, maxDimension: 360) {
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
                // Fill available width and stay square. The previous fixed
                // 180×180 frame plus 12pt spacing exceeded the usable width
                // on iPhone SE (~288pt) once Card padding was applied,
                // forcing the second box to clip or push off-screen. Going
                // adaptive lets the boxes shrink together on small screens
                // and grow together on iPad / Mac.
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(Text(String(format: NSLocalizedString("visit.photo_a11y_label_fmt", comment: ""), title)))
                .accessibilityHint(Text(NSLocalizedString("visit.photo_a11y_hint", comment: "")))
            }
        }
    }

        private var placeholder: some View {
            VStack(spacing: 6) {
                Image(systemName: "photo")
                Text(NSLocalizedString("visit.no_photo", comment: ""))
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
                                .accessibilityLabel(String(format: NSLocalizedString("visit.notes_a11y_fmt", value: "Notes, %@", comment: ""), trimmed))
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        private var behaviorTagsCard: some View {
            if !visit.behaviorTags.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("visit.behavior_tags", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(visit.behaviorTags, id: \.self) { tag in
                                Chip(tag, style: .tinted, size: .sm, tint: .blue)
                            }
                        }
                    }
                }
            }
        }
        
        // MARK: - Export (CSV)
        
        private func exportCSVForVisit() -> String {
            let header = NSLocalizedString("visit.csv.header", value: "startedAt,endedAt,pet,owner,services,amount,payment,notes", comment: "")

            func escape(_ text: String) -> String {
                let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }

            let started = visit.startedAt.ISO8601Format()
            let ended = visit.endedAt?.ISO8601Format() ?? ""
            let petName = visit.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: "")
            let ownerName = visit.pet?.owner.map { "\($0.firstName) \($0.lastName)" } ?? ""
            let services = (visit.items ?? []).map { $0.displayName }.joined(separator: "; ")
            let amount = visit.totalCurrencyString
            let payment = visit.payment?.method.displayName ?? ""
            let notes = (visit.note ?? "").replacingOccurrences(of: "\n", with: " ")

            let row: [String] = [
                started,
                ended,
                petName,
                ownerName,
                services,
                amount,
                payment,
                notes
            ].map(escape)
            
            return header + "\n" + row.joined(separator: ",")
        }
    }
    
    // Wrapper type to drive fullScreenCover(item:)
fileprivate struct PreviewItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}

private struct VisitCheckoutModifier: ViewModifier {
    @Binding var showCheckout: Bool
    let visit: Visit

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $showCheckout) {
            if let pet = visit.pet {
                CheckoutView(pet: pet, visit: visit)
            }
        }
        #else
        content.sheet(isPresented: $showCheckout) {
            if let pet = visit.pet {
                CheckoutView(pet: pet, visit: visit)
            }
        }
        #endif
    }
}

private struct VisitPreviewModifier: ViewModifier {
    let previewItem: Binding<PreviewItem?>

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: previewItem) { item in
            PhotoPreview(imageData: item.data, title: item.title)
        }
        #else
        content.sheet(item: previewItem) { item in
            PhotoPreview(imageData: item.data, title: item.title)
        }
        #endif
    }
}
