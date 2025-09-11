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

        // 1) KPI grid
        VStack(alignment: .leading, spacing: 8) {
          Text("Today").font(.headline)
          Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
              kpiCard(title: "Appointments", value: vm.kpi.appointmentsTodayText, symbol: "calendar")
              kpiCard(title: "In Progress",  value: "\(vm.kpi.inProgressCount)",   symbol: "hourglass")
            }
            GridRow {
              kpiCard(title: "Revenue",     value: vm.kpi.revenueTodayString,      symbol: "dollarsign.circle")
              kpiCard(title: "Completed",   value: "\(vm.kpi.completedToday)",      symbol: "checkmark.circle")
            }
          }
        }

        // 2) Quick actions
        VStack(alignment: .leading, spacing: 8) {
          Text("Quick Actions").font(.headline)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              actionCard(title: "New Client", symbol: "person.crop.circle.badge.plus") { showNewClient = true }
              NavigationLink {
                ClientsView() // jump to clients to pick a pet to check in
              } label: {
                actionCardLabel(title: "Check In", symbol: "play.circle")
              }
              NavigationLink {
                RecentHistoryView() // or a “Ready to Checkout” filter if you add one
              } label: {
                actionCardLabel(title: "Check Out", symbol: "stop.circle")
              }
              NavigationLink {
                InsightsView()
              } label: {
                actionCardLabel(title: "Reports", symbol: "doc.chart")
              }
            }
          }
        }

        // 3) Active sessions
        if !vm.activeVisits.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Active Sessions").font(.headline)
            VStack(spacing: 10) {
              ForEach(vm.activeVisits) { visit in
                NavigationLink {
                  VisitDetailView(visit: visit)
                } label: {
                  Card {
                    HStack(spacing: 12) {
                      AvatarView(.pet(species: visit.pet.species, gender: visit.pet.gender,
                                      name: visit.pet.name, imageData: visit.pet.photoData), size: .md)
                      VStack(alignment: .leading) {
                        Text(visit.pet.name).font(.headline)
                        Text(visit.pet.owner?.fullName ?? "").font(.footnote).foregroundStyle(.secondary)
                      }
                      Spacer()
                      Chip("In Progress", style: .info)
                    }
                  }
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        // 4) Recent clients
        if !vm.recentClients.isEmpty {
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
                  ClientRow(client: client) // or ClientCard(client:)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        // 5) Revenue analytics (7D)
        #if canImport(Charts)
        VStack(alignment: .leading, spacing: 8) {
          Text("Revenue (7 Days)").font(.headline)
          Card {
            Chart(vm.revenueSeries) { point in
              BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Revenue", point.amountDouble)
              )
            }
            .frame(height: 180)
          }
        }
        #endif

        // 6) Gallery
        if !vm.gallery.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Pet Gallery").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
              ForEach(vm.gallery) { item in
                Card {
                  if let uiImage = item.uiImage {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                      .frame(height: 120).clipped().cornerRadius(8)
                  } else {
                    AddPhotoPlaceholder(size: .md) // your dashed placeholder
                  }
                }
              }
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 24)
    }
    .refreshable { await vm.refresh() }
  }

  private func kpiCard(title: String, value: String, symbol: String) -> some View {
    Card {
      HStack(alignment: .top) {
        IconCircle(systemName: symbol, tone: .primary).frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.footnote).foregroundStyle(.secondary)
          Text(value).font(.title3.weight(.semibold)).monospacedDigit()
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
        IconCircle(systemName: symbol, tone: .primary).frame(width: 48, height: 48)
        Text(title).font(.body.weight(.medium))
      }
      .frame(width: 150, height: 110)
    }
  }
}
