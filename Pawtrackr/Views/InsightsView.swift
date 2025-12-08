//
//  InsightsView.swift
//  Pawtrackr
//
//  Business KPIs & Trends dashboard.
//  - Now powered by a performant ViewModel that handles all data fetching and processing.
//  - Uses debounced search and predicate-based filtering for a fast user experience.
//
//  Created by mac on 8/26/25.
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var selectedRevenueDate: Date?

    private var showErrorAlert: Binding<Bool> {
        Binding {
            viewModel?.errorMessage != nil
        } set: { _ in
            viewModel?.clearErrorMessage()
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    @Bindable var bvm = vm
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            filtersSection(vm)
                            revenueChart(vm)
                            topServices(vm)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await MainActor.run { vm.refresh() }
                    }
                    .animation(.default, value: bvm.scope)
                    .overlay {
                        if bvm.isLoading {
                            ProgressView()
                                .padding()
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                } else {
                    ProgressView("Loading Insights...")
                }
            }
            .navigationTitle(Text("insights.title"))
            .task { if viewModel == nil { viewModel = InsightsViewModel(modelContext: modelContext) } }
        }
        .alert("common.error", isPresented: showErrorAlert) {
            Button("common.ok") {}
        } message: {
            Text(viewModel?.errorMessage ?? NSLocalizedString("errors.unknown", comment: "Unknown error message"))
        }
    }

    // MARK: - Sections
    
    private func filtersSection(_ vm: InsightsViewModel) -> some View {
        @Bindable var bvm = vm
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("insights.filters").font(.subheadline.weight(.semibold))
                        Text(vm.activeRangeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                scopeChips(selection: $bvm.scope) {
                    selectedRevenueDate = nil
                }

                if vm.scope == .custom {
                    DatePicker("Start Date", selection: $bvm.customDraftStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("End Date", selection: $bvm.customDraftEnd, in: bvm.customDraftStart..., displayedComponents: .date)
                    Button(action: { vm.applyCustomDates() }) {
                        Label("insights.compare.apply", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bvm.customDraftEnd < bvm.customDraftStart)
                }
            }
        }
    }

    private func scopeChips(selection: Binding<InsightsViewModel.Scope>, onChange: (() -> Void)? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InsightsViewModel.Scope.allCases) { scope in
                    let isSelected = selection.wrappedValue == scope
                    Button {
                        selection.wrappedValue = scope
                        onChange?()
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 62)
                            .background(isSelected ? DS.ColorToken.primary.opacity(0.15) : DS.ColorToken.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? DS.ColorToken.primary.opacity(0.35) : DS.ColorToken.border, lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? DS.ColorToken.primary : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    @ViewBuilder
    private func revenueChart(_ vm: InsightsViewModel) -> some View {
        #if canImport(Charts)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("insights.revenue_trend").font(.subheadline.weight(.semibold))
                    Text(vm.activeRangeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = selectedRevenueDate,
                   let amount = vm.revenueSeries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.amount {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(amount.moneyString)
                        .font(.title3.bold())
                } else {
                    Text(vm.totalRevenueString)
                        .font(.title3.bold())
                }
                if vm.revenueSeries.isEmpty {
                    ContentUnavailableView(NSLocalizedString("insights.no_revenue", comment: ""), systemImage: "chart.bar.xaxis")
                        .frame(height: 180)
                } else {
                    Chart {
                        ForEach(vm.revenueSeries) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Revenue", point.amountDouble)
                            )
                            .foregroundStyle(DS.ColorToken.primary.gradient)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 180)
                    .chartOverlay { proxy in
                        GeometryReader { g in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let x = value.location.x - g[proxy.plotFrame!].origin.x
                                            if let date: Date = proxy.value(atX: x) {
                                                selectedRevenueDate = date
                                            }
                                        }
                                        .onEnded { _ in selectedRevenueDate = nil }
                                )
                        }
                    }
                    // Subtle animation on data changes (scope/timeframe updates)
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
                    // Encourage a small re-layout when scope changes to replay the animation
                    // keep identity stable to avoid heavy view rebuilds
                }
            }
        }
        #endif
    }
    
    private func topServices(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("insights.top_services").font(.subheadline.weight(.semibold))
                if vm.serviceLeaders.isEmpty {
                    Text(NSLocalizedString("insights.no_service_data", comment: "")).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(vm.serviceLeaders.enumerated()), id: \.element.id) { index, row in
                            NavigationLink(destination: ServiceTrendView(serviceName: row.name)) {
                                LeaderRow(title: row.name, trailing: row.countString, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Small Components (can be moved to a shared file)

// FIX: Implemented the LeaderRow view to conform to View.
private struct LeaderRow: View {
    let title: String
    let trailing: String
    var rank: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank).")
                    .frame(width: 24, alignment: .leading)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(title).lineLimit(1)
            Spacer()
            Text(trailing)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}