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
    @Environment(NavigationRouter.self) private var router
    @State private var vm: DashboardViewModel?
    @State private var showNewClient = false
    @State private var showContent = false
    @Namespace var namespace

  var body: some View {
      dashboardContent
        .navigationTitle(NSLocalizedString("dashboard.title", comment: ""))
        .sheet(isPresented: $showNewClient) {
          NewClientSheet(modelContext: modelContext)
        }
        .alert(item: appErrorBinding) { error in
          Alert(
            title: Text(NSLocalizedString("common.error", comment: "")),
            message: Text(error.localizedDescription),
            dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
          )
        }
        .toolbar { insightsToolbarItem }
  }

  @ViewBuilder
  private var dashboardContent: some View {
    if let vm {
      content(vm)
    } else {
      ProgressView()
        .task {
          let model = DashboardViewModel(modelContext: modelContext)
          await model.refresh()
          vm = model
        }
    }
  }

  private var appErrorBinding: Binding<AppError?> {
    Binding(get: { vm?.appError }, set: { vm?.appError = $0 })
  }

  @ToolbarContentBuilder
  private var insightsToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
      } label: {
        Image(systemName: "chart.bar")
      }
      .accessibilityLabel("Open Insights")
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
            if !vm.upcomingAppointments.isEmpty { upcomingSection(vm).transition(.move(edge: .trailing).combined(with: .opacity)) }
            if !vm.overduePets.isEmpty { overduePetsSection(vm).transition(.move(edge: .leading).combined(with: .opacity)) }
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
            kpiCard(title: NSLocalizedString("dashboard.appointments", comment: ""), value: vm.kpi.appointmentsTodayText, symbol: "calendar")
          }
          NavigationLink { RecentHistoryView(initialScope: .today) } label: {
            kpiCard(title: NSLocalizedString("dashboard.in_progress", comment: ""),  value: "\(vm.kpi.inProgressCount)",   symbol: "hourglass")
          }
        }
        GridRow {
          NavigationLink { InsightsView() } label: {
            kpiCard(title: NSLocalizedString("dashboard.revenue", comment: ""),     value: vm.kpi.revenueTodayString,      symbol: "dollarsign.circle")
          }
          NavigationLink { RecentHistoryView(initialScope: .today) } label: {
            kpiCard(title: NSLocalizedString("dashboard.completed", comment: ""),   value: "\(vm.kpi.completedToday)",      symbol: "checkmark.circle")
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
          NavigationLink { ClientsView() } label: { actionCardLabel(title: NSLocalizedString("dashboard.check_in", comment: ""), symbol: "play.circle") }
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

  private func upcomingSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.upcoming", comment: "Upcoming Appointments")).font(.headline)
      Card {
        VStack(spacing: 0) {
          ForEach(vm.upcomingAppointments) { appt in
            upcomingRow(appt, vm: vm)
            if appt != vm.upcomingAppointments.last { Divider().padding(.leading, 56) }
          }
        }
      }
    }
  }

  private func upcomingRow(_ appt: Appointment, vm: DashboardViewModel) -> some View {
    HStack(spacing: 12) {
      AvatarView(.pet(species: appt.pet.species, gender: appt.pet.gender, name: appt.pet.name, imageData: appt.pet.photoData), size: .sm)
      VStack(alignment: .leading, spacing: 2) {
        Text(appt.pet.name).font(.subheadline.weight(.semibold))
        Text(appt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Check In") {
        Task { await vm.checkInFromAppointment(appt) }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
  }

  private func overduePetsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.needs_attention", comment: "")).font(.headline)
      LazyVStack(spacing: 12) {
        ForEach(vm.overduePets) { pet in
            if let owner = pet.owner {
                VStack(spacing: 0) {
                    NavigationLink { ClientDetailView(client: owner) } label: {
                        PetCard(pet: pet, activeVisit: nil, onViewDetails: {}, onCheckIn: {}, onCheckOut: {})
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 16) {
                        if let sms = owner.smsURL {
                            Link(destination: sms) {
                                Label(NSLocalizedString("dashboard.message", comment: ""), systemImage: "message.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        if let tel = owner.telURL {
                            Link(destination: tel) {
                                Label(NSLocalizedString("dashboard.call", comment: ""), systemImage: "phone.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .offset(y: -8) // Pull it up to overlap slightly with the card's bottom
                }
            }
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
          NavigationLink { ClientDetailView(client: client) } label: { ClientRow(client: client) }
            .buttonStyle(.plain)
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

  private func gallerySection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.pet_gallery", comment: "")).font(.headline)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(vm.gallery) { item in
          Card {
            #if canImport(UIKit)
            if let uiImage = item.uiImage {
              Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(height: 120).clipped().cornerRadius(8)
            } else {
              LabelContent(title: NSLocalizedString("dashboard.no_photo", comment: ""), systemImage: "photo")
            }
            #elseif canImport(AppKit)
            if let nsImage = item.nsImage {
              Image(nsImage: nsImage).resizable().scaledToFill()
                .frame(height: 120).clipped().cornerRadius(8)
            } else {
              LabelContent(title: NSLocalizedString("dashboard.no_photo", comment: ""), systemImage: "photo")
            }
            #endif
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
