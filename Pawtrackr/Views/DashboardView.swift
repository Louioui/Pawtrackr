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
    }
  }

  @ViewBuilder
  private func content(_ vm: DashboardViewModel) -> some View {
    ScrollView {
      VStack(spacing: 16) {
        kpiSection(vm)
        quickActionsSection
        if !vm.activeVisits.isEmpty { activeSessionsSection(vm) }
        if !vm.recentClients.isEmpty { recentClientsSection(vm) }
        revenueSection(vm)
        if !vm.gallery.isEmpty { gallerySection(vm) }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 24)
    }
    .refreshable { await vm.refresh() }
  }

  // MARK: Sections
  private func kpiSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Today").font(.headline)
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
      Text("Quick Actions").font(.headline)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          actionCard(title: "New Client", symbol: "person.crop.circle.badge.plus") { showNewClient = true }
          NavigationLink { ClientsView() } label: { actionCardLabel(title: "Check In", symbol: "play.circle") }
          NavigationLink { RecentHistoryView() } label: { actionCardLabel(title: "Check Out", symbol: "stop.circle") }
          NavigationLink { InsightsView() } label: { actionCardLabel(title: "Reports", symbol: "doc.chart") }
        }
      }
    }
  }

  private func activeSessionsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Active Sessions").font(.headline)
      VStack(spacing: 10) {
        ForEach(vm.activeVisits) { visit in
          Card {
            HStack(spacing: 12) {
              AvatarView(.pet(species: visit.pet.species, gender: visit.pet.gender,
                              name: visit.pet.name, imageData: visit.pet.photoData), size: .md)
              VStack(alignment: .leading) {
                Text(visit.pet.name).font(.headline)
                Text(visit.pet.owner?.fullName ?? "").font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              Chip.info("In Progress")
              NavigationLink(destination: CheckoutView(pet: visit.pet)) {
                Image(systemName: "ellipsis.circle").font(.title3)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Session options")
            }
          }
        }
      }
    }
  }

  private func recentClientsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Recent Clients").font(.headline)
        Spacer()
        NavigationLink("View All", destination: ClientsView())
          .font(.footnote)
      }
      VStack(spacing: 10) {
        ForEach(vm.recentClients.prefix(5)) { client in
          NavigationLink { ClientDetailView(client: client) } label: {
            ClientRow(client: client)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func revenueSection(_ vm: DashboardViewModel) -> some View {
    #if canImport(Charts)
    VStack(alignment: .leading, spacing: 8) {
      Text("Revenue (7 Days)").font(.headline)
      Card {
        if vm.revenueSeries.isEmpty {
          ContentUnavailableView("No Revenue Yet", systemImage: "chart.bar.xaxis", description: Text("Complete a checkout to see revenue."))
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

  private func gallerySection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Pet Gallery").font(.headline)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(vm.gallery) { item in
          Card {
            if let uiImage = item.uiImage {
              Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(height: 120).clipped().cornerRadius(8)
            } else {
              AddPhotoPlaceholder(size: .md)
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
