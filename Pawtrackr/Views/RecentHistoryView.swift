//
//  RecentHistoryView.swift
//  Pawtrackr
//
//  Updated by Assistant on 2025-09-03 to use a ViewModel.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecentHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RecentHistoryViewModel?
    private var initialScope: RecentHistoryViewModel.Scope?
    private var initialQuery: String?

    init(initialScope: RecentHistoryViewModel.Scope? = nil, initialQuery: String? = nil) {
        self.initialScope = initialScope
        self.initialQuery = initialQuery
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    @Bindable var bvm = viewModel
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header(bvm)
                            summaryChips(viewModel).padding(.horizontal)
                            visitList(viewModel)
                        }
                        .padding(.top, 8)
                        .animation(.default, value: viewModel.scope)
                    }
                } else {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Recent History")
            .toolbar { if let viewModel { toolbarContent(viewModel) } }
            .refreshable { viewModel?.fetchVisits() }
            .task {
                if viewModel == nil {
                    let vm = RecentHistoryViewModel(modelContext: modelContext)
                    if let s = initialScope { vm.scope = s }
                    if let q = initialQuery { vm.query = q }
                    viewModel = vm
                }
            }
        }
        
    }
    
    private func header(@Bindable _ viewModel: RecentHistoryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(text: $viewModel.query)
            ScopePicker(scope: $viewModel.scope)
        }
        .padding(.horizontal)
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
            ProgressView().padding(.top, 40)
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
