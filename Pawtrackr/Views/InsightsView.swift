import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?
    @State private var selectedRevenueDate: Date?

    var body: some View {
        insightsContent
            .navigationTitle(Text("insights.title"))
            .task {
                if viewModel == nil {
                    viewModel = InsightsViewModel(modelContext: modelContext)
                }
            }
            .alert(item: appErrorBinding) { error in
                Alert(
                    title: Text(NSLocalizedString("common.error", comment: "")),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
    }

    @ViewBuilder
    private var insightsContent: some View {
        if let vm = viewModel {
            insightsLoadedContent(vm)
        } else {
            ProgressView("Loading Insights...")
        }
    }

    private func insightsLoadedContent(_ vm: InsightsViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                filtersSection(vm)
                revenueSummary(vm)
                revenueChart(vm)
                topServices(vm)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            vm.refresh()
        }
        .animation(.default, value: vm.scope)
        .overlay {
            if vm.isLoading {
                loadingOverlay
            }
        }
    }

    private var loadingOverlay: some View {
        ProgressView()
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appErrorBinding: Binding<AppError?> {
        Binding(
            get: { viewModel?.appError },
            set: { viewModel?.appError = $0 }
        )
    }
    
    // MARK: - Sections
    
    private func filtersSection(_ vm: InsightsViewModel) -> some View {
        Card {
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
                
                scopeChips(selection: scopeBinding(for: vm)) {
                    selectedRevenueDate = nil
                }
                
                if vm.scope == .custom {
                    DatePicker("Start Date", selection: customStartBinding(for: vm), in: ...Date(), displayedComponents: .date)
                    DatePicker("End Date", selection: customEndBinding(for: vm), in: vm.customDraftStart..., displayedComponents: .date)
                    Button(action: { vm.applyCustomDates() }) {
                        Label("insights.compare.apply", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.customDraftEnd < vm.customDraftStart)
                }
            }
            .padding(16)
        }
    }

    private func scopeBinding(for vm: InsightsViewModel) -> Binding<InsightsViewModel.Scope> {
        Binding(
            get: { vm.scope },
            set: { vm.scope = $0 }
        )
    }

    private func customStartBinding(for vm: InsightsViewModel) -> Binding<Date> {
        Binding(
            get: { vm.customDraftStart },
            set: { vm.customDraftStart = $0 }
        )
    }

    private func customEndBinding(for vm: InsightsViewModel) -> Binding<Date> {
        Binding(
            get: { vm.customDraftEnd },
            set: { vm.customDraftEnd = $0 }
        )
    }
    
    private func revenueSummary(_ vm: InsightsViewModel) -> some View {
        Card {
            HStack(spacing: 0) {
                summaryMetric(title: vm.scope.displayDescription, value: vm.totalRevenueString, color: .green)
                Divider().frame(height: 50)
                summaryMetric(title: "Today", value: vm.revenueTodayString, color: .blue)
                Divider().frame(height: 50)
                summaryMetric(title: "Total Visits", value: "\(vm.totalVisitsInPeriod)", color: .primary)
            }
            .padding(.vertical, 16)
        }
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func scopeChips(selection: Binding<InsightsViewModel.Scope>, onChange: (() -> Void)? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let x = value.location.x - g[plotFrame].origin.x
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
            .padding(16)
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
                    ContentUnavailableView("No Service Data", systemImage: "sparkles", description: Text("Complete checkouts with services to see your top performers here."))
                        .frame(height: 180)
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
            .padding(16)
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
