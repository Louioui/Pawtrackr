//
//  OnboardingView.swift
//  Pawtrackr
//
//  Redesigned multi-step onboarding journey.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @State private var viewModel: OnboardingViewModel
    @State private var showConfetti = false
    
    var onComplete: () -> Void
    
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        // Initializing with nil, will set up in .task or via environment in a real app,
        // but since we are in a View, we'll initialize it here and update it.
        self._viewModel = State(initialValue: OnboardingViewModel(modelContext: nil, appSettings: nil))
    }
    
    var body: some View {
        @Bindable var viewModel = viewModel
        ZStack {
            DS.ColorToken.background.ignoresSafeArea()
            
            if showConfetti {
                confettiView
                    .zIndex(10)
            }

            VStack(spacing: 0) {
                // Header / Progress
                onboardingHeader
                
                // Content
                ZStack {
                    switch viewModel.currentStep {
                    case .welcome:
                        welcomeStep
                    case .businessProfile:
                        businessProfileStep
                    case .regional:
                        regionalStep
                    case .security:
                        securityStep
                    case .permissions:
                        permissionsStep
                    case .warmStart:
                        warmStartStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                
                // Footer / Navigation
                onboardingFooter
            }
        }
        .task {
            // Correctly hook up the dependencies
            viewModel = OnboardingViewModel(modelContext: modelContext, appSettings: appSettings)
        }
        .alert("Setup Error", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("OK") { viewModel.saveError = nil }
        } message: {
            if let error = viewModel.saveError {
                Text(error)
            }
        }
    }
    
    // MARK: - Subviews

    private var confettiView: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<50, id: \.self) { i in
                    ConfettiPiece()
                        .offset(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private var onboardingHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            Text(viewModel.currentStep.title)
                .font(DS.TypeScale.title)
                .foregroundStyle(.primary)
            
            HStack(spacing: 4) {
                ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? DS.ColorToken.primary : DS.ColorToken.border)
                        .frame(height: 4)
                        .animation(.spring(), value: viewModel.currentStep)
                }
            }
            .padding(.horizontal, DS.Spacing.xxl)
        }
        .padding(.vertical, DS.Spacing.xl)
    }
    
    private var onboardingFooter: some View {
        HStack {
            if viewModel.currentStep != .welcome {
                Button("Back") {
                    viewModel.previousStep()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if viewModel.currentStep != .warmStart {
                Button {
                    viewModel.nextStep()
                } label: {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                    .background(viewModel.canGoNext ? DS.ColorToken.primary : DS.ColorToken.primary.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .disabled(!viewModel.canGoNext)
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.xxl)
        .background(DS.ColorToken.background)
    }
    
    // MARK: - Steps
    
    private var welcomeStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(DS.ColorToken.primary)
            
            VStack(spacing: DS.Spacing.sm) {
                Text("Welcome to Pawtrackr")
                    .font(.largeTitle.bold())
                Text("The modern workspace for pet groomers.\nLet's get your business set up in minutes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                featureRow(icon: "cloud.fill", title: "iCloud Sync", subtitle: "Your data stays safe and synced across all your devices.")
                featureRow(icon: "lock.fill", title: "Privacy First", subtitle: "End-to-end security with local-first storage and biometric locking.")
                featureRow(icon: "chart.bar.fill", title: "Business Insights", subtitle: "Track revenue, service trends, and client loyalty effortlessly.")
            }
            .padding(.top, DS.Spacing.xl)
        }
    }
    
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(DS.ColorToken.primary)
                .frame(width: 40)
            
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }
    
    private var businessProfileStep: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xxl) {
                VStack(spacing: DS.Spacing.md) {
                    if let logoData = viewModel.logoData, let image = PlatformImage(data: logoData) {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                            .hairlineBorder(DS.ColorToken.border, cornerRadius: DS.Radius.lg)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .fill(DS.ColorToken.surface)
                                .frame(height: 120)
                                .frame(width: 120)
                                .hairlineBorder(DS.ColorToken.border, cornerRadius: DS.Radius.lg)
                            
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(DS.ColorToken.primary)
                        }
                    }
                    
                    ImagePicker(imageData: $viewModel.logoData) {
                        Text(viewModel.logoData == nil ? "Upload Business Logo" : "Change Logo")
                    }
                    .buttonStyle(.bordered)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Business Name").font(.headline)
                    TextField("e.g. Bark & Bathe Grooming", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }
                .padding(.horizontal, DS.Spacing.xxl)
                
                Text("This information will be used to brand your receipts and reports.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
            }
            .padding(.top, DS.Spacing.xl)
        }
    }
    
    private var regionalStep: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Currency Symbol").font(.headline)
                    Picker("Currency", selection: $viewModel.currencySymbol) {
                        Text("$ (USD/CAD)").tag("$")
                        Text("£ (GBP)").tag("£")
                        Text("€ (EUR)").tag("€")
                        Text("¥ (JPY)").tag("¥")
                        Text("A$ (AUD)").tag("A$")
                        Text("₪ (ILS)").tag("₪")
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Contact Email").font(.headline)
                    TextField("contact@business.com", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Phone Number").font(.headline)
                    TextField("123-456-7890", text: $viewModel.phone)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Business Address").font(.headline)
                    TextField("123 Groomer Way, City", text: $viewModel.address, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
            }
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.top, DS.Spacing.xl)
        }
    }
    
    private var securityStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                
                Text("Set Your App PIN")
                    .font(.title2.bold())
                
                Text("This 4-digit code will protect your client data.")
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Enter PIN").font(.caption).foregroundStyle(.secondary)
                    SecureField("", text: $viewModel.pin)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                        .font(.title.monospacedDigit())
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Confirm PIN").font(.caption).foregroundStyle(.secondary)
                    SecureField("", text: $viewModel.confirmPin)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.center)
                        .font(.title.monospacedDigit())
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                
                if !viewModel.pin.isEmpty && viewModel.pin.count != 4 {
                    Text("PIN must be 4 digits")
                        .font(.caption)
                        .foregroundStyle(DS.ColorToken.danger)
                } else if !viewModel.confirmPin.isEmpty && viewModel.pin != viewModel.confirmPin {
                    Text("PINs do not match")
                        .font(.caption)
                        .foregroundStyle(DS.ColorToken.danger)
                }
            }
        }
        .padding(.top, DS.Spacing.xl)
    }
    
    private var permissionsStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                
                Text("App Preferences")
                    .font(.title2.bold())
                
                Text("Customize how Pawtrackr works for you.")
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                Toggle(isOn: $viewModel.notificationsEnabled) {
                    VStack(alignment: .leading) {
                        Text("Notifications").font(.headline)
                        Text("Get reminders for upcoming appointments.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.notificationsEnabled) { _, newValue in
                    if newValue { viewModel.requestNotifications() }
                }
                .padding()
                .background(DS.ColorToken.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                
                Toggle(isOn: $viewModel.biometricsEnabled) {
                    VStack(alignment: .leading) {
                        Text("Biometric Lock").font(.headline)
                        Text("Use FaceID/TouchID to quickly unlock the app.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.biometricsEnabled) { _, newValue in
                    if newValue { viewModel.requestBiometrics() }
                }
                .padding()
                .background(DS.ColorToken.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .padding(.horizontal, DS.Spacing.xxl)
        }
        .padding(.top, DS.Spacing.xl)
    }
    
    private var warmStartStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                
                Text("How would you like to start?")
                    .font(.title2.bold())
                
                Text("Choose whether you want to start fresh or explore with some demo data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            VStack(spacing: DS.Spacing.md) {
                Button {
                    completeWithCelebration(seed: false)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start Fresh").font(.headline)
                            Text("Empty database, ready for your first client.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .padding()
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .hairlineBorder(DS.ColorToken.border)
                }
                .buttonStyle(.plain)
                
                Button {
                    completeWithCelebration(seed: true)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("See Demo Data").font(.headline)
                            Text("Seeds example pets and visits to explore features.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "wand.and.stars").font(.title2)
                    }
                    .padding()
                    .background(DS.ColorToken.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .hairlineBorder(DS.ColorToken.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Spacing.xxl)
            
            if viewModel.isSaving {
                ProgressView("Setting up your workspace...")
            }
        }
    }
    
    private func completeWithCelebration(seed: Bool) {
        Task {
            withAnimation(.spring()) {
                showConfetti = true
            }
            HapticManager.notify(.success)
            
            // Give a moment for the confetti to pop before dismissing
            try? await Task.sleep(for: .seconds(1.5))
            
            await viewModel.finish(seedSampleData: seed, onComplete: onComplete)
        }
    }
}

private struct ConfettiPiece: View {
    @State private var x: CGFloat = 0
    @State private var y: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var color: Color = [.blue, .purple, .pink, .orange, .yellow, .green].randomElement()!
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .opacity(opacity)
            .onAppear {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 100...400)
                
                withAnimation(.easeOut(duration: 1.5)) {
                    x = cos(angle) * distance
                    y = sin(angle) * distance
                    rotation = Double.random(in: 0...720)
                    opacity = 0
                }
            }
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
