//
//  OnboardingView.swift
//  Pawtrackr
//
//  First-run onboarding flow to capture business branding.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
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
                        
                        Button("Choose Logo") {
                            showingImagePicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical)
                } header: {
                    Text("Business Branding")
                } footer: {
                    Text("Your logo and business name will appear on receipts and reports.")
                }
                
                Section("Basic Info") {
                    TextField("Business Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address)
                }
            }
            .navigationTitle("Setup Your Business")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        saveAndFinish()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(data: $logoData)
            }
        }
    }
    
    private func saveAndFinish() {
        let config = BusinessConfig(
            name: name,
            email: email,
            phone: phone,
            address: address,
            logoData: logoData
        )
        config.isSetupComplete = true
        modelContext.insert(config)
        try? modelContext.save()
        onComplete()
    }
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
