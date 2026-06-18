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
    // Welcome-screen entrance/loop animation state. Looping effects are scoped to
    // the welcome step only (see footer/welcomeStep) and use SwiftUI repeatForever
    // — never Timer/Combine, which freezes @Observable-driven views.
    @State private var welcomeAppeared = false
    @State private var welcomeBreathing = false
    @State private var ctaPulse = false
    
    // Explicitly define PlatformImage based on platform to ensure availability
    #if canImport(UIKit)
    private typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    private typealias PlatformImage = NSImage
    #endif
    
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
                    case .welcome: welcomeStep
                    case .businessProfile: businessProfileStep
                    case .regional: regionalStep
                    case .security: securityStep
                    case .permissions: permissionsStep
                    case .warmStart: warmStartStep
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
        .alert(NSLocalizedString("onboarding.error.setup_title", value: "Setup Error", comment: ""), isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button(NSLocalizedString("common.ok", comment: "")) { viewModel.saveError = nil }
        } message: {
            if let error = viewModel.saveError {
                Text(error)
            }
        }
    }
    
    @ViewBuilder
    private func logoImageView(image: PlatformImage) -> some View {
        #if os(iOS)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #elseif os(macOS)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }

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

    private func featureRow(index: Int = 0, icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(DS.ColorToken.primary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Staggered slide-up reveal; each bullet trails the previous by 120ms.
        .opacity(welcomeAppeared ? 1 : 0)
        .offset(y: welcomeAppeared ? 0 : 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.78).delay(0.18 + Double(index) * 0.12), value: welcomeAppeared)
        .padding(.horizontal, DS.Spacing.xxl)
    }

    private var onboardingHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(spacing: DS.Spacing.xs) {
                Text(viewModel.currentStep.title)
                    .font(DS.TypeScale.title)
                    .foregroundStyle(.primary)
                    .id(viewModel.currentStep)
                    .accessibilityIdentifier("onboarding.stepTitle")
                    .transition(.push(from: .top))

                Text(subtitle(for: viewModel.currentStep))
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

    private func subtitle(for step: OnboardingViewModel.Step) -> String {
        switch step {
        case .welcome: return NSLocalizedString("onboarding.subtitle.welcome", value: "Let's configure your workspace.", comment: "")
        case .businessProfile: return NSLocalizedString("onboarding.subtitle.business_profile", value: "Tell us about your grooming business.", comment: "")
        case .regional: return NSLocalizedString("onboarding.subtitle.regional", value: "Set your local currency and contact details.", comment: "")
        case .security: return NSLocalizedString("onboarding.subtitle.security", value: "Secure your business data with a PIN.", comment: "")
        case .permissions: return NSLocalizedString("onboarding.subtitle.permissions", value: "Set your app preferences and unlock method.", comment: "")
        case .warmStart: return NSLocalizedString("onboarding.subtitle.finish", value: "You are all set to start grooming!", comment: "")
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                    .symbolEffect(.bounce, value: viewModel.currentStep)
                
                Text(NSLocalizedString("onboarding.permissions.title", value: "Choose Your Defaults", comment: ""))
                    .font(.title2.bold())
                
                Text(NSLocalizedString("onboarding.permissions.message", value: "These preferences can be changed later in Settings, but getting them right now makes the first session smoother.", comment: ""))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }
            
            VStack(spacing: DS.Spacing.lg) {
                permissionToggle(
                    title: NSLocalizedString("onboarding.permissions.lock_background.title", value: "Lock When App Closes", comment: ""),
                    subtitle: NSLocalizedString("onboarding.permissions.lock_background.subtitle", value: "Require your PIN again whenever Pawtrackr leaves the foreground.", comment: ""),
                    icon: "lock.fill",
                    isOn: $viewModel.lockOnBackgroundEnabled
                )

                permissionToggle(
                    title: NSLocalizedString("onboarding.permissions.auto_lock.title", value: "Lock After Inactivity", comment: ""),
                    subtitle: NSLocalizedString("onboarding.permissions.auto_lock.subtitle", value: "Automatically relock the app after a few idle minutes.", comment: ""),
                    icon: "timer",
                    isOn: $viewModel.autoLockAfterInactivityEnabled
                )
                
                if viewModel.isBiometricsAvailable {
                    permissionToggle(
                        title: viewModel.biometricTitle,
                        subtitle: viewModel.biometricSubtitle,
                        icon: "faceid",
                        isOn: $viewModel.biometricsEnabled
                    )
                } else {
                    biometricUnavailableCard
                }
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
        // Interactive card: when ON it lifts to an accent tint + border and
        // settles into a slightly smaller, "pressed-in" footprint for feedback.
        .background(isOn.wrappedValue ? DS.ColorToken.primary.opacity(0.10) : DS.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .hairlineBorder(isOn.wrappedValue ? DS.ColorToken.primary.opacity(0.55) : DS.ColorToken.border, cornerRadius: 12)
        .scaleEffect(isOn.wrappedValue ? 0.99 : 1.0)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn.wrappedValue)
    }

    /// Shown in place of the biometric toggle when Face ID / Touch ID isn't
    /// available — a styled, non-interactive disclosure rather than a dead row.
    private var biometricUnavailableCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.title2)
                .foregroundStyle(DS.ColorToken.warning)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.biometricTitle).font(.headline)
                Text(NSLocalizedString("onboarding.permissions.biometric_unavailable", value: "Turn on Face ID or Touch ID in your device Settings to speed up checkout unlocks. Your PIN keeps working in the meantime.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .hairlineBorder(DS.ColorToken.warning.opacity(0.4), cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    private var businessCardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if let logoData = viewModel.logoData, let uiImage = PlatformImage(data: logoData) {
                    logoImageView(image: uiImage)
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
                    Text(viewModel.name.trimmed.isEmpty ? NSLocalizedString("onboarding.business.preview_name", value: "Your Business Name", comment: "") : viewModel.name)
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
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                ZStack {
                    // Decorative breathing halo (not matched-geometry, so it can loop
                    // freely without disturbing the shared-logo transition).
                    Circle()
                        .fill(DS.ColorToken.primary.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(welcomeBreathing ? 1.06 : 0.94)

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(DS.ColorToken.primary)
                        .symbolEffect(.pulse, options: .repeating)
                        .matchedGeometryEffect(id: "businessLogo", in: animation)
                }
                .padding(.top, DS.Spacing.xl)

                VStack(spacing: DS.Spacing.sm) {
                    Text(NSLocalizedString("onboarding.welcome.title", value: "Welcome to Pawtrackr", comment: ""))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NSLocalizedString("onboarding.welcome.message", value: "The modern workspace for pet groomers.\nLet's get your business set up in minutes.", comment: ""))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Spacing.xxl)
                .opacity(welcomeAppeared ? 1 : 0)
                .offset(y: welcomeAppeared ? 0 : 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.05), value: welcomeAppeared)

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    featureRow(index: 0, icon: "cloud.fill", title: NSLocalizedString("onboarding.feature.icloud.title", value: "iCloud Sync", comment: ""), subtitle: NSLocalizedString("onboarding.feature.icloud.subtitle", value: "Your data stays safe and synced across all your devices.", comment: ""))
                    featureRow(index: 1, icon: "lock.fill", title: NSLocalizedString("onboarding.feature.privacy.title", value: "Privacy First", comment: ""), subtitle: NSLocalizedString("onboarding.feature.privacy.subtitle", value: "End-to-end security with local-first storage and biometric locking.", comment: ""))
                    featureRow(index: 2, icon: "chart.bar.fill", title: NSLocalizedString("onboarding.feature.insights.title", value: "Business Insights", comment: ""), subtitle: NSLocalizedString("onboarding.feature.insights.subtitle", value: "Track revenue, service trends, and client loyalty effortlessly.", comment: ""))
                }
                .padding(.top, DS.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, DS.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            welcomeAppeared = true
            if !welcomeBreathing {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    welcomeBreathing = true
                }
            }
            if !ctaPulse {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    ctaPulse = true
                }
            }
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
                            Text(viewModel.logoData == nil ? NSLocalizedString("onboarding.business.upload_logo", value: "Upload Business Logo", comment: "") : NSLocalizedString("onboarding.business.change_logo", value: "Change Logo", comment: ""))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(NSLocalizedString("onboarding.business.name", value: "Business Name", comment: "")).font(.headline)
                    TextField(NSLocalizedString("onboarding.business.name_placeholder", value: "e.g. Bark & Bathe Grooming", comment: ""), text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .accessibilityIdentifier("onboarding.businessName")
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                .padding(.horizontal, DS.Spacing.xxl)
                
                Text(NSLocalizedString("onboarding.business.info_message", value: "This information will be used to brand your receipts and reports.", comment: ""))
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
                
                Text(NSLocalizedString("onboarding.regional.contact_message", value: "Contact details are optional. Add them now if you want them on receipts and exports.", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
                
                Card {
                    VStack(spacing: DS.Spacing.md) {
                        onboardingTextField(title: NSLocalizedString("onboarding.regional.email", value: "Contact Email", comment: ""), text: $viewModel.email, icon: "envelope", contentType: .emailAddress)
                        onboardingTextField(title: NSLocalizedString("onboarding.regional.phone", value: "Phone Number", comment: ""), text: $viewModel.phone, icon: "phone", contentType: .telephoneNumber)
                            .phoneFieldFormatting($viewModel.phone)
                        onboardingTextField(title: NSLocalizedString("onboarding.regional.address", value: "Business Address", comment: ""), text: $viewModel.address, icon: "mappin.and.ellipse", axis: .vertical, contentType: .fullStreetAddress)                    }
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
                    Button(NSLocalizedString("common.back", value: "Back", comment: "")) {
                        viewModel.previousStep()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(viewModel.isSaving)
                    .accessibilityIdentifier("onboarding.back")
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
                    // Gentle attention pulse on the very first screen's CTA only.
                    .scaleEffect(viewModel.currentStep == .welcome && ctaPulse ? 1.035 : 1.0)
                    .scaleEffect(viewModel.canGoNext ? 1.0 : 0.98)
                    .animation(.spring(), value: viewModel.canGoNext)
                    .accessibilityIdentifier("onboarding.continue")
                }
            }
        }
        .padding(DS.Spacing.xxl)
        .background(DS.ColorToken.background)
    }
    
    private var securityStep: some View {
        VStack(spacing: DS.Spacing.xxl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                
                Text(NSLocalizedString("onboarding.security.title", value: "Set Your App PIN", comment: ""))
                    .font(.title2.bold())
                
                Text(NSLocalizedString("onboarding.security.message", value: "This 4-digit code will protect your client data.", comment: ""))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: DS.Spacing.xl) {
                pinEntryView(title: NSLocalizedString("onboarding.security.enter_pin", value: "Enter PIN", comment: ""), text: $viewModel.pin, field: .pin)
                pinEntryView(title: NSLocalizedString("onboarding.security.confirm_pin", value: "Confirm PIN", comment: ""), text: $viewModel.confirmPin, field: .confirmPin)
                // Validation messages render in the shared footer to avoid duplicates.
            }

            // Optional path: let solo groomers run the app passcode-free.
            Button {
                focusedField = nil
                viewModel.skipPIN()
            } label: {
                Text(NSLocalizedString("onboarding.security.skip", value: "Skip for now — use without a PIN", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.ColorToken.primary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
            .accessibilityIdentifier("onboarding.skipPin")
        }
        .padding(.top, DS.Spacing.xl)
        .onAppear {
            // Focus the first empty PIN field on entry — but if the user is coming
            // back from a later step with both PINs already filled, leave focus alone.
            if viewModel.pin.filter(\.isNumber).count < 4 {
                focusedField = .pin
            } else if viewModel.confirmPin.filter(\.isNumber).count < 4 {
                focusedField = .confirmPin
            }
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: field)
                    .opacity(0.01)
                    .accessibilityIdentifier(field == .pin ? "onboarding.pinField" : "onboarding.confirmPinField")
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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DS.ColorToken.primary)
                    .symbolEffect(.bounce, value: viewModel.currentStep)

                Text(NSLocalizedString("onboarding.finish.title", value: "You're all set!", comment: ""))
                    .font(.title2.bold())

                Text(NSLocalizedString("onboarding.finish.message", value: "We've loaded a sample salon so you can explore hands-on. Tap below and we'll show you around — clear it anytime with “Start Fresh” in Settings.", comment: ""))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xl)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("onboarding.summary.title", value: "Workspace Summary", comment: ""))
                    .font(.headline)
                Label(viewModel.name.trimmed.isEmpty ? NSLocalizedString("onboarding.summary.business_pending", value: "Business name will be added in setup", comment: "") : viewModel.name.trimmed, systemImage: "building.2")
                Label(String(format: NSLocalizedString("onboarding.summary.currency_fmt", value: "Currency: %@", comment: ""), viewModel.currencySymbol), systemImage: "dollarsign.circle")
                if viewModel.pinSkipped {
                    Label(NSLocalizedString("onboarding.summary.pin_disabled", value: "No PIN — open access", comment: ""), systemImage: "lock.open")
                } else {
                    Label(NSLocalizedString("onboarding.summary.pin_enabled", value: "PIN protection enabled", comment: ""), systemImage: "lock.shield")
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(DS.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .hairlineBorder(DS.ColorToken.border, cornerRadius: 14)
            .padding(.horizontal, DS.Spacing.xxl)

            // Single, unmistakable call to action — every new user starts in the
            // demo and is guided from there. (No "fresh vs demo" fork anymore.)
            Button {
                completeWithCelebration(seed: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text(NSLocalizedString("onboarding.finish.explore", value: "Explore Pawtrackr", comment: ""))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.ColorToken.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(color: DS.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
            .accessibilityIdentifier("onboarding.explore")
            .padding(.horizontal, DS.Spacing.xxl)

            if viewModel.isSaving {
                ProgressView(NSLocalizedString("onboarding.saving", value: "Setting up your workspace...", comment: ""))
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
            }
        }
    }

    
    private func completeWithCelebration(seed: Bool) {
        Task {
            withAnimation(.spring()) {
                showConfetti = true
            }

            // Run the confetti pop and the persistence work concurrently so demo
            // seeding can begin immediately rather than waiting 1.5s of dead time.
            async let pop: Void = Task.sleep(for: .seconds(1.5))
            await viewModel.finish(seedSampleData: seed, onComplete: onComplete)
            try? await pop

            // Tear the confetti down whether we succeeded or failed so it does not
            // hang in the view tree while the alert / parent re-renders.
            withAnimation(.easeOut(duration: 0.2)) {
                showConfetti = false
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
