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
                NavigationLink(destination: EditServiceView(service: service, modelContext: modelContext)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(service.name).font(.headline)
                            if let price = service.basePrice {
                                Text(price.moneyString).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !service.isEnabled {
                            Text("Disabled")
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
        .navigationTitle("Service Management")
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
    
    init(service: Service? = nil, modelContext: ModelContext) {
        _viewModel = State(initialValue: EditServiceViewModel(modelContext: modelContext, service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Service Name", text: $viewModel.name)
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(Service.Category.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    HStack {
                        Text("Icon")
                        Spacer()
                        Image(systemName: viewModel.systemIcon)
                    }
                }
                
                Section("Pricing & Duration") {
                    TextField("Price", value: $viewModel.price, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    
                    Stepper(
                        "\(viewModel.duration) minutes",
                        value: $viewModel.duration,
                        in: 5...480,
                        step: 5
                    )
                }

                Section("Status") {
                    Toggle("Enabled in app", isOn: $viewModel.isEnabled)
                    Toggle("Is a Package deal", isOn: $viewModel.isPackage)
                }
            }
            .navigationTitle(viewModel.service == nil ? "Add Service" : "Edit Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveService() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func saveService() {
        do {
            try viewModel.save()
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
