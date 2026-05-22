//
//  HapticManager.swift
//  Pawtrackr
//
//  Centralized, cross-platform haptics manager.
//  Provides tactile feedback on iOS (Taptic Engine) and macOS (Force Touch Trackpad).
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum HapticManager {
    enum Impact: CaseIterable { case light, medium, heavy, soft, rigid }
    enum NotificationType { case success, warning, error }

    #if os(iOS)
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    /// Per-call UserDefaults check so the Settings toggle silences haptics
    /// immediately without rewiring every call site. Defaults to enabled when
    /// the key is missing so legacy installs keep their existing behavior.
    /// Key must mirror `AppSettingsKeys.hapticsEnabled` — kept inline so this
    /// file stays dependency-free from AppSettings.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    /// Plays a transient impact (button tap, chip toggle, small affordance).
    static func impact(_ style: Impact = .light) {
        guard isEnabled else { return }
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = lightGen
        case .medium: generator = mediumGen
        case .heavy: generator = heavyGen
        case .soft: generator = softGen
        case .rigid: generator = rigidGen
        }
        generator.prepare()
        generator.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }

    /// Selection changed feedback for segmented controls, pickers, etc.
    static func selectionChanged() {
        guard isEnabled else { return }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Plays a notification haptic (success, warning, error).
    static func notify(_ type: NotificationType) {
        guard isEnabled else { return }
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: feedbackType = .success
        case .warning: feedbackType = .warning
        case .error: feedbackType = .error
        }
        generator.notificationOccurred(feedbackType)
        #elseif os(macOS)
        switch type {
        case .success:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        case .warning, .error:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
        #endif
    }
}
