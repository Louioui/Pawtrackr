//
//  Image+Extensions.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Image {
    #if canImport(UIKit)
    init?(fromData data: Data, maxDimension: CGFloat) {
        guard let uiImage = ImageCache.shared.image(data: data, maxDimension: maxDimension) else {
            return nil
        }
        self.init(uiImage: uiImage)
    }
    #endif
}
