//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                                Section("Security") {
                    Toggle(isOn: $appSettings.isBiometricLockEnabled) {
                        Text("Enable Biometric Lock")
                    }
                }

                Section("Data Management") {
                    Picker("settings.data_management.prune_after", selection: $viewModel.pruningThreshold) {
                        ForEach(SettingsViewModel.PruningThreshold.allCases) { threshold in
                            Text(threshold.rawValue).tag(threshold)
                        }
                    }
                    
                    Button("settings.data_management.prune_now", role: .destructive) {
                        showingConfirmation = true
                    }
                    .disabled(viewModel.pruningThreshold == .never)
                }
            }
            .navigationTitle("settings.title")
            .alert("settings.data_management.confirm.title", isPresented: $showingConfirmation) {
                Button("common.cancel", role: .cancel) { }
                Button("settings.data_management.confirm.delete", role: .destructive) {
                    pruneData()
                }
            } message: {
                Text("settings.data_management.confirm.message")
            }
            .alert("common.error", isPresented: $showError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func pruneData() {
        guard let date = viewModel.pruningThreshold.date else {
            return
        }
        
        let dataPruner = DataPruner(modelContext: modelContext)
        do {
            try dataPruner.pruneVisits(olderThan: date)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}