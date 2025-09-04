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
    @State private var viewModel: RecentHistoryViewModel
    
    init() {
        let tempContext = try! ModelContainer(for: Visit.self).mainContext
        _viewModel = State(initialValue: RecentHistoryViewModel(modelContext: tempContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    summaryChips.padding(.horizontal)
                    visitList
                }
                .padding(.top, 8)
                .animation(.default, value: viewModel.scope)
            }
            .navigationTitle("Recent History")
            .toolbar { toolbarContent }
            .refreshable {
                viewModel.fetchVisits()
            }
            .task {
                viewModel.setModelContext(modelContext)
            }
            .navigationDestination(for: Visit.self) { visit in
                VisitDetailView(visit: visit)
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(text: $viewModel.query)
            ScopePicker(scope: $viewModel.scope)
        }
        .padding(.horizontal)
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            Chip.info("\(viewModel.summaryVisitCount) visits")
            Chip.info(viewModel.summaryRevenueString)
        }
    }

    @ViewBuilder
    private var visitList: some View {
        if viewModel.isLoading {
            ProgressView().padding(.top, 40)
        } else if viewModel.sortedDays.isEmpty {
            let message = viewModel.query.isEmpty ? "Completed checkouts will appear here." : "No visits match your search."
            ContentUnavailableView(viewModel.query.isEmpty ? "No Recent History" : "No Results", systemImage: "clock.badge.questionmark", description: Text(message))
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.sortedDays, id: \.self) { day in
                    Section {
                        ForEach(viewModel.groupedVisits[day]!) { visit in
                            NavigationLink(value: visit) {
                                VisitRow(visit: visit)
                            }
                            .buttonStyle(.plain)
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
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let csv = viewModel.exportCSV()
            ShareLink(
                item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_History.csv"),
                preview: SharePreview("Recent History", icon: Image(systemName: "doc.text.fill"))
            ) {
                Label("Export", systemImage: "square.and.arrow.up")
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

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search owner, pet, or service...", text: $text)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(DS.ColorToken.surface, in: .capsule)
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
