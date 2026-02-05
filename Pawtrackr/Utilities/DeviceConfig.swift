//
//  DeviceConfig.swift
//  Pawtrackr
//
//  Centralized, cross‑platform device heuristics for sizing and quality.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DeviceConfig {
    enum Class { case smallPhone, phone, tablet, desktop, other }

    static var deviceClass: Class {
        #if canImport(UIKit)
        let w = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        if w < 360 { return .smallPhone }
        if w < 600 { return .phone }
        return .tablet
        #elseif os(macOS)
        return .desktop
        #else
        return .other
        #endif
    }

    static var imageMaxDimension: CGFloat? {
        switch deviceClass {
        case .smallPhone: return 1200
        case .phone:      return 1600
        case .tablet:     return 2400
        case .desktop:    return 2400  // High quality for Retina displays
        case .other:      return 1600
        }
    }

    static var jpegQuality: CGFloat {
        switch deviceClass {
        case .smallPhone: return 0.80
        case .phone:      return 0.85
        case .tablet:     return 0.88
        case .desktop:    return 0.90  // Higher quality for macOS
        case .other:      return 0.85
        }
    }
}

