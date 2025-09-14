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
import UniformTypeIdentifiers

// FIX: Create a Transferable struct to correctly handle CSV data for ShareLink.
struct CSVDoc: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .commaSeparatedText) { doc in
            doc.data
        } importing: { data in
            CSVDoc(data: data, filename: "data.csv")
        }
        .suggestedFileName { doc in
            doc.filename
        }
    }
}

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    @Bindable var bvm = vm
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            filtersSection(vm)
                            kpiRibbon(vm)
                            revenueChart(vm)
                            visitsByPackage(vm)
                            packageMix(vm)
                            topServices(vm)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .toolbar { toolbar(vm) }
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
            .navigationTitle("insights.title")
            .task { if viewModel == nil { viewModel = InsightsViewModel(modelContext: modelContext) } }
        }
    }

    // MARK: - Sections
    
    private func filtersSection(_ vm: InsightsViewModel) -> some View {
        @Bindable var bvm = vm
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("insights.filters").font(.subheadline.weight(.semibold))

                Picker("Scope", selection: $bvm.scope) {
                    ForEach(InsightsViewModel.Scope.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)

                if vm.scope == .custom {
                    DatePicker("Start Date", selection: $bvm.customDraftStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("End Date", selection: $bvm.customDraftEnd, in: bvm.customDraftStart..., displayedComponents: .date)
                    Button(action: { vm.applyCustomDates() }) {
                        Label("Apply Range", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bvm.customDraftEnd < bvm.customDraftStart)
                }
                // Search removed per request: Insights should not expose a search UI.
            }
        }
    }

    private func kpiGrid(_ vm: InsightsViewModel) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                KPI(title: "insights.revenue", value: vm.kpis.revenueString)
                KPI(title: "insights.total_visits", value: "\(vm.kpis.count)")
            }
            GridRow {
                KPI(title: "insights.aov", value: vm.kpis.aovString)
                KPI(title: "insights.avg_duration", value: vm.kpis.avgDurationString)
            }
        }
    }

    // A more visual ribbon to echo the sample UI style
    private func kpiRibbon(_ vm: InsightsViewModel) -> some View {
        HStack(spacing: 12) {
            RibbonCard(
                icon: "dollarsign",
                title: "insights.revenue",
                value: vm.kpis.revenueString,
                tint: .green
            )
            RibbonCard(
                icon: "checkmark.circle",
                title: "insights.visits",
                value: "\(vm.kpis.count)",
                tint: .blue
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func revenueChart(_ vm: InsightsViewModel) -> some View {
        #if canImport(Charts)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("insights.revenue_trend").font(.subheadline.weight(.semibold))
                if vm.revenueSeries.isEmpty {
                    ContentUnavailableView(NSLocalizedString("insights.no_revenue", comment: ""), systemImage: "chart.bar.xaxis")
                        .frame(height: 180)
                } else {
                    Chart(vm.revenueSeries) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Revenue", point.amount)
                        )
                        .foregroundStyle(DS.ColorToken.primary.gradient)
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 180)
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
                            LeaderRow(title: row.name, trailing: row.countString, rank: index + 1)
                        }
                    }
                }
            }
        }
    }
    
    // Top Clients section removed

    // MARK: - Additional Sections inspired by sample
    @ViewBuilder
    private func visitsByPackage(_ vm: InsightsViewModel) -> some View {
        #if canImport(Charts)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("insights.visits_by_package").font(.subheadline.weight(.semibold))
                if vm.packageLeaders.isEmpty {
                    ContentUnavailableView("No package data", systemImage: "chart.bar")
                        .frame(height: 160)
                } else {
                    Chart(vm.packageLeaders) { row in
                        BarMark(
                            x: .value("Count", row.count),
                            y: .value("Package", row.name)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .frame(height: max(160, CGFloat(vm.packageLeaders.count) * 24 + 40))
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
                    // keep identity stable to avoid heavy view rebuilds
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func packageMix(_ vm: InsightsViewModel) -> some View {
        #if canImport(Charts)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("insights.package_mix").font(.subheadline.weight(.semibold))
                if vm.categoryTotals.isEmpty {
                    ContentUnavailableView(NSLocalizedString("insights.no_category", comment: ""), systemImage: "chart.pie")
                        .frame(height: 160)
                } else {
                    Chart(vm.categoryTotals) { row in
                        SectorMark(
                            angle: .value("Count", row.count)
                        )
                        .foregroundStyle(by: .value("Category", row.name))
                    }
                    .frame(height: 180)
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
                    // keep identity stable to avoid heavy view rebuilds
                }
            }
        }
        #endif
    }

    // (Header removed to avoid duplicate "Insights" with the navigation title.)

    @ToolbarContentBuilder
    private func toolbar(_ vm: InsightsViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let csv = vm.exportCSV
            ShareLink(
                item: CSVDoc(data: Data(csv.utf8), filename: "Pawtrackr_Insights.csv"),
                preview: SharePreview("Pawtrackr Insights", icon: Image(systemName: "doc.text.fill"))
            ) {
                Label("common.export", systemImage: "square.and.arrow.up")
            }
            .disabled(csv.isEmpty)
            .accessibilityHint(csv.isEmpty ? "No data to export for the current filters" : "Shares a CSV of the current Insights")
        }
    }
}

// MARK: - Small Components (can be moved to a shared file)

// FIX: Implemented the KPI view to conform to View.
private struct KPI: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.ColorToken.surface)
        )
        .animation(.default, value: value)
    }
}

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

// Small ribbon card to echo the sample KPI style
private struct RibbonCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    let delta: String? = nil
    let trendUp: Bool? = nil

    var body: some View {
        Card(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12), elevation: .raised, showBorder: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).foregroundStyle(tint)
                    Spacer()
                }
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let delta {
                    HStack(spacing: 4) {
                        if trendUp != nil {
                            Image(systemName: (trendUp ?? false) ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle((trendUp ?? false) ? .green : .red)
                        }
                        Text(delta)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// IMPROVEMENT: A dedicated search field component.
private struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .disableAutocorrection(true)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .circular)
                .fill(DS.ColorToken.surface)
        )
    }
}
