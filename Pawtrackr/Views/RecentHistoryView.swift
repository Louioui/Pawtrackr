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
            .task { viewModel = RecentHistoryViewModel(modelContext: modelContext) }
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
            Chip.info("\(viewModel.summaryVisitCount) visits")
            Chip.info(viewModel.summaryRevenueString)
        }
    }

    @ViewBuilder
    private func visitList(_ viewModel: RecentHistoryViewModel) -> some View {
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
                            NavigationLink(destination: VisitDetailView(visit: visit)) {
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
    private func toolbarContent(_ viewModel: RecentHistoryViewModel) -> some ToolbarContent {
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
