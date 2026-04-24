//
//  PetDetailView.swift
//  Pawtrackr
//
//  Updated by Assistant on 8/28/25 to use a ViewModel.
//  - All business logic (check-in, state management) is now in the ViewModel.
//  - Uses standard button styles and reusable components for UI consistency.
//  - Dangerous `completeCheckout` logic has been removed.
//

import SwiftUI
import SwiftData

// MARK: - ViewModel
@Observable
@MainActor
final class PetDetailViewModel {
    var pet: Pet
    var appError: AppError? = nil
    private let visitRepository: VisitRepositoryProtocol
    
    // State
    var sheetDestination: SheetDestination?
    let visitTimer = VisitTimer()
    
    // Computed Data
    var activeVisit: Visit? {
        pet.activeVisit
    }
    
    var sortedVisits: [Visit] {
        pet.visits.sorted { $0.sortKeyDate > $1.sortKeyDate }
    }

    // MARK: - Stats
    var completedVisits: [Visit] {
        pet.visits.filter { $0.isCompleted }
            .sorted { $0.sortKeyDate > $1.sortKeyDate }
    }
    
    var totalVisits: Int { pet.visits.count }
    
    var totalSpent: Decimal {
        completedVisits.reduce(0) { $0 + $1.effectiveTotal }
    }
    
    var totalSpentString: String {
        totalSpent.moneyString
    }
    
    var averageDurationString: String {
        guard !completedVisits.isEmpty else { return "–" }
        let totalSeconds = completedVisits.map { Int($0.duration) }.reduce(0, +)
        let avg = max(0, totalSeconds / completedVisits.count)
        return VisitTimer.format(seconds: avg)
    }
    
    init(pet: Pet, modelContext: ModelContext) {
        self.pet = pet
        self.visitRepository = VisitRepository(modelContainer: modelContext.container)
        
        Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: .visitDidComplete).map { _ in () }
            for await _ in notifications {
                self?.updateTimerOnMain()
            }
        }
        
        updateTimer()
    }
    
    @MainActor
    private func updateTimerOnMain() {
        updateTimer()
    }
    
    func updateTimer() {
        if let v = activeVisit {
            visitTimer.load(startedAt: v.startedAt, endedAt: v.endedAt)
        } else {
            visitTimer.reset()
        }
    }
    
    // MARK: Intents
    func checkIn() {
        guard activeVisit == nil else { return }
        Task {
            do {
                _ = try await visitRepository.checkIn(pet: pet, date: .now)
                updateTimer()
            } catch {
                appError = .database("Could not start a visit. Please try again.")
            }
        }
    }
    
    func showCheckout() {
        guard let petForCheckout = pet.modelContext != nil ? pet : nil else { return }
        sheetDestination = .checkout(petForCheckout)
    }
    
    func showHistory() {
        sheetDestination = .history(pet)
    }
    
    enum SheetDestination: Identifiable {
        case checkout(Pet)
        case history(Pet)
        
        var id: String {
            switch self {
            case .checkout(let pet): "checkout-\(pet.id)"
            case .history(let pet): "history-\(pet.id)"
            }
        }
    }

}

// MARK: - View
struct PetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PetDetailViewModel?
    @State private var confirmCheckIn: Bool = false
    private let initialPet: Pet
    var namespace: Namespace.ID

    init(pet: Pet, namespace: Namespace.ID) {
        self.initialPet = pet
        self.namespace = namespace
        _viewModel = State(initialValue: nil)
    }
    
    var body: some View {
        Group {
            if let vm = viewModel {
                @Bindable var bvm = vm
                ScrollView {
                    VStack(spacing: 12) {
                        header(vm)
                        actionRow(vm)
                        quickStats(vm)
                        visitsSection(vm)
                    }
                    .padding(.vertical, 8)
                }
                .navigationTitle(vm.pet.name)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .alert(String(format: NSLocalizedString("client_details.checkin_confirm_title_fmt", comment: ""), vm.pet.name), isPresented: $confirmCheckIn) {
                    Button(NSLocalizedString("common.no", comment: ""), role: .cancel) {}
                    Button(NSLocalizedString("common.yes", comment: ""), role: .destructive) { vm.checkIn() }
                } message: {
                    Text(NSLocalizedString("client_details.checkin_confirm_message", comment: ""))
                }
                .sheet(item: $bvm.sheetDestination) { destination in
                    switch destination {
                    case .checkout(let petForCheckout):
                        NavigationStack {
                            CheckoutView(pet: petForCheckout, visit: vm.activeVisit)
                        }
                    case .history(let petForHistory):
                        NavigationStack {
                            PetHistoryView(pet: petForHistory)
                        }
                    }
                }
                .onChange(of: vm.pet.visits.count) {
                    vm.updateTimer()
                }
                .alert(item: $bvm.appError) { error in
                    Alert(
                        title: Text(NSLocalizedString("common.error", comment: "")),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                    )
                }
            } else {
                ProgressView()
                    .task { viewModel = PetDetailViewModel(pet: initialPet, modelContext: modelContext) }
            }
        }
    }
    
    private func header(_ vm: PetDetailViewModel) -> some View {
            Card(accent: .top(.color(DS.ColorToken.gender(vm.pet.gender)))) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        AvatarView(.pet(species: vm.pet.species, gender: vm.pet.gender, name: vm.pet.name, imageData: vm.pet.photoData), size: .lg)
                            .matchedGeometryEffect(id: vm.pet.id, in: namespace)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.pet.name).font(.title2.weight(.semibold))
                            Text(vm.pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)
                            if let age = vm.pet.ageString { Text(String(format: NSLocalizedString("pet.age_fmt", comment: ""), age)).font(.footnote).foregroundStyle(.secondary) }
                            ownerInfo(vm)
                        }
                        Spacer()
                    }
                    if vm.activeVisit != nil { sessionStatus(vm) }
                }
            }
            .padding(.horizontal)
        }

    private func ownerInfo(_ vm: PetDetailViewModel) -> some View {
            Group {
                if let owner = vm.pet.owner {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("pet.owner", comment: "")).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill").foregroundStyle(.secondary)
                            Text(owner.fullName).font(.footnote.weight(.medium))
                            if let phone = owner.phone, !phone.isEmpty {
                                Spacer(minLength: 8)
                                Image(systemName: "phone.fill").foregroundStyle(.secondary)
                                Text(phone).font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }

    private func sessionStatus(_ vm: PetDetailViewModel) -> some View {
            HStack(spacing: 10) {
                Label(NSLocalizedString("status.in_session", comment: ""), systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.success)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(DS.ColorToken.success.opacity(0.12), in: Capsule())
                Spacer()
                Label(vm.visitTimer.formattedElapsed, systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
                    .accessibilityLabel(vm.visitTimer.accessibilityElapsedLabel)
            }
        }
        
    private func actionRow(_ vm: PetDetailViewModel) -> some View {
            HStack(spacing: 12) {
                actionTile(title: NSLocalizedString("pet.view_history", comment: ""), systemImage: "clock.arrow.circlepath", tint: .primary) { vm.showHistory() }
                actionTile(title: NSLocalizedString("pet.check_in", comment: ""), systemImage: "play.fill", tint: .blue, disabled: vm.activeVisit != nil) { confirmCheckIn = true }
                actionTile(title: NSLocalizedString("pet.check_out", comment: ""), systemImage: "checkmark.seal.fill", tint: .green, disabled: vm.activeVisit == nil) { vm.showCheckout() }
            }
            .padding(.horizontal)
        }

    private func actionTile(title: String, systemImage: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(disabled ? 0.5 : 1)
            .disabled(disabled)
        }

    private func quickStats(_ vm: PetDetailViewModel) -> some View {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("pet.quick_stats", comment: "")).font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        statTile(label: NSLocalizedString("pet.total_visits", comment: ""), value: "\(vm.totalVisits)", tint: .blue)
                        statTile(label: NSLocalizedString("pet.total_spent", comment: ""), value: vm.totalSpentString, tint: .green)
                        statTile(label: NSLocalizedString("pet.avg_duration", comment: ""), value: vm.averageDurationString, tint: .purple)
                    }
                }
            }
            .padding(.horizontal)
        }

    private func statTile(label: String, value: String, tint: Color) -> some View {
            VStack(spacing: 6) {
                Text(value).font(.headline.weight(.bold)).foregroundStyle(tint)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        
    private func visitsSection(_ vm: PetDetailViewModel) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Text(NSLocalizedString("pet.recent_visits", comment: "")).font(.headline)
                    Spacer()
                    Text("\(vm.sortedVisits.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel("Recent visits count \(vm.sortedVisits.count)")
                }
                .padding(.horizontal)

                // Empty state
                if vm.sortedVisits.isEmpty {
                    ContentUnavailableView(NSLocalizedString("pet.no_visits_yet", comment: ""), systemImage: "calendar.badge.plus")
                } else {
                    VStack(spacing: 12) {
                        // Highlight current visit (if any)
                        if let current = vm.activeVisit {
                            currentVisitCard(current)
                                .padding(.horizontal)
                        }

                        // Remaining visits
                        ForEach(vm.sortedVisits.filter { $0.endedAt != nil }) { visit in
                            NavigationLink(destination: VisitDetailView(visit: visit)) {
                                VisitTimelineRow(visit: visit)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }

    private func currentVisitCard(_ visit: Visit) -> some View {
            Card(showBorder: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("In Progress", systemImage: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.success)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(DS.ColorToken.sessionBackground, in: Capsule())
                        Text(startedString(visit.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(visit.totalCurrencyString)
                                .font(.subheadline.weight(.semibold))
                            Text(vmElapsedLabel())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Services
                    if !visit.items.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(visit.items) { item in
                                Chip(item.displayName, style: .tinted, size: .sm)
                            }
                        }
                    }

                    // Payment / media footer
                    HStack(spacing: 8) {
                        if let method = visit.payment?.method {
                            Label(method.displayName, systemImage: method.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(NSLocalizedString("visit.payment_pending", comment: ""), systemImage: "creditcard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        mediaThumbs(visit)
                    }
                }
            }
            .leftAccentRail(DS.ColorToken.session)
        }

    private func mediaThumbs(_ visit: Visit) -> some View {
            HStack(spacing: 6) {
                if let data = visit.beforePhotoData {
                #if canImport(UIKit)
                    if let img = ImageCache.shared.image(data: data, maxDimension: 64) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.ColorToken.border, lineWidth: 0.5))
                    }
                #elseif canImport(AppKit)
                    if let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.ColorToken.border, lineWidth: 0.5))
                    }
                #endif
                }
                if let data = visit.afterPhotoData {
                #if canImport(UIKit)
                    if let img = ImageCache.shared.image(data: data, maxDimension: 64) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.ColorToken.border, lineWidth: 0.5))
                    }
                #elseif canImport(AppKit)
                    if let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.ColorToken.border, lineWidth: 0.5))
                    }
                #endif
                }
            }
        }

    private func startedString(_ date: Date) -> String {
            // Localized relative day (Today/Yesterday) + time for current locale
            let dateOnly = DateFormatter()
            dateOnly.locale = .current
            dateOnly.dateStyle = .medium
            dateOnly.timeStyle = .none
            dateOnly.doesRelativeDateFormatting = true
            let timeOnly = DateFormatter()
            timeOnly.locale = .current
            timeOnly.dateStyle = .none
            timeOnly.timeStyle = .short
            return "\(dateOnly.string(from: date)), \(timeOnly.string(from: date))"
        }

    private func vmElapsedLabel() -> String {
        viewModel?.visitTimer.formattedElapsed ?? ""
    }
}
