//
//  PetHistoryView.swift
//  Pawtrackr
//
//  Shows a pet’s visit history/timeline.
//  Updated by Assistant on 2025-09-03.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// A wrapper to make CSV data transferable for use with ShareLink.
struct CSVDoc: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .commaSeparatedText) { doc in
            doc.data
        } importing: { data in
            // Default filename for imported data, can be ignored.
            CSVDoc(data: data, filename: "data.csv")
        }
        .suggestedFileName { doc in
            doc.filename
        }
    }
}

struct PetHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var envModelContext
    @State private var viewModel: PetHistoryViewModel? = nil
    private let pet: Pet
    private let wrapsInNavigationStack: Bool

    init(pet: Pet, wrapsInNavigationStack: Bool = true) {
        self.pet = pet
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                if wrapsInNavigationStack {
                    NavigationStack {
                        historyContent(vm)
                    }
                } else {
                    historyContent(vm)
                }
            } else {
                ProgressView()
                    .task {
                        // Initialize using the pet's context if available, else environment.
                        let ctx = pet.modelContext ?? envModelContext
                        viewModel = PetHistoryViewModel(pet: pet, modelContext: ctx)
                    }
            }
        }
    }

    private func historyContent(_ vm: PetHistoryViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard(vm)
                    .padding(.horizontal)

                if vm.visits.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("pet_history.empty_title", comment: ""),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(String(format: NSLocalizedString("pet_history.empty_desc_fmt", comment: ""), vm.pet.name))
                    )
                    .padding(.top, 40)
                } else {
                    visitList(vm)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(vm.pet.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent(vm) }
        .task { await vm.refresh() }
    }

    private func visitList(_ vm: PetHistoryViewModel) -> some View {
        let groups = Dictionary(grouping: vm.visits, by: { Calendar.current.startOfDay(for: $0.sortKeyDate) })
        let sortedDays = groups.keys.sorted(by: >)

        return LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
            ForEach(sortedDays, id: \.self) { day in
                Section {
                    ForEach(groups[day]!.sorted { $0.sortKeyDate > $1.sortKeyDate }) { visit in
                        NavigationLink(destination: VisitDetailView(visit: visit)) {
                            // Use the new, standalone VisitTimelineRow.
                            VisitTimelineRow(visit: visit)
                        }
                        .buttonStyle(.plain)
                        // Infinite scroll removed (no pagination in current view model)
                    }
                } header: {
                    HStack {
                        Text(day.formatted(date: .abbreviated, time: .omitted))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(.background)
                }
            }

            // Loading indicator removed (view model doesn't expose isLoading)
        }
        .padding(.horizontal)
    }

    private func headerCard(_ vm: PetHistoryViewModel) -> some View {
        Card(elevation: .regular, accent: .leading(.color(DS.ColorToken.gender(vm.pet.gender)), thickness: 4)) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(.pet(species: vm.pet.species, gender: vm.pet.gender, name: vm.pet.name, imageData: vm.pet.photoData), size: .lg)

                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.pet.name).font(.title3.weight(.semibold))
                    Text(vm.pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        let visits = vm.totalVisits
                        let visitsText = String.localizedStringWithFormat(NSLocalizedString("visits.count", comment: "visit count"), visits)
                        Chip.info(visitsText)
                        Chip.info(String(format: "%@ %@",
                                         NSLocalizedString("visits.avg_duration", comment: "avg duration short"), vm.averageDurationString))
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(_ vm: PetHistoryViewModel) -> some ToolbarContent {
        if wrapsInNavigationStack {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                let csvData = vm.exportCSV()
                ShareLink(
                    item: CSVDoc(data: csvData, filename: "\(vm.pet.name)_History.csv"),
                    preview: SharePreview("Pet History", icon: Image(systemName: "doc.text.fill"))
                ) {
                    Label("common.export", systemImage: "tablecells")
                }
                .disabled(vm.filtered.isEmpty)

                let textData = vm.exportPlainText()
                ShareLink(
                    item: textData,
                    preview: SharePreview("Pet History", icon: Image(systemName: "doc.text"))
                ) {
                    Label("common.export_text", systemImage: "doc.text")
                }
                .disabled(vm.filtered.isEmpty)
            } label: {
                Label("common.export", systemImage: "square.and.arrow.up")
            }
        }
    }
}
