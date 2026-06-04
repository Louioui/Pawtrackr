//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UserNotifications
import UIKit
#endif

enum SettingSection: String, CaseIterable, Identifiable {
    case business, preferences, security, dataExport, icloud, help, devices, about
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .business: return "settings.section.business"
        case .preferences: return "settings.section.preferences"
        case .security: return "settings.section.security"
        case .dataExport: return "settings.section.export"
        case .icloud: return "settings.section.icloud"
        case .help: return "settings.section.help"
        case .devices: return "settings.section.devices"
        case .about: return "settings.section.about"
        }
    }
    
    var icon: String {
        switch self {
        case .business: return "building.2.fill"
        case .preferences: return "slider.horizontal.3"
        case .security: return "lock.shield.fill"
        case .dataExport: return "square.and.arrow.up"
        case .icloud: return "icloud.fill"
        case .help: return "questionmark.circle.fill"
        case .devices: return "iphone.gen3.radiowaves.left.and.right"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @State private var selection: SettingSection? = .business
    
    // State needed for sub-views
    @State private var showChangePIN = false
    @State private var pinChangeError: String? = nil
    @State private var showResetFirstRunConfirm = false
    @State private var versionTapCount = 0
    @State private var showDiagnostics = false

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(SettingSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.icon)
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
            }
            .navigationTitle(Text("settings.title"))
            .listStyle(.sidebar)
        } detail: {
            if let selection {
                SettingsDetailView(section: selection, 
                                   showChangePIN: $showChangePIN, 
                                   showResetFirstRunConfirm: $showResetFirstRunConfirm,
                                   versionTapCount: $versionTapCount,
                                   showDiagnostics: $showDiagnostics)
            } else {
                ContentUnavailableView("Select a setting", systemImage: "gear")
            }
        }
        #else
        NavigationStack {
            List(SettingSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.icon)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingSection.self) { section in
                SettingsDetailView(section: section, 
                                   showChangePIN: $showChangePIN, 
                                   showResetFirstRunConfirm: $showResetFirstRunConfirm,
                                   versionTapCount: $versionTapCount,
                                   showDiagnostics: $showDiagnostics)
            }
        }
        #endif
    }
}

private struct SettingsDetailView: View {
    let section: SettingSection
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Binding var showChangePIN: Bool
    @Binding var showResetFirstRunConfirm: Bool
    @Binding var versionTapCount: Int
    @Binding var showDiagnostics: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(section.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                
                content
            }
            .padding(30)
        }
        .sheet(isPresented: $showChangePIN) {
            ChangePINSheet(isPresented: $showChangePIN)
                .environment(appSettings)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch section {
        case .business: BusinessSectionView(appSettings: appSettings)
        case .preferences: PreferencesSectionView(appSettings: appSettings)
        case .security: SecuritySectionView(appSettings: appSettings, showChangePIN: $showChangePIN)
        case .dataExport: DataExportSectionView(modelContext: modelContext)
        case .devices: DevicesHealthView()
        case .about: AboutSectionView(versionTapCount: $versionTapCount, showDiagnostics: $showDiagnostics)
        default:
            Text("Configuration for \(section.title)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DataExportSectionView: View {
    let modelContext: ModelContext
    @State private var isExportingClients = false
    @State private var isExportingVisits = false

    var body: some View {
        CardView {
            Button("Export Clients (CSV)") {
                runExport(kind: .clients)
            }
            .disabled(isExportingClients)
            
            Button("Export Visits (CSV)") {
                runExport(kind: .visits)
            }
            .disabled(isExportingVisits)
        }
    }
    
    enum ExportKind { case clients, visits }
    private func runExport(kind: ExportKind) {
        // Placeholder for ExportService integration
        print("Exporting \(kind)...")
    }
}

private struct BusinessSectionView: View {
    @Bindable var appSettings: AppSettings
    var body: some View {
        CardView {
            TextField("Business Name", text: $appSettings.businessName)
                .textFieldStyle(.roundedBorder)
            TextField("Currency Symbol", text: $appSettings.currencySymbol)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PreferencesSectionView: View {
    @Bindable var appSettings: AppSettings
    var body: some View {
        CardView {
            Picker(selection: $appSettings.preferredColorScheme) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            
            Toggle(isOn: $appSettings.hapticsEnabled) {
                Label("Haptic Feedback", systemImage: "hand.tap.fill")
            }
        }
    }
}

private struct SecuritySectionView: View {
    @Bindable var appSettings: AppSettings
    @Binding var showChangePIN: Bool
    
    var body: some View {
        CardView {
            Toggle("Enable App Lock", isOn: $appSettings.isLockEnabled)
            Toggle("Biometric Unlock", isOn: $appSettings.isBiometricLockEnabled)
            if appSettings.isLockEnabled {
                Button("Change PIN") { showChangePIN = true }
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct AboutSectionView: View {
    @Binding var versionTapCount: Int
    @Binding var showDiagnostics: Bool
    
    var body: some View {
        CardView {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0") // Placeholder for version
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                versionTapCount += 1
                if versionTapCount >= 7 {
                    showDiagnostics = true
                }
            }
        }
    }
}

private struct CardView<Content: View>: View {
    let content: Content
    @State private var isHovering = false
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        VStack(spacing: 16) { content }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 8 : 5, x: 0, y: 2)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
    }
}
