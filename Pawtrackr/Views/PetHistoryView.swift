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

struct PetHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PetHistoryViewModel

    init(pet: Pet) {
        // The modelContext is available via the pet object itself.
        // It's safe to force-unwrap here because a managed model will always have a context.
        _viewModel = StateObject(wrappedValue: PetHistoryViewModel(pet: pet, modelContext: pet.modelContext!))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                        .padding(.horizontal)

                    if viewModel.visits.isEmpty {
                        ContentUnavailableView(
                            NSLocalizedString("pet_history.empty_title", comment: ""),
                            systemImage: "clock.arrow.circlepath",
                            description: Text(String(format: NSLocalizedString("pet_history.empty_desc_fmt", comment: ""), viewModel.pet.name))
                        )
                        .padding(.top, 40)
                    } else {
                        visitList
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle(viewModel.pet.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task { await viewModel.refresh() }
        }
    }

    private var visitList: some View {
        let groups = Dictionary(grouping: viewModel.visits, by: { Calendar.current.startOfDay(for: $0.sortKeyDate) })
        let sortedDays = groups.keys.sorted(by: >)
        let lastVisitID = viewModel.visits.last?.id

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

    private var headerCard: some View {
        Card(accent: .top(.color(DS.ColorToken.gender(viewModel.pet.gender)))) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(.pet(species: viewModel.pet.species, gender: viewModel.pet.gender, name: viewModel.pet.name, imageData: viewModel.pet.photoData), size: .lg)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.pet.name).font(.title3.weight(.semibold))
                    Text(viewModel.pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        let visits = viewModel.totalVisits
                        let visitsText = String.localizedStringWithFormat(NSLocalizedString("visits.count", comment: "visit count"), visits)
                        Chip.info(visitsText)
                        Chip.info(String(format: "%@ %@", NSLocalizedString("visits.avg_duration", comment: "avg duration short"), viewModel.averageDurationString))
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            let data = viewModel.exportCSV()
            ShareLink(
                item: CSVDoc(data: data, filename: "\(viewModel.pet.name)_History.csv"),
                preview: SharePreview("Pet History", icon: Image(systemName: "doc.text.fill"))
            ) {
                Label("common.export", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.filtered.isEmpty)
        }
    }
}
