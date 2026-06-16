//
//  ServiceManagementView.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData

struct ServiceManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ServiceManagementViewModel
    @State private var showingAddService = false

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: ServiceManagementViewModel(modelContext: modelContext))
    }

    var body: some View {
        List {
            ForEach(viewModel.services) { service in
                NavigationLink(destination: EditServiceView(service: service, modelContext: modelContext, wrapsInNavigationStack: false)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(service.name).font(.headline)
                            Text(service.effectiveBasePrice.moneyString)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !service.isEnabled {
                            Text(NSLocalizedString("service.disabled", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .onDelete(perform: deleteService)
        }
        .navigationTitle(NSLocalizedString("service.management_title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddService = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddService) {
            EditServiceView(modelContext: modelContext)
        }
        .onAppear {
            viewModel.fetchServices()
        }
        .alert(item: $viewModel.appError) { error in
            Alert(
                title: Text(NSLocalizedString("common.error", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
    }
    
    private func deleteService(at offsets: IndexSet) {
        for index in offsets {
            let service = viewModel.services[index]
            viewModel.deleteService(service)
        }
    }
}

// Placeholder for EditServiceView
struct EditServiceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: EditServiceViewModel
    private let wrapsInNavigationStack: Bool

    init(service: Service? = nil, modelContext: ModelContext, wrapsInNavigationStack: Bool = true) {
        _viewModel = State(initialValue: EditServiceViewModel(modelContext: modelContext, service: service))
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack {
                editContent
            }
        } else {
            editContent
        }
    }

    private var editContent: some View {
        Form {
            Section(NSLocalizedString("service.details", comment: "")) {
                TextField(NSLocalizedString("service.name", comment: ""), text: $viewModel.name)
                Picker(NSLocalizedString("service.category", comment: ""), selection: $viewModel.category) {
                    ForEach(Service.Category.allCases) { category in
                        Text(category.localizedName).tag(category)
                    }
                }
                HStack {
                    Text(NSLocalizedString("service.icon", comment: ""))
                    Spacer()
                    Image(systemName: viewModel.systemIcon)
                }
            }

            Section(NSLocalizedString("service.pricing_duration", comment: "")) {
                TextField(NSLocalizedString("service.price", comment: ""), value: $viewModel.price, format: .currency(code: "USD"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Stepper(
                    String(format: NSLocalizedString("service.duration_minutes_fmt", comment: ""), viewModel.duration),
                    value: $viewModel.duration,
                    in: 5...480,
                    step: 5
                )
            }

            Section(NSLocalizedString("service.status", comment: "")) {
                Toggle(NSLocalizedString("service.enabled_in_app", comment: ""), isOn: $viewModel.isEnabled)
                Toggle(NSLocalizedString("service.is_package", comment: ""), isOn: $viewModel.isPackage)
            }
        }
        .navigationTitle(viewModel.service == nil ? NSLocalizedString("service.add_service", comment: "") : NSLocalizedString("service.edit_service", comment: ""))
        .toolbar {
            if wrapsInNavigationStack {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("common.save", comment: "")) { saveService() }
            }
        }
        .alert(item: $viewModel.appError) { error in
            Alert(
                title: Text(NSLocalizedString("common.error", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
    }

    private func saveService() {
        Task {
            do {
                try await viewModel.save()
                dismiss()
            } catch let error as ValidationError {
                viewModel.appError = .validation(error)
            } catch {
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving service")
                viewModel.appError = .database(error.localizedDescription)
            }
        }
    }
}
