//
//  DashboardView.swift
//  Pawtrackr
//
//  Created by mac on 9/11/25.
//

import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

  struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm: DashboardViewModel?
    @State private var showNewClient = false
    @State private var clientPendingDeletion: Client? = nil
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage: String = ""
    @State private var showContent = false
    private let clientsCoordinator: ClientsCoordinator

    init() {
        clientsCoordinator = ClientsCoordinator(navigationController: UINavigationController())
    }

  var body: some View {
    NavigationStack {
      Group {
        if let vm { content(vm) }
        else {
          ProgressView()
            .task {
              let model = DashboardViewModel(modelContext: modelContext)
              await model.refresh()
              vm = model
            }
        }
      }
      .navigationTitle("Dashboard")
      .sheet(isPresented: $showNewClient) {
        NewClientSheet() // you already have this
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          NavigationLink(destination: InsightsView()) {
            Image(systemName: "chart.bar")
          }
          .accessibilityLabel("Open Insights")
        }
      }
      // Confirm delete client
      .alert(
        clientPendingDeletion.map { String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), $0.fullName) } ?? "",
        isPresented: Binding(
          get: { clientPendingDeletion != nil },
          set: { if !$0 { clientPendingDeletion = nil } }
        )
      ) {
        Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { clientPendingDeletion = nil }
        Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
          if let vm { deletePendingClient(vm) }
        }
      } message: {
        Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
      }
      .alert(NSLocalizedString("clients.delete_failed", comment: ""), isPresented: $showDeleteErrorAlert) {
        Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
      } message: {
        Text(deleteErrorMessage)
      }
    }
  }

  @ViewBuilder
  private func content(_ vm: DashboardViewModel) -> some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        if showContent {
            kpiSection(vm)
                .transition(.move(edge: .leading).combined(with: .opacity))
            quickActionsSection
                .transition(.move(edge: .trailing).combined(with: .opacity))
            if !vm.activeVisits.isEmpty { activeSessionsSection(vm).transition(.move(edge: .leading).combined(with: .opacity)) }
            if !vm.recentClients.isEmpty { recentClientsSection(vm).transition(.move(edge: .trailing).combined(with: .opacity)) }
            revenueSection(vm)
                .transition(.move(edge: .leading).combined(with: .opacity))
            if !vm.gallery.isEmpty { gallerySection(vm).transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 24)
    }
    .onAppear {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showContent = true
        }
    }
    .refreshable { await vm.refresh() }
  }

  // MARK: Sections
  private func kpiSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.today", comment: "")).font(.headline)
      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          NavigationLink { RecentHistoryView(initialScope: .today) } label: {
            kpiCard(title: "Appointments", value: vm.kpi.appointmentsTodayText, symbol: "calendar")
          }
          NavigationLink { RecentHistoryView(initialScope: .today) } label: {
            kpiCard(title: "In Progress",  value: "\(vm.kpi.inProgressCount)",   symbol: "hourglass")
          }
        }
        GridRow {
          NavigationLink { InsightsView() } label: {
            kpiCard(title: "Revenue",     value: vm.kpi.revenueTodayString,      symbol: "dollarsign.circle")
          }
          NavigationLink { RecentHistoryView(initialScope: .today) } label: {
            kpiCard(title: "Completed",   value: "\(vm.kpi.completedToday)",      symbol: "checkmark.circle")
          }
        }
      }
    }
  }

  private var quickActionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.quick_actions", comment: "")).font(.headline)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          actionCard(title: NSLocalizedString("dashboard.new_client", comment: ""), symbol: "person.crop.circle.badge.plus") { showNewClient = true }
          NavigationLink { ClientsView(coordinator: clientsCoordinator) } label: { actionCardLabel(title: NSLocalizedString("dashboard.check_in", comment: ""), symbol: "play.circle") }
          NavigationLink { RecentHistoryView() } label: { actionCardLabel(title: NSLocalizedString("dashboard.check_out", comment: ""), symbol: "stop.circle") }
          NavigationLink { InsightsView() } label: { actionCardLabel(title: NSLocalizedString("dashboard.reports", comment: ""), symbol: "doc.chart") }
        }
      }
    }
  }

  private func activeSessionsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.active_sessions", comment: "")).font(.headline)
      LazyVStack(spacing: 10) {
        ForEach(vm.activeVisits) { visit in
          ActiveVisitRow(visit: visit)
        }
      }
    }
  }

  private func recentClientsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(NSLocalizedString("dashboard.recent_clients", comment: "")).font(.headline)
        Spacer()
        NavigationLink(NSLocalizedString("dashboard.view_all", comment: ""), destination: ClientsView())
          .font(.footnote)
      }
      LazyVStack(spacing: 10) {
        ForEach(vm.recentClients.prefix(5)) { client in
          NavigationLink { ClientDetailView(client: client, coordinator: clientsCoordinator, namespace: Namespace().wrappedValue) } label: { ClientRow(client: client) }
            .buttonStyle(.plain)
            .contextMenu {
              Button(role: .destructive) {
                clientPendingDeletion = client
              } label: {
                Label(NSLocalizedString("client_details.delete", comment: ""), systemImage: "trash")
              }
            }
        }
      }
    }
  }

  @ViewBuilder
  private func revenueSection(_ vm: DashboardViewModel) -> some View {
    #if canImport(Charts)
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.revenue_7d", comment: "")).font(.headline)
      Card {
        if vm.revenueSeries.isEmpty {
          ContentUnavailableView(NSLocalizedString("dashboard.no_revenue_yet", comment: ""), systemImage: "chart.bar.xaxis", description: Text(NSLocalizedString("dashboard.no_revenue_desc", comment: "")))
            .frame(height: 180)
        } else {
          Chart(vm.revenueSeries) { point in
            BarMark(
              x: .value("Day", point.date, unit: .day),
              y: .value("Revenue", point.amountDouble)
            )
          }
          .frame(height: 180)
        }
      }
    }
    #else
    EmptyView()
    #endif
  }

  // MARK: - Delete
  private func deletePendingClient(_ vm: DashboardViewModel) {
    guard let client = clientPendingDeletion else { return }
    modelContext.delete(client)
    do {
      try modelContext.save()
      clientPendingDeletion = nil
      Task { await vm.refresh() }
    } catch {
      deleteErrorMessage = error.localizedDescription
      showDeleteErrorAlert = true
    }
  }

  private func gallerySection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.pet_gallery", comment: "")).font(.headline)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(vm.gallery) { item in
          Card {
            if let uiImage = item.uiImage {
              Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(height: 120).clipped().cornerRadius(8)
            } else {
              LabelContent(title: "No Photo", systemImage: "photo")
            }
          }
        }
      }
    }
  }

  private func kpiCard(title: String, value: String, symbol: String) -> some View {
    Card {
      HStack(alignment: .top) {
        IconCircle(systemImage: symbol, size: .md)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.footnote).foregroundStyle(.secondary)
          Text(value)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
        }
        Spacer()
      }
    }
  }

  private func actionCard(title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { actionCardLabel(title: title, symbol: symbol) }
      .buttonStyle(.plain)
  }

  private func actionCardLabel(title: String, symbol: String) -> some View {
    Card {
      VStack(spacing: 8) {
        IconCircle(systemImage: symbol, size: .lg)
        Text(title).font(.body.weight(.medium))
      }
      .frame(width: 150, height: 110)
    }
  }
}
