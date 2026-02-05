//
//  Image+Extensions.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    #if canImport(UIKit)
    init?(fromData data: Data, maxDimension: CGFloat) {
        guard let uiImage = ImageCache.shared.image(data: data, maxDimension: maxDimension) else {
            return nil
        }
        self.init(uiImage: uiImage)
    }
    #elseif canImport(AppKit)
    init?(fromData data: Data, maxDimension: CGFloat) {
        guard let nsImage = ImageCache.shared.image(data: data, maxDimension: maxDimension) else {
            return nil
        }
        self.init(nsImage: nsImage)
    }
    #endif
}
