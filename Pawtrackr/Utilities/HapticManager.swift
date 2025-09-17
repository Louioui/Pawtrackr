//
//  HapticManager.swift
//  Pawtrackr
//
//  Centralized, lightweight haptics manager.
//  Replaces scattered UIImpactFeedbackGenerator calls for consistency
//  and future tuning (e.g., intensity, rate limiting, user settings).
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum HapticManager {
    enum Impact: CaseIterable { case light, medium, heavy, soft, rigid }
    enum NotificationType { case success, warning, error }

    /// Plays a transient impact (button tap, chip toggle, small affordance).
    static func impact(_ style: Impact = .light) {
        #if canImport(UIKit)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy: generator = UIImpactFeedbackGenerator(style: .heavy)
        case .soft:
            if #available(iOS 13.0, *) { generator = UIImpactFeedbackGenerator(style: .soft) }
            else { generator = UIImpactFeedbackGenerator(style: .light) }
        case .rigid:
            if #available(iOS 13.0, *) { generator = UIImpactFeedbackGenerator(style: .rigid) }
            else { generator = UIImpactFeedbackGenerator(style: .heavy) }
        }
        generator.impactOccurred()
        #endif
    }

    /// Selection changed feedback for segmented controls, pickers, etc.
    static func selectionChanged() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Plays a notification haptic (success, warning, error).
    static func notify(_ type: NotificationType) {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: feedbackType = .success
        case .warning: feedbackType = .warning
        case .error: feedbackType = .error
        }
        generator.notificationOccurred(feedbackType)
        #endif
    }
}

