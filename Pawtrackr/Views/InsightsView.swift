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
                    .refreshable {
                        await MainActor.run { vm.refresh() }
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
        .alert("common.error", isPresented: showErrorAlert) {
            Button("common.ok") {}
        } message: {
            Text(viewModel?.errorMessage ?? NSLocalizedString("errors.unknown", comment: "Unknown error message"))
        }
    }

    @ViewBuilder
    private func content(_ vm: InsightsViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                filtersSection(vm)
                kpiRibbon(vm)
                kpiGrid(vm)
                revenueChart(vm)
                topServices(vm)
                visitsByPackage(vm)
                packageMix(vm)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .refreshable {
            await MainActor.run { vm.refresh() }
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
                        Label("insights.compare.apply", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bvm.customDraftEnd < bvm.customDraftStart)
                }

                Divider()

                Toggle("insights.compare.title", isOn: $bvm.enableComparison.animation())

                if bvm.enableComparison {
                    Picker("insights.compare.scope", selection: $bvm.comparisonScope) {
                        ForEach(InsightsViewModel.Scope.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.segmented)

                    if vm.comparisonScope == .custom {
                        DatePicker("insights.compare.start_date", selection: $bvm.comparisonCustomDraftStart, in: ...Date(), displayedComponents: .date)
                        DatePicker("insights.compare.end_date", selection: $bvm.comparisonCustomDraftEnd, in: bvm.comparisonCustomDraftStart..., displayedComponents: .date)
                        Button(action: { vm.applyComparisonCustomDates() }) {
                            Label("insights.compare.apply", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(bvm.comparisonCustomDraftEnd < bvm.comparisonCustomDraftStart)
                    }
                }
            }
        }
    }

    private func kpiGrid(_ vm: InsightsViewModel) -> some View {
        let avgDurationString = Formatters.durationString(seconds: Int(vm.kpis.averageDurationSeconds.rounded()), abbreviated: false)
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                KPI(title: "insights.revenue", value: vm.kpis.revenueString)
                KPI(title: "insights.total_visits", value: "\(vm.kpis.count)")
            }
            GridRow {
                KPI(title: "insights.aov", value: vm.kpis.aovString)
                KPI(title: "insights.avg_duration", value: avgDurationString)
            }
        }
    }

    // A more visual ribbon to echo the sample UI style
    private func kpiRibbon(_ vm: InsightsViewModel) -> some View {
        let revenueDelta: String?
        let revenueTrendUp: Bool?
        let visitsDelta: String?
        let visitsTrendUp: Bool?

        if vm.enableComparison && vm.comparisonKpis.revenue > 0 {
            let change = (vm.kpis.revenue - vm.comparisonKpis.revenue) / vm.comparisonKpis.revenue
            let changeAsDouble = NSDecimalNumber(decimal: change).doubleValue
            revenueTrendUp = changeAsDouble >= 0
            revenueDelta = String(format: "%.1f%%", abs(changeAsDouble * 100))
        } else {
            revenueDelta = nil
            revenueTrendUp = nil
        }
        
        if vm.enableComparison && vm.comparisonKpis.count > 0 {
            let change = Double(vm.kpis.count - vm.comparisonKpis.count) / Double(vm.comparisonKpis.count)
            visitsTrendUp = change >= 0
            visitsDelta = String(format: "%.1f%%", abs(change * 100))
        } else {
            visitsDelta = nil
            visitsTrendUp = nil
        }

        return HStack(spacing: 12) {
            RibbonCard(
                icon: "dollarsign",
                title: "insights.revenue",
                value: vm.kpis.revenueString,
                tint: .green,
                delta: revenueDelta,
                trendUp: revenueTrendUp
            )
            RibbonCard(
                icon: "checkmark.circle",
                title: "insights.visits",
                value: "\(vm.kpis.count)",
                tint: .blue,
                delta: visitsDelta,
                trendUp: visitsTrendUp
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
                if let date = selectedRevenueDate,
                   let amount = vm.revenueSeries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.amount {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(amount.moneyString)
                        .font(.title3.bold())
                } else {
                    Text(vm.kpis.revenueString)
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
                        if vm.enableComparison {
                            ForEach(vm.comparisonRevenueSeries) { point in
                                LineMark(
                                    x: .value("Comparison Date", point.date, unit: .day),
                                    y: .value("Comparison Revenue", point.amountDouble)
                                )
                                .foregroundStyle(.gray)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            }
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
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: max(160, CGFloat(vm.packageLeaders.count) * 32 + 40))
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
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
                if vm.packageMix.isEmpty {
                    ContentUnavailableView(NSLocalizedString("insights.no_package_data", comment: ""), systemImage: "chart.pie")
                        .frame(height: 160)
                } else {
                    Chart(vm.packageMix) { row in
                        SectorMark(
                            angle: .value("Count", row.count)
                        )
                        .foregroundStyle(by: .value("Name", row.name))
                    }
                    .frame(height: 180)
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
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
    let title: LocalizedStringKey
    let value: String
    let tint: Color
    let delta: String?
    let trendUp: Bool?

    init(icon: String, title: LocalizedStringKey, value: String, tint: Color, delta: String? = nil, trendUp: Bool? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tint = tint
        self.delta = delta
        self.trendUp = trendUp
    }

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
