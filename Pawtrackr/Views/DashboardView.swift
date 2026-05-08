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
    @Environment(DataStoreService.self) private var dataStore
    @Environment(GlobalEventBus.self) private var eventBus
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var vm: DashboardViewModel?
    @State private var showNewClient = false
    @State private var showContent = false
    @State private var selectedRevenueDate: Date?
    @Namespace var namespace

  var body: some View {
      dashboardContent
        .navigationTitle(NSLocalizedString("dashboard.title", comment: ""))
        .task {
            if vm == nil {
                vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
            }
        }
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
          // Assign immediately so @Observable tracking is live while refresh runs.
          let model = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
          vm = model
          await model.refresh()
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
          showNewClient = true
      } label: {
        Label("New Client", systemImage: "person.badge.plus")
      }
      .keyboardShortcut("n", modifiers: .command)
    }

    ToolbarItem(placement: .primaryAction) {
      CloudKitStatusView()
    }

    #if os(macOS)
    ToolbarItem(placement: .navigation) {
        Button {
            Task { await vm?.refresh() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
    }
    #endif

    ToolbarItem(placement: .status) {
        if let vm = vm, !vm.activeVisits.isEmpty {
            Text("\(vm.activeVisits.count) Active Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
  }

  @ViewBuilder
  private func content(_ vm: DashboardViewModel) -> some View {
    ScrollView {
      LazyVStack(spacing: 24) {
        if showContent {
            smartSummary(vm)
                .transition(.move(edge: .top).combined(with: .opacity))

            #if os(macOS)
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 24) {
                    kpiSection(vm)
                    activeSessionsSection(vm)
                    reengagementSection(vm)
                    revenueSection(vm)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 24) {
                    quickActionsSection
                    upcomingSection(vm)
                    overduePetsSection(vm)
                    recentClientsSection(vm)
                    gallerySection(vm)
                }
                .frame(maxWidth: 350)
            }
            #else
            VStack(spacing: 24) {
                kpiSection(vm)
                quickActionsSection
                if !vm.activeVisits.isEmpty { activeSessionsSection(vm) }
                reengagementSection(vm)
                if !vm.upcomingAppointments.isEmpty { upcomingSection(vm) }
                if !vm.overduePets.isEmpty { overduePetsSection(vm) }
                if !vm.recentClients.isEmpty { recentClientsSection(vm) }
                revenueSection(vm)
                if !vm.gallery.isEmpty { gallerySection(vm) }
            }
            #endif
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 24)
    }
    .accessibilityIdentifier("dashboard.scroll")
    .onAppear {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showContent = true
        }
    }
    .refreshable {
      // Pull-to-refresh runs both: local data refresh + iCloud sync trigger.
      // The two run concurrently because they're independent.
      async let local: Void = vm.refresh()
      async let cloud: Void = CloudKitMonitor.shared.forceSync()
      _ = await (local, cloud)
    }
  }

  private func reengagementSection(_ vm: DashboardViewModel) -> some View {
      VStack(alignment: .leading, spacing: 12) {
          if !vm.overduePets.isEmpty {
              HStack {
                  Text("Re-engagement Suggestions")
                      .font(.headline)
                  Spacer()
                  Chip("\(vm.overduePets.count) Actionable", style: .tinted, size: .sm, tint: .orange)
              }

              ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 12) {
                      ForEach(vm.overduePets.prefix(3)) { pet in
                          reengagementCard(pet)
                      }
                  }
              }
          }
      }
  }

  private func reengagementCard(_ pet: Pet) -> some View {
      Card(elevation: .regular) {
          VStack(alignment: .leading, spacing: 10) {
              HStack {
                  AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .sm)
                  VStack(alignment: .leading) {
                      Text(pet.name).font(.subheadline.weight(.bold))
                      Text(pet.owner?.fullName ?? "").font(.caption).foregroundStyle(.secondary)
                  }
              }

              Text(pet.isOverdue ? "Overdue for visit" : "Due soon")
                  .font(.caption2.weight(.semibold))
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.orange.opacity(0.1))
                  .foregroundColor(.orange)
                  .clipShape(Capsule())

              HStack {
                  if let sms = pet.owner?.smsURL {
                      Link(destination: sms) {
                          Label("Message", systemImage: "message.fill")
                              .font(.caption.weight(.bold))
                      }
                      .buttonStyle(.borderedProminent)
                      .controlSize(.small)
	                  } else if let owner = pet.owner {
	                      Button {
	                          openClient(owner)
	                      } label: {
	                          Label("View Owner", systemImage: "person.fill")
	                              .font(.caption.weight(.bold))
                      }
                      .buttonStyle(.bordered)
                      .controlSize(.small)
                  }

                  Spacer()
              }
          }
          .frame(width: 180)
      }
  }

  private func smartSummary(_ vm: DashboardViewModel) -> some View {
      VStack(alignment: .leading, spacing: 4) {
          Text(Calendar.current.component(.hour, from: .now) < 12 ? "Good Morning" : "Good Afternoon")
              .font(.title2.weight(.bold))

          let summary = generateSummaryText(vm)
          Text(summary)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 8)
  }

  private func generateSummaryText(_ vm: DashboardViewModel) -> String {
      var parts: [String] = []

      if vm.kpi.appointmentsToday > 0 {
          parts.append("\(vm.kpi.appointmentsToday) appointments scheduled for today")
      } else {
          parts.append("No appointments scheduled for today")
      }

      if vm.kpi.inProgressCount > 0 {
          parts.append("\(vm.kpi.inProgressCount) active sessions in progress")
      }

      if let trend = vm.kpi.revenueTrend {
          let direction = trend >= 0 ? "up" : "down"
          let pct = Formatters.percentString(abs(trend), showSign: false) ?? ""
          parts.append("revenue is \(direction) \(pct) from yesterday")
      }

      return parts.joined(separator: ", ") + "."
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
	          Button {
	            selectSurface(.insights, resetPath: true)
	          } label: {
	            kpiCard(title: NSLocalizedString("dashboard.revenue", comment: ""),     value: vm.kpi.revenueTodayString,      symbol: "dollarsign.circle", trend: vm.kpi.revenueTrend)
	          }
	          .buttonStyle(.plain)
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
	          actionCard(title: NSLocalizedString("dashboard.check_in", comment: ""), symbol: "play.circle") {
	            selectSurface(.clients, resetPath: true)
	          }
	          NavigationLink { RecentHistoryView() } label: { actionCardLabel(title: NSLocalizedString("dashboard.check_out", comment: ""), symbol: "stop.circle") }
	          actionCard(title: NSLocalizedString("dashboard.reports", comment: ""), symbol: "chart.bar.fill") {
	            selectSurface(.insights, resetPath: true)
	          }
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
      if let pet = appt.pet {
        AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .sm)
        VStack(alignment: .leading, spacing: 2) {
          Text(pet.name).font(.subheadline.weight(.semibold))
          Text(appt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }
      } else {
        // Pet was deleted but the appointment record remains. Show a placeholder
        // rather than crashing or hiding the row entirely.
        Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(NSLocalizedString("common.unknown_pet", comment: "")).font(.subheadline.weight(.semibold))
          Text(appt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button("Check In") {
        Task { await vm.checkInFromAppointment(appt) }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(appt.pet == nil)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
  }

  private func overduePetsSection(_ vm: DashboardViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("dashboard.needs_attention", comment: "")).font(.headline)
      LazyVStack(spacing: 12) {
        ForEach(vm.overduePets, id: \.uuid) { pet in
            if let owner = pet.owner {
                Card {
                    VStack(spacing: 8) {
	                        PetCard(
	                            pet: pet,
	                            activeVisit: pet.activeVisit,
	                            onViewDetails: { openClient(owner) },
	                            onCheckIn: { Task { await vm.checkInPet(pet) } },
	                            onCheckOut: { router.navigateToCheckout(pet) }
	                        )

                        if owner.smsURL != nil || owner.telURL != nil {
                            HStack(spacing: 12) {
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
                        }
                    }
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
	        Button(NSLocalizedString("dashboard.view_all", comment: "")) {
	          selectSurface(.clients, resetPath: true)
	        }
	          .font(.footnote)
	      }
	      LazyVStack(spacing: 10) {
	        ForEach(vm.recentClients.prefix(5)) { client in
	          Button {
	            openClient(client)
	          } label: {
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
    let selectedPoint = selectedRevenuePoint(in: vm)
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(NSLocalizedString("dashboard.revenue_7d", comment: "")).font(.headline)
        Spacer()
        if let selected = selectedPoint {
            Text("\(selected.date.formatted(.dateTime.weekday(.abbreviated))): \(selected.amount.moneyString)")
                .font(.subheadline.bold())
                .foregroundStyle(DS.ColorToken.primary)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
      }
      Card {
        if vm.revenueSeries.isEmpty {
          ContentUnavailableView(NSLocalizedString("dashboard.no_revenue_yet", comment: ""), systemImage: "chart.bar.xaxis", description: Text(NSLocalizedString("dashboard.no_revenue_desc", comment: "")))
            .frame(height: 180)
        } else {
          Chart {
            ForEach(vm.revenueSeries) { point in
              BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Revenue", point.amountDouble)
              )
              .foregroundStyle(DS.ColorToken.primary.gradient)
              .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.4)
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date, unit: .day))
                    .foregroundStyle(.gray.opacity(0.3))
                    .offset(y: -10)
                    .zIndex(-1)
            }
          }
          .chartXSelection(value: $selectedRevenueDate)
          .frame(height: 180)
          .animation(.spring(), value: selectedRevenueDate)
        }
      }
    }
    #else
    EmptyView()
    #endif
  }

  private func selectedRevenuePoint(in vm: DashboardViewModel) -> DashboardViewModel.RevenuePoint? {
    guard let selectedRevenueDate else { return nil }
    let calendar = Calendar.current
    return vm.revenueSeries.first { calendar.isDate($0.date, inSameDayAs: selectedRevenueDate) }
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
                .frame(height: 120)
            }
            #elseif canImport(AppKit)
            if let nsImage = item.nsImage {
              Image(nsImage: nsImage).resizable().scaledToFill()
                .frame(height: 120).clipped().cornerRadius(8)
            } else {
              LabelContent(title: NSLocalizedString("dashboard.no_photo", comment: ""), systemImage: "photo")
                .frame(height: 120)
            }
            #endif
          }
        }
      }
    }
  }

  private func kpiCard(title: String, value: String, symbol: String, trend: Double? = nil) -> some View {
    Card {
      HStack(alignment: .top) {
        IconCircle(systemImage: symbol, size: .md)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.footnote).foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())

            if let trend = trend {
                HStack(spacing: 2) {
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(Formatters.percentString(abs(trend), showSign: false) ?? "")
                }
                .font(.caption2.bold())
                .foregroundStyle(trend >= 0 ? .green : .red)
            }
          }
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
        Text(title)
          .font(.body.weight(.medium))
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.8)
      }
      .frame(width: 130, height: 100)
	    }
	  }

	  private func selectSurface(_ item: NavigationItem, resetPath: Bool = false) {
	    NotificationCenter.default.post(name: .selectNavigationItem, object: nil, userInfo: [
	      NavigationSelectionKey.item.rawValue: item.rawValue,
	      NavigationSelectionKey.resetPath.rawValue: resetPath
	    ])
	  }

	  private func openClient(_ client: Client) {
	    NotificationCenter.default.post(name: .navigateToClient, object: nil, userInfo: [
	      "uuid": client.uuid
	    ])
	  }
	}
