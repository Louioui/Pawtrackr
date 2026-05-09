//
//  OnboardingView.swift
//  Pawtrackr
//
//  Redesigned multi-step onboarding journey.
//

import SwiftUI
import SwiftData

#if os(iOS)
typealias PlatformContentType = UITextContentType
#elseif os(macOS)
typealias PlatformContentType = NSTextContentType
#endif

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Namespace private var animation
    @State private var viewModel: OnboardingViewModel
    @State private var showConfetti = false
    
    private enum FocusField {
        case pin, confirmPin
    }
    @FocusState private var focusedField: FocusField?
    
    var onComplete: () -> Void
    
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
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
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
                // Footer / Navigation
                onboardingFooter
            }
        }
        .task {
            viewModel.bindIfNeeded(modelContext: modelContext, appSettings: appSettings)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.currentStep)
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

    private var onboardingHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(spacing: DS.Spacing.xs) {
                Text(viewModel.currentStep.title)
                    .font(DS.TypeScale.title)
                    .foregroundStyle(.primary)
                    .id(viewModel.currentStep)
                    .transition(.push(from: .top))

                Text(viewModel.currentStep.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
            }
            
            HStack(spacing: 8) {
                ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(step.rawValue <= viewModel.currentStep.rawValue ? DS.ColorToken.primary : DS.ColorToken.border)
                            .frame(height: 6)
                        
                        if step == viewModel.currentStep {
                            Circle()
                                .fill(DS.ColorToken.primary)
                                .frame(width: 4, height: 4)
                                .matchedGeometryEffect(id: "activeStepDot", in: animation)
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.goToStep(step)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xxl)
        }
        .padding(.vertical, DS.Spacing.xl)
        .background(DS.ColorToken.background)
    }

    private var permissionsStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                    .symbolEffect(.bounce, value: viewModel.currentStep)
                
                Text("Choose Your Defaults")
                    .font(.title2.bold())
                
                Text("These preferences can be changed later in Settings, but getting them right now makes the first session smoother.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                permissionToggle(
                    title: "Lock When App Closes",
                    subtitle: "Require your PIN again whenever Pawtrackr leaves the foreground.",
                    icon: "lock.fill",
                    isOn: $viewModel.lockOnBackgroundEnabled
                )

                permissionToggle(
                    title: "Lock After Inactivity",
                    subtitle: "Automatically relock the app after a few idle minutes.",
                    icon: "timer",
                    isOn: $viewModel.autoLockAfterInactivityEnabled
                )
                
                permissionToggle(
                    title: viewModel.biometricTitle,
                    subtitle: viewModel.biometricSubtitle,
                    icon: viewModel.isBiometricsAvailable ? "faceid" : "touchid",
                    isOn: $viewModel.biometricsEnabled,
                    isDisabled: !viewModel.isBiometricsAvailable
                )
            }
            .padding(.horizontal, DS.Spacing.xxl)
        }
        .padding(.top, DS.Spacing.xl)
    }

    private func permissionToggle(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(DS.ColorToken.primary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(DS.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .hairlineBorder(DS.ColorToken.border, cornerRadius: 12)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
    }

    private var businessCardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if let logoData = viewModel.logoData, let uiImage = PlatformImage(data: logoData) {
                    Image(platformImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .matchedGeometryEffect(id: "businessLogo", in: animation)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DS.ColorToken.primary.opacity(0.1))
                            .frame(width: 60, height: 60)
                        Image(systemName: "pawprint.fill")
                            .foregroundStyle(DS.ColorToken.primary)
                    }
                    .matchedGeometryEffect(id: "businessLogo", in: animation)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.name.isEmpty ? "Your Business Name" : viewModel.name)
                        .font(.headline)
                        .foregroundStyle(viewModel.name.isEmpty ? .secondary : .primary)
                    
                    if !viewModel.email.isEmpty {
                        Text(viewModel.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !viewModel.phone.isEmpty {
                        Text(viewModel.phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if !viewModel.address.isEmpty {
                Divider()
                Text(viewModel.address)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.ColorToken.surface)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .padding(.bottom, DS.Spacing.lg)
    }
    
    private var welcomeStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            ZStack {
                Circle()
                    .fill(DS.ColorToken.primary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                    .matchedGeometryEffect(id: "businessLogo", in: animation)
            }
            .padding(.top, 40)
            
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
            
            Spacer()
        }
    }
    
    private var businessProfileStep: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                businessCardPreview
                
                VStack(spacing: DS.Spacing.md) {
                    ImagePicker(imageData: $viewModel.logoData) {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text(viewModel.logoData == nil ? "Upload Business Logo" : "Change Logo")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Business Name").font(.headline)
                    TextField("e.g. Bark & Bathe Grooming", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .accessibilityIdentifier("onboarding.businessName")
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
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
                businessCardPreview
                
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
                .padding(.horizontal, DS.Spacing.xxl)
                
                Text("Contact details are optional. Add them now if you want them on receipts and exports.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
                
                VStack(spacing: DS.Spacing.lg) {
                    onboardingTextField(title: "Contact Email", text: $viewModel.email, icon: "envelope", contentType: .emailAddress)
                    onboardingTextField(title: "Phone Number", text: $viewModel.phone, icon: "phone", contentType: .telephoneNumber)
                    onboardingTextField(title: "Business Address", text: $viewModel.address, icon: "mappin.and.ellipse", axis: .vertical, contentType: .fullStreetAddress)
                }
                .padding(.horizontal, DS.Spacing.xxl)
            }
            .padding(.top, DS.Spacing.xl)
        }
    }

    private func onboardingTextField(title: String, text: Binding<String>, icon: String, axis: Axis = .horizontal, contentType: PlatformContentType? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            if axis == .vertical {
                TextField(title, text: text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                    .textContentType(contentType)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(contentType)
                    #if os(iOS)
                    .keyboardType(keyboardType(for: contentType))
                    #endif
            }
        }
    }
    
    #if os(iOS)
    private func keyboardType(for contentType: PlatformContentType?) -> UIKeyboardType {
        switch contentType {
        case .emailAddress: return .emailAddress
        case .telephoneNumber: return .phonePad
        default: return .default
        }
    }
    #endif

    
    private var onboardingFooter: some View {
        VStack(spacing: DS.Spacing.sm) {
            if let validationMessage = viewModel.currentValidationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(DS.ColorToken.danger)
            }

            HStack {
                if viewModel.currentStep != .welcome {
                    Button("Back") {
                        viewModel.previousStep()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(viewModel.isSaving)
                }
                
                Spacer()
                
                if viewModel.currentStep != .warmStart {
                    Button {
                        viewModel.nextStep()
                    } label: {
                        HStack {
                            Text(viewModel.primaryActionTitle)
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                        .background(viewModel.canGoNext ? DS.ColorToken.primary : DS.ColorToken.primary.opacity(0.5))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .shadow(color: viewModel.canGoNext ? DS.ColorToken.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                    }
                    .disabled(!viewModel.canGoNext || viewModel.isSaving)
                    .buttonStyle(.plain)
                    .scaleEffect(viewModel.canGoNext ? 1.0 : 0.98)
                    .animation(.spring(), value: viewModel.canGoNext)
                    .accessibilityIdentifier("onboarding.continue")
                }
            }
        }
        .padding(DS.Spacing.xxl)
        .background(DS.ColorToken.background)
    }
    
    // MARK: - Steps
    
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
            
            VStack(spacing: DS.Spacing.xl) {
                pinEntryView(title: "Enter PIN", text: $viewModel.pin, field: .pin)
                pinEntryView(title: "Confirm PIN", text: $viewModel.confirmPin, field: .confirmPin)
                
                if let validationMessage = viewModel.securityValidationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(DS.ColorToken.danger)
                }
            }
        }
        .padding(.top, DS.Spacing.xl)
        .onAppear {
            focusedField = .pin
        }
    }

    private func pinEntryView(title: String, text: Binding<String>, field: FocusField) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            ZStack {
                // Hidden TextField that captures input
                TextField("", text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textContentType(field == .pin ? .oneTimeCode : .oneTimeCode) // using .oneTimeCode as generic placeholder where safe
                    .focused($focusedField, equals: field)
                    .opacity(0.01)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            text.wrappedValue = filtered
                            return
                        }
                        // Auto-advance focus if filling first PIN
                        if field == .pin && text.wrappedValue.count == 4 {
                            focusedField = .confirmPin
                        }
                    }

                // Visible PIN boxes
                HStack(spacing: 12) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.ColorToken.surface)
                            .frame(width: 50, height: 60)
                            .overlay(
                                Text(index < text.wrappedValue.count ? "•" : "")
                                    .font(.title.bold())
                            )
                            .hairlineBorder(
                                (focusedField == field && index == text.wrappedValue.count) ? DS.ColorToken.primary : DS.ColorToken.border,
                                cornerRadius: 8
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = field
            }
        }
    }
    
    private var warmStartStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                    .symbolEffect(.bounce, value: viewModel.currentStep)
                
                Text("How would you like to start?")
                    .font(.title2.bold())
                
                Text("Choose whether you want to start fresh or explore with some demo data.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Workspace Summary")
                    .font(.headline)
                Label(viewModel.name.trimmed.isEmpty ? "Business name will be added in setup" : viewModel.name.trimmed, systemImage: "building.2")
                Label("Currency: \(viewModel.currencySymbol)", systemImage: "dollarsign.circle")
                Label("PIN protection enabled", systemImage: "lock.shield")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(DS.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .hairlineBorder(DS.ColorToken.border, cornerRadius: 14)
            .padding(.horizontal, DS.Spacing.xxl)
            
            VStack(spacing: DS.Spacing.md) {
                selectionCard(
                    title: "Start Fresh",
                    subtitle: "Start with your own services, clients, and first visit workflow.",
                    icon: "plus.circle.fill",
                    action: { completeWithCelebration(seed: false) }
                )
                
                selectionCard(
                    title: "See Demo Data",
                    subtitle: "Load polished sample clients, pets, visits, and pricing so you can explore every major screen.",
                    icon: "wand.and.stars",
                    isPromoted: true,
                    action: { completeWithCelebration(seed: true) }
                )
            }
            .padding(.horizontal, DS.Spacing.xxl)
            
            if viewModel.isSaving {
                ProgressView("Setting up your workspace...")
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
            }
        }
    }

    private func selectionCard(title: String, subtitle: String, icon: String, isPromoted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isPromoted ? DS.ColorToken.primary : .secondary)
            }
            .padding()
            .background(DS.ColorToken.surface)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .hairlineBorder(isPromoted ? DS.ColorToken.primary.opacity(0.5) : DS.ColorToken.border, cornerRadius: 12)
            .shadow(color: isPromoted ? DS.ColorToken.primary.opacity(0.1) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier(title == "Start Fresh" ? "onboarding.startFresh" : "onboarding.demoData")
    }

    
    private func completeWithCelebration(seed: Bool) {
        Task {
            withAnimation(.spring()) {
                showConfetti = true
            }
            
            // Give a moment for the confetti to pop before dismissing
            try? await Task.sleep(for: .seconds(1.5))
            
            await viewModel.finish(seedSampleData: seed, onComplete: onComplete)
            if viewModel.saveError != nil {
                withAnimation(.easeOut(duration: 0.2)) {
                    showConfetti = false
                }
            }
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
