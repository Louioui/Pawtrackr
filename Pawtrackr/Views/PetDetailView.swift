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
    private var modelContext: ModelContext
    
    // State
    var sheetDestination: SheetDestination?
    let visitTimer = VisitTimer()
    var showAlert: Bool = false
    var alertMessage: String = ""
    
    // Computed Data
    var activeVisit: Visit? {
        pet.visits.first { $0.endedAt == nil }
    }
    
    var sortedVisits: [Visit] {
        pet.visits.sorted { $0.sortKeyDate > $1.sortKeyDate }
    }
    
    init(pet: Pet, modelContext: ModelContext) {
        self.pet = pet
        self.modelContext = modelContext
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisitCompletion),
            name: .visitDidComplete,
            object: nil
        )
        
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
        let newVisit = Visit(pet: pet)
        modelContext.insert(newVisit)
        do { try modelContext.save() }
        catch {
            alertMessage = "Could not start a visit. Please try again."
            showAlert = true
        }
        updateTimer() // Refresh timer after check-in
    }
    
    func showCheckout() {
        guard let petForCheckout = pet.modelContext != nil ? pet : nil else { return }
        sheetDestination = .checkout(petForCheckout)
    }
    
    func showHistory() {
        sheetDestination = .history(pet)
    }
    
    @objc private func handleVisitCompletion() {
        updateTimer()
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
    
    // MARK: - View
    struct PetDetailView: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext
        @State private var viewModel: PetDetailViewModel?
        private let initialPet: Pet
        init(pet: Pet) {
            self.initialPet = pet
            _viewModel = State(initialValue: nil)
        }
        
        var body: some View {
            Group {
                if let vm = viewModel {
                    @Bindable var pet = vm.pet
                    @Bindable var bvm = vm
                    NavigationStack {
                        ScrollView {
                            VStack(spacing: 12) {
                                header(vm)
                                actionRow(vm)
                                visitsSection(vm)
                            }
                            .padding(.vertical, 8)
                        }
                        .navigationTitle(pet.name)
#if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                            }
                        }
                        .sheet(item: $bvm.sheetDestination) { destination in
                            switch destination {
                            case .checkout(let petForCheckout):
                                CheckoutView(pet: petForCheckout)
                            case .history(let petForHistory):
                                PetHistoryView(pet: petForHistory)
                            }
                        }
                        .onChange(of: vm.pet.visits.count) {
                            vm.updateTimer()
                        }
                        .alert("Save Error", isPresented: $bvm.showAlert) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text(bvm.alertMessage)
                        }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vm.pet.name).font(.title2.weight(.semibold))
                            Text(vm.pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)
                            if let age = vm.pet.ageString { Text("Age: \(age)").font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                    if vm.activeVisit != nil { timerDisplay(vm) }
                }
            }
            .padding(.horizontal)
        }
        
        private func timerDisplay(_ vm: PetDetailViewModel) -> some View {
            Label(vm.visitTimer.formattedElapsed, systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .monospacedDigit()
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.08), in: .capsule)
                .accessibilityLabel(vm.visitTimer.accessibilityElapsedLabel)
        }
        
        private func actionRow(_ vm: PetDetailViewModel) -> some View {
            HStack(spacing: 8) {
                Button("View History", systemImage: "doc.text.magnifyingglass", action: vm.showHistory)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Check In", systemImage: "play.circle.fill", action: vm.checkIn)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(vm.activeVisit != nil)
                Button("Check Out", systemImage: "checkmark.circle.fill", action: vm.showCheckout)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.activeVisit == nil)
            }
            .padding(.horizontal)
        }
        
        private func visitsSection(_ vm: PetDetailViewModel) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent History").font(.headline)
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
                if vm.sortedVisits.isEmpty {
                    ContentUnavailableView("No Visits Yet", systemImage: "calendar.badge.plus")
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.sortedVisits) { visit in
                            NavigationLink(destination: VisitDetailView(visit: visit)) {
                                VisitTimelineRow(visit: visit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
