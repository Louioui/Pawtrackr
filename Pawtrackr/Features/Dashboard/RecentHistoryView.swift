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
    @Namespace private var visitHeroNamespace
    @State private var viewModel: RecentHistoryViewModel?
    private var initialScope: RecentHistoryViewModel.Scope?
    private var initialQuery: String?

    init(initialScope: RecentHistoryViewModel.Scope? = nil, initialQuery: String? = nil) {
        self.initialScope = initialScope
        self.initialQuery = initialQuery
    }

    var body: some View {
        recentHistoryContent
            .navigationTitle(NSLocalizedString("history.title", value: "Recent History", comment: ""))
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
            loadingState
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
        .alert(item: Binding(
            get: { viewModel.appError },
            set: { viewModel.appError = $0 }
        )) { error in
            Alert(
                title: Text(NSLocalizedString("history.error_title", value: "History Error", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
    }
    
    private func deleteVisit(_ visit: Visit) {
        Task {
            do {
                let repository = VisitRepository(modelContainer: dataStore.container, eventBus: eventBus)
                try await repository.deleteVisit(visit)
                HapticManager.notify(.success)
                viewModel?.fetchVisits()
            } catch {
                HapticManager.notify(.error)
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "deleting visit history")
                viewModel?.appError = .database(error.localizedDescription)
            }
        }
    }

    private func header(_ viewModel: RecentHistoryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(text: queryBinding(for: viewModel), accessibilityIdentifier: "recentHistory.search")
            ScopePicker(scope: scopeBinding(for: viewModel))
                .accessibilityIdentifier("recentHistory.scope")
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
            .accessibilityIdentifier("recentHistory.loading")
        } else if viewModel.sortedDays.isEmpty {
            let message = viewModel.query.isEmpty ? NSLocalizedString("history.empty_desc", comment: "") : NSLocalizedString("history.no_results_desc", comment: "")
            ContentUnavailableView(viewModel.query.isEmpty ? NSLocalizedString("history.empty_title", comment: "") : NSLocalizedString("history.no_results_title", comment: ""), systemImage: "clock.badge.questionmark", description: Text(message))
                .padding(.top, 40)
                .accessibilityIdentifier("recentHistory.empty")
        } else {
            LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.sortedDays, id: \.self) { day in
                    Section {
                        if let visits = viewModel.groupedVisits[day] {
                            ForEach(visits) { visit in
                                NavigationLink(destination: VisitDetailView(visit: visit, heroNamespace: visitHeroNamespace)) {
                                    VisitRow(visit: visit, heroNamespace: visitHeroNamespace)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteVisit(visit)
                                    } label: { Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash") }
                                }
                            }
                        }
                    } header: {
                        SectionHeader(date: day)
                    }
                }
            }
            .padding(.horizontal)
            .accessibilityIdentifier("recentHistory.list")
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(_ viewModel: RecentHistoryViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let csv = viewModel.exportCSV()
            ShareLink(
                item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_History.csv"),
                preview: SharePreview(NSLocalizedString("history.title", value: "Recent History", comment: ""), icon: Image(systemName: "doc.text.fill"))
            ) {
                Label(NSLocalizedString("common.export", comment: ""), systemImage: "square.and.arrow.up")
            }
            .disabled(csv.isEmpty)
        }
    }

    private var loadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSkeleton
                summaryChipsSkeleton
                historyRowsSkeleton
            }
            .padding(.top, 8)
        }
    }

    private var headerSkeleton: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 44)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.10))
                .frame(height: 32)
        }
        .padding(.horizontal)
        .redacted(reason: .placeholder)
    }

    private var summaryChipsSkeleton: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 96, height: 28)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 120, height: 28)
        }
        .padding(.horizontal)
        .redacted(reason: .placeholder)
    }

    private var historyRowsSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                Card(elevation: .regular) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.secondary.opacity(0.15)).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 180, height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 140, height: 10)
                        }
                        Spacer()
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
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
