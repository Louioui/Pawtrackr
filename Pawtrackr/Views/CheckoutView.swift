//
//  CheckoutView.swift
//  Pawtrackr
//
//  Full-screen checkout that matches the mock:
//  - Pet header with live duration
//  - Service chips (toggle)
//  - Session notes + behavior tags (simple chips)
//  - Optional before/after photos (uses ImagePicker component)
//  - Amount + payment method
//  - Confirm & Check Out finalizes the active Visit and creates a Payment
//
//  Created by mac on 8/15/25.
//

import SwiftUI
import SwiftData
import Foundation  // for Locale/autoupdatingCurrent if not already present

extension Notification.Name {
    static let visitDidComplete = Notification.Name("VisitDidComplete")
}

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Bindable var pet: Pet

    // Active visit must exist (startedAt set, endedAt nil). If not, we create one on appear.
    @State private var activeVisit: Visit?

    // Services selection + data
    @Query(sort: [SortDescriptor(\Service.name)])
    private var allServices: [Service]

    @State private var selectedServiceIDs: Set<PersistentIdentifier> = []

    // Notes & tags
    @State private var notes: String = ""
    @State private var tagOptions: [String] = ["Calm", "Cooperative", "Anxious", "Muzzle"]
    @State private var tags: Set<String> = []

    // Photos (optional)
    @State private var beforePhotoData: Data?
    @State private var afterPhotoData: Data?

    // Charge & payment
    @State private var amountString: String = ""
    @State private var paymentMethod: Payment.Method = .cash
    @State private var checkoutNotes: String = ""

    // Timer for live duration
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DS.ColorToken.gender(pet.gender))
                    .frame(height: 3)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: 16) {
                        header

                        servicesSection
                        notesSection
                        photosSection
                        chargeSection

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .overlay(
                Rectangle()
                    .fill(pet.gender == .male ? Color.blue : Color.pink)
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .top),
                alignment: .top
            )
            .navigationTitle("Check Out")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirmCheckout() }
                        .disabled(totalDecimal <= 0 || selectedServiceIDs.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: confirmCheckout) {
                    Label("Confirm & Check Out", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding()
                .background(.ultraThinMaterial)
            }
            .onAppear(perform: hydrate)
            .onReceive(timer) { tick = $0 }
        }
    }

    // MARK: - Sections

    private var header: some View {
        Card {
            HStack(spacing: 12) {
                // Photo or icon
                #if canImport(UIKit)
                if let data = pet.photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 56)
                }
                #else
                SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 56)
                #endif

                VStack(alignment: .leading, spacing: 2) {
                    Text(pet.name).font(.headline)
                    Text(pet.breed ?? pet.species.displayName)
                        .font(.subheadline).foregroundStyle(.secondary)

                    // Duration with dynamic timer if active
                    if let v = activeVisit {
                        if v.endedAt == nil {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.green)
                                TimelineView(.periodic(from: Date(), by: 1)) { context in
                                    Text(durationString(from: v, now: context.date))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.top, 2)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.green)
                                Text(durationString(from: v))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var servicesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Services Performed").font(.subheadline.weight(.semibold))
                FlowLayout(spacing: 8) {
                    ForEach(allServices, id: \.persistentModelID) { s in
                        SelectablePill(text: s.name, selected: selectedServiceIDs.contains(s.persistentModelID)) {
                            toggleService(s)
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Notes").font(.subheadline.weight(.semibold))
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.gray.opacity(0.15))
                    )

                Text("Behavior Tags").font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(tagOptions, id: \.self) { tag in
                        SelectablePill(text: tag, selected: tags.contains(tag)) {
                            if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                        }
                    }
                }
            }
        }
    }

    private var photosSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before & After Photos").font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ImagePicker(imageData: $beforePhotoData, allowsEditing: true, maxDimension: 2048, jpegQuality: 0.8) {
                        photoBox(title: "Before", imageData: beforePhotoData)
                    }
                    ImagePicker(imageData: $afterPhotoData, allowsEditing: true, maxDimension: 2048, jpegQuality: 0.8) {
                        photoBox(title: "After", imageData: afterPhotoData)
                    }
                }
            }
        }
    }

    private var chargeSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Service Charge").font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount").font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                            .textContentType(.oneTimeCode) // improves decimal keypad behavior on iOS
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        #endif
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.08)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Method").font(.footnote).foregroundStyle(.secondary)
                    Picker("", selection: $paymentMethod) {
                        ForEach(Payment.Method.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional Notes").font(.footnote).foregroundStyle(.secondary)
                    TextField("Extra charge for matting removal", text: $checkoutNotes)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor private func hydrate() {
        // Ensure an active visit exists
        if let current = pet.visits.first(where: { $0.endedAt == nil }) {
            activeVisit = current
        } else {
            let v = Visit(pet: pet)
            v.startedAt = Date()
            ctx.insert(v)
            activeVisit = v
            try? ctx.save()
        }

        // Prefill from visit if any fields are present
        if let v = activeVisit {
            notes = v.notes ?? notes
            // Prefill selections from VisitItems by matching names back to Service catalog
            selectedServiceIDs = Set(
                allServices.filter { svc in
                    v.items.contains { $0.name == svc.name }
                }
                .map(\.persistentModelID)
            )
            if v.total > 0, amountString.isEmpty {
                amountString = v.total.formatted(.currency(code: "USD"))
            }
        }
    }

    @MainActor private func confirmCheckout() {
        guard let v = activeVisit else { return }
        // Apply selections using VisitItem snapshots
        let selected = allServices.filter { selectedServiceIDs.contains($0.persistentModelID) }
        // Clear any existing items (edit-safe)
        v.items.forEach { ctx.delete($0) }
        v.items.removeAll()
        // Snapshot each selected Service into a VisitItem
        for svc in selected {
            // ✅ FIXED: Added the required 'visit' and 'service' parameters.
            let item = VisitItem(name: svc.name, price: svc.defaultPrice, visit: v, service: svc)
            v.items.append(item)
        }

        v.notes = notes
        v.beforePhotoData = beforePhotoData
        v.afterPhotoData = afterPhotoData
        v.endedAt = Date()
        // If a manual amount was entered, honor it; otherwise compute from items
        let autoTotal = v.items.reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
        v.total = (totalDecimal > 0) ? totalDecimal : autoTotal
        v.updatedAt = Date()

        // Attach payment (initializer does NOT take visit:; assign relationship after)
        let pmt = Payment(amount: v.total, method: paymentMethod)
        pmt.paidAt = Date()
        pmt.note = checkoutNotes
        pmt.visit = v
        ctx.insert(pmt)

        do {
            try ctx.save()
            NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: ["petID": pet.persistentModelID])
            dismiss()
        } catch {
            print("Checkout save failed:", error)
        }
    }

    // MARK: - Helpers

    private func toggleService(_ s: Service) {
        let id = s.persistentModelID
        if selectedServiceIDs.contains(id) { selectedServiceIDs.remove(id) } else { selectedServiceIDs.insert(id) }
    }

    private var totalDecimal: Decimal {
        // USD-only business rule
        if let d = amountString.asDecimal(locale: .autoupdatingCurrent) {
            return d.rounded(scale: 2) // ensure 2dp for money
        }
        return 0
    }

    private func durationString(from v: Visit, now: Date = Date()) -> String {
        let sec = Int(now.timeIntervalSince(v.startedAt))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return h > 0 ? "\(h) hr \(m) mins" : "\(m) mins"
    }

    @ViewBuilder
    private func photoBox(title: String, imageData: Data?) -> some View {
        ZStack {
            #if canImport(UIKit)
            if let data = imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                placeholderBox(title: title)
            }
            #else
            placeholderBox(title: title)
            #endif
        }
    }

    @ViewBuilder
    private func placeholderBox(title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill").font(.title3).foregroundStyle(.secondary)
            Text("\(title) Photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [6,6]))
                .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.08)))
        )
    }
}

private struct SelectablePill: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Group {
                        if selected {
                            LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                           startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.gray.opacity(0.12)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(selected ? .clear : .gray.opacity(0.25))
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
