//
//  RecentHistoryView.swift
//  Pawtrackr
//
//  Updated by Assistant on 2025-09-03 to use a ViewModel.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct RecentHistoryView: View {
    @Environment(DataStoreService.self) private var dataStore
    @Environment(GlobalEventBus.self) private var eventBus
    @State private var viewModel: RecentHistoryViewModel?
    private var initialScope: RecentHistoryViewModel.Scope?
    private var initialQuery: String?

    init(initialScope: RecentHistoryViewModel.Scope? = nil, initialQuery: String? = nil) {
        self.initialScope = initialScope
        self.initialQuery = initialQuery
    }

    var body: some View {
        recentHistoryContent
            .navigationTitle("Recent History")
            .toolbar { if let viewModel { toolbarContent(viewModel) } }
            .refreshable { viewModel?.fetchVisits() }
            .task {
                if viewModel == nil {
                    let vm = RecentHistoryViewModel(dataStore: dataStore, eventBus: eventBus)
                    if let s = initialScope { vm.scope = s }
                    if let q = initialQuery { vm.query = q }
                    viewModel = vm
                }
            }
    }

    @ViewBuilder
    private var recentHistoryContent: some View {
        if let viewModel {
            loadedContent(viewModel)
        } else {
            ProgressView("Loading…")
        }
    }

    private func loadedContent(_ viewModel: RecentHistoryViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(viewModel)
                summaryChips(viewModel)
                    .padding(.horizontal)
                visitList(viewModel)
            }
            .padding(.top, 8)
            .animated(Animations.fastEaseOut, value: viewModel.scope)
        }
    }
    
    private func deleteVisit(_ visit: Visit) {
        do {
            dataStore.container.mainContext.delete(visit)
            try dataStore.container.mainContext.save()
            HapticManager.notify(.success)
            viewModel?.fetchVisits()
        } catch {
            HapticManager.notify(.error)
        }
    }

    private func header(_ viewModel: RecentHistoryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(text: queryBinding(for: viewModel))
            ScopePicker(scope: scopeBinding(for: viewModel))
        }
        .padding(.horizontal)
    }

    private func queryBinding(for viewModel: RecentHistoryViewModel) -> Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { viewModel.query = $0 }
        )
    }

    private func scopeBinding(for viewModel: RecentHistoryViewModel) -> Binding<RecentHistoryViewModel.Scope> {
        Binding(
            get: { viewModel.scope },
            set: { viewModel.scope = $0 }
        )
    }

    private func summaryChips(_ viewModel: RecentHistoryViewModel) -> some View {
        HStack(spacing: 8) {
            let count = viewModel.summaryVisitCount
            let visitsText = String.localizedStringWithFormat(NSLocalizedString("visits.count", comment: "visit count"), count)
            Chip.info(visitsText)
            Chip.info(viewModel.summaryRevenueString)
        }
    }

    @ViewBuilder
    private func visitList(_ viewModel: RecentHistoryViewModel) -> some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    Card(elevation: .regular) {
                        HStack(spacing: 12) {
                            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 180, height: 12)
                                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 120, height: 10)
                            }
                            Spacer()
                        }
                    }
                    .redacted(reason: .placeholder)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
        } else if viewModel.sortedDays.isEmpty {
            let message = viewModel.query.isEmpty ? NSLocalizedString("history.empty_desc", comment: "") : NSLocalizedString("history.no_results_desc", comment: "")
            ContentUnavailableView(viewModel.query.isEmpty ? NSLocalizedString("history.empty_title", comment: "") : NSLocalizedString("history.no_results_title", comment: ""), systemImage: "clock.badge.questionmark", description: Text(message))
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.sortedDays, id: \.self) { day in
                    Section {
                        if let visits = viewModel.groupedVisits[day] {
                            ForEach(visits) { visit in
                                NavigationLink(destination: VisitDetailView(visit: visit)) {
                                    VisitRow(visit: visit)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteVisit(visit)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    } header: {
                        SectionHeader(date: day)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(_ viewModel: RecentHistoryViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let csv = viewModel.exportCSV()
            ShareLink(
                item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_History.csv"),
                preview: SharePreview("Recent History", icon: Image(systemName: "doc.text.fill"))
            ) {
                Label("common.export", systemImage: "square.and.arrow.up")
            }
            .disabled(csv.isEmpty)
        }
    }
}

// MARK: - Private Subviews (can be moved to a shared file)

private struct ScopePicker: View {
    @Binding var scope: RecentHistoryViewModel.Scope
    var body: some View {
        Picker("Filter Scope", selection: $scope) {
            ForEach(RecentHistoryViewModel.Scope.allCases) { s in Text(s.rawValue).tag(s) }
        }
        .pickerStyle(.segmented)
    }
}



private struct SectionHeader: View {
    let date: Date
    var body: some View {
        Text(date.formatted(date: .complete, time: .omitted))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(.background.opacity(0.9))
    }
}
