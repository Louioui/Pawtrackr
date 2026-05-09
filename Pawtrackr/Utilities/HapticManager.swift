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

    /// Plays a transient impact (button tap, chip toggle, small affordance).
    static func impact(_ style: Impact = .light) {
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy: generator = UIImpactFeedbackGenerator(style: .heavy)
        case .soft: generator = UIImpactFeedbackGenerator(style: .soft)
        case .rigid: generator = UIImpactFeedbackGenerator(style: .rigid)
        }
        generator.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }

    /// Selection changed feedback for segmented controls, pickers, etc.
    static func selectionChanged() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Plays a notification haptic (success, warning, error).
    static func notify(_ type: NotificationType) {
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
