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
                controls(vm)
                    .padding(.horizontal)

                if vm.isLoading && vm.filtered.isEmpty {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if vm.visits.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("pet_history.empty_title", comment: ""),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(String(format: NSLocalizedString("pet_history.empty_desc_fmt", comment: ""), vm.pet.name))
                    )
                    .padding(.top, 40)
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView(
                        "No Matching Visits",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different service, note, or reference.")
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
        .alert(item: Binding(
            get: { vm.appError },
            set: { vm.appError = $0 }
        )) { error in
            Alert(
                title: Text("History Error"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
        .task { await vm.refresh() }
    }

    private func visitList(_ vm: PetHistoryViewModel) -> some View {
        let groups = Dictionary(grouping: vm.filtered, by: { Calendar.current.startOfDay(for: $0.sortKeyDate) })
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

            if vm.canLoadMore {
                Button {
                    vm.loadMore()
                } label: {
                    HStack(spacing: 8) {
                        if vm.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(NSLocalizedString("common.load_more", comment: "Load More"))
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func controls(_ vm: PetHistoryViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(spacing: 10) {
            SearchField(text: $vm.searchText)
            Picker("History Range", selection: $vm.scope) {
                ForEach(PetHistoryViewModel.Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        }
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
