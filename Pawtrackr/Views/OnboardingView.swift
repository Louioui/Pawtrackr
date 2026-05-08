//
//  OnboardingView.swift
//  Pawtrackr
//
//  First-run onboarding flow to capture business branding.
//

import SwiftUI
import SwiftData
import OSLog

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [BusinessConfig]
    
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var logoData: Data?
    @State private var showingImagePicker = false
    
    var onComplete: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        if let logoData, let image = PlatformImage(data: logoData) {
                            Image(platformImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                                .frame(height: 100)
                                .frame(maxWidth: .infinity)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        ImagePicker(imageData: $logoData) {
                            Text("Choose Logo")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical)
                } header: {
                    Text("Business Branding")
                } footer: {
                    Text("Your logo and business name will appear on receipts and reports.")
                }
                
                Section {
                    TextField("Business Name", text: $name)
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Address", text: $address)
                } header: {
                    Text("Basic Info")
                }
            }
            .navigationTitle("Setup Your Business")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        saveAndFinish()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveAndFinish() {
        let config = configs.first ?? BusinessConfig()
        config.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        config.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        config.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        config.address = address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        config.logoData = logoData
        config.isSetupComplete = true
        if config.modelContext == nil {
            modelContext.insert(config)
        }
        do {
            try modelContext.save()
        } catch {
            // Onboarding-failure visibility: log so we can see in Console if
            // the user is stuck on this screen. The setup-complete flag is
            // already set on the config object, so a rerun will reuse it.
            Logger.onboarding.error("Onboarding save failed: \(String(describing: error))")
        }
        onComplete()
    }
}

private extension Logger {
    static let onboarding = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Onboarding")
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#endif
