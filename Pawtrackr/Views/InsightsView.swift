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
                            revenueSummaryCard(vm)
                            revenueChart(vm)
                            topRevenueServices(vm)
                            topServices(vm)
                            topClients(vm)
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

    private func revenueSummaryCard(_ vm: InsightsViewModel) -> some View {
        Card(elevation: .raised, accent: .leading(.color(Color.green.opacity(0.8)))) {
            VStack(spacing: 16) {
                // Main revenue display
                VStack(spacing: 4) {
                    Text(vm.scope.displayDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(vm.totalRevenueString)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                        .monospacedDigit()
                }

                Divider()

                // Stats row
                HStack(spacing: 0) {
                    // Visits count
                    VStack(spacing: 4) {
                        Text("\(vm.totalVisitsInPeriod)")
                            .font(.title2.bold())
                            .monospacedDigit()
                        Text("Visits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 40)

                    // Average per visit
                    VStack(spacing: 4) {
                        Text(vm.averagePerVisitString)
                            .font(.title2.bold())
                            .monospacedDigit()
                        Text("Avg/Visit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 40)

                    // Today's revenue quick view (always shows today regardless of filter)
                    VStack(spacing: 4) {
                        Text(vm.revenueTodayString)
                            .font(.title2.bold())
                            .foregroundStyle(Color.blue)
                            .monospacedDigit()
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider()

                // Smarter revenue context: average/day, momentum, and best day
                HStack(spacing: 0) {
                    summaryStat(title: "Avg/Day",
                                value: vm.averageDailyRevenueString,
                                subtitle: vm.activePeriodDays > 0 ? "\(vm.activePeriodDays)d window" : "Select a range")
                        .frame(maxWidth: .infinity)

                    Divider().frame(height: 40)

                    let isPositive = vm.revenueChangeAmount >= 0
                    summaryStat(title: vm.revenueChangeComparisonLabel,
                                value: vm.revenueChangeAmountString,
                                subtitle: vm.revenueChangePercentString,
                                valueColor: isPositive ? .green : .red)
                        .frame(maxWidth: .infinity)

                    if let best = vm.bestRevenueDay {
                        Divider().frame(height: 40)
                        summaryStat(title: "Best Day",
                                    value: best.amount.moneyString,
                                    subtitle: Formatters.dateOnly.string(from: best.date))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func summaryStat(title: String, value: String, subtitle: String? = nil, valueColor: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .monospacedDigit()
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("insights.revenue_trend").font(.subheadline.weight(.semibold))
                        Text(vm.activeRangeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Show selected day's revenue when touching chart
                    if let date = selectedRevenueDate,
                       let amount = vm.revenueSeries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.amount {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(amount.moneyString)
                                .font(.headline.bold())
                                .foregroundStyle(Color.green)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if vm.revenueSeries.isEmpty {
                    ContentUnavailableView {
                        Label("No Revenue Data", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Complete checkouts to see your revenue trend here.")
                    }
                    .frame(height: 180)
                } else {
                    Chart {
                        ForEach(vm.revenueSeries) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Revenue", point.amountDouble)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.7), Color.green],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .cornerRadius(4)
                        }

                        // Highlight selected bar
                        if let date = selectedRevenueDate,
                           let point = vm.revenueSeries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                            RuleMark(x: .value("Selected", point.date, unit: .day))
                                .foregroundStyle(Color.green.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        }

                        // Moving average overlay to smooth noisy revenue series
                        ForEach(vm.revenueMovingAverage) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Avg", point.amountDouble)
                            )
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(.init(lineWidth: 2))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: vm.scope == .today || vm.scope == .yesterday ? 1 : 5)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            AxisValueLabel {
                                if let doubleValue = value.as(Double.self) {
                                    Text("$\(Int(doubleValue))")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
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
                    .animation(.easeOut(duration: 0.35), value: vm.scope)
                }
            }
        }
        #endif
    }
    
    private func topServices(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("insights.top_services").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.serviceLeaders.count) services")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vm.serviceLeaders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No Service Data")
                            .font(.subheadline.weight(.medium))
                        Text("Complete checkouts with services to see your top performers here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 8) {
                        ForEach(vm.serviceLeaders) { row in
                            NavigationLink(destination: ServiceTrendView(serviceName: row.name)) {
                                TopServiceRow(row: row, maxCount: vm.serviceLeaders.first?.count ?? 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func topRevenueServices(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top Services by Revenue").font(.subheadline.weight(.semibold))
                        Text(vm.totalRevenueString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if vm.topRevenueServices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No revenue yet")
                            .font(.subheadline.weight(.medium))
                        Text("Complete checkouts to see which services drive revenue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.topRevenueServices) { row in
                            TopRevenueServiceRow(row: row, maxRevenue: vm.topRevenueServices.first?.revenue ?? .zero)
                        }
                    }
                }
            }
        }
    }

    private func topClients(_ vm: InsightsViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top Clients").font(.subheadline.weight(.semibold))
                        Text("By revenue in selected period")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if vm.topClients.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No Client Data")
                            .font(.subheadline.weight(.medium))
                        Text("Complete checkouts to see your top clients and their preferences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.topClients) { client in
                            TopClientRowView(client: client, maxSpent: vm.topClients.first?.totalSpent ?? .zero)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Top Service Row Component

private struct TopServiceRow: View {
    let row: InsightsViewModel.CountRow
    let maxCount: Int

    private var progress: Double {
        guard maxCount > 0 else { return 0 }
        return Double(row.count) / Double(maxCount)
    }

    private var rankColor: Color {
        switch row.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary.opacity(0.5)
        }
    }

    private var rankIcon: String {
        switch row.rank {
        case 1: return "trophy.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                if row.rank <= 3 {
                    Image(systemName: rankIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(rankColor)
                } else {
                    Text("\(row.rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(row.countString)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.rank == 1 ? Color.green : .primary)
                }

                // Progress bar showing relative popularity
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: row.rank == 1 ? [Color.green.opacity(0.7), Color.green] : [Color.blue.opacity(0.5), Color.blue.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct TopRevenueServiceRow: View {
    let row: InsightsViewModel.ServiceRevenueRow
    let maxRevenue: Decimal

    private var progress: Double {
        guard maxRevenue > 0 else { return 0 }
        return (row.revenue as NSDecimalNumber).doubleValue / (maxRevenue as NSDecimalNumber).doubleValue
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text("\(row.rank)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(row.revenueString)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 4)
                            Capsule()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text(row.shareString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Top Client Row Component

private struct TopClientRowView: View {
    let client: InsightsViewModel.TopClientRow
    let maxSpent: Decimal

    private var progress: Double {
        guard maxSpent > 0 else { return 0 }
        return (client.totalSpent as NSDecimalNumber).doubleValue / (maxSpent as NSDecimalNumber).doubleValue
    }

    private var rankColor: Color {
        switch client.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary.opacity(0.5)
        }
    }

    private var rankIcon: String {
        switch client.rank {
        case 1: return "crown.fill"
        case 2: return "star.fill"
        case 3: return "star.fill"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                if client.rank <= 3 {
                    Image(systemName: rankIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(rankColor)
                } else {
                    Text("\(client.rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(client.clientName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(client.totalSpentString)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(client.rank == 1 ? Color.green : .primary)
                }

                HStack(spacing: 8) {
                    // Visit count
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(client.visitCount) visit\(client.visitCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Favorite service (if available)
                    if let favService = client.favoriteService {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.pink)
                            Text(favService)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                // Progress bar showing relative spending
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: client.rank == 1 ? [Color.green.opacity(0.7), Color.green] : [Color.purple.opacity(0.5), Color.purple.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
