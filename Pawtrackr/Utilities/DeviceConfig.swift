//
//  DeviceConfig.swift
//  Pawtrackr
//
//  Centralized, cross‑platform device heuristics for sizing and quality.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

struct DeviceConfig {
    enum Class { case smallPhone, phone, tablet, other }

    static var deviceClass: Class {
        #if canImport(UIKit)
        let w = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        if w < 360 { return .smallPhone }
        if w < 600 { return .phone }
        return .tablet
        #else
        return .other
        #endif
    }

    static var imageMaxDimension: CGFloat? {
        #if canImport(UIKit)
        switch deviceClass {
        case .smallPhone: return 1200
        case .phone:      return 1600
        case .tablet:     return 2400
        case .other:      return 1600
        }
        #else
        return nil
        #endif
    }

    static var jpegQuality: CGFloat {
        #if canImport(UIKit)
        switch deviceClass {
        case .smallPhone: return 0.80
        case .phone:      return 0.85
        case .tablet:     return 0.88
        case .other:      return 0.85
        }
        #else
        return 0.85
        #endif
    }
}

