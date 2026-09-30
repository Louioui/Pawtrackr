//
//  LocalMediaPolicy.swift
//  Pawtrackr
//
//  Central media sizing policy for local SwiftData photo storage.
//

import Foundation
import CoreGraphics

enum LocalMediaPolicy {
    static let optimizedMediaDefaultsKey = "media.optimizeStorage"

    static var isOptimizationEnabled: Bool {
        if UserDefaults.standard.object(forKey: optimizedMediaDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: optimizedMediaDefaultsKey)
    }

    static var fullImageMaxDimension: CGFloat? {
        guard isOptimizationEnabled else { return DeviceConfig.rawImageMaxDimension }
        guard let raw = DeviceConfig.rawImageMaxDimension else { return 1600 }
        return min(raw, 1600)
    }

    static var thumbnailMaxDimension: CGFloat {
        isOptimizationEnabled ? 240 : 300
    }

    static var jpegQuality: CGFloat {
        guard isOptimizationEnabled else { return DeviceConfig.rawJPEGQuality }
        return min(DeviceConfig.rawJPEGQuality, 0.82)
    }

    /// Downsamples a photo for bounded local storage and decoding costs.
    static func optimizedFullImageData(_ data: Data, context: String) -> Data? {
        let output = ImageCache.shared.downsampleToData(
            data: data,
            maxDimension: fullImageMaxDimension ?? 1600,
            compressionQuality: jpegQuality
        )
        return output
    }

    /// Creates a small preview that can be decoded efficiently in lists.
    static func optimizedThumbnailData(_ data: Data) -> Data? {
        ImageCache.shared.downsampleToData(
            data: data,
            maxDimension: thumbnailMaxDimension,
            compressionQuality: 0.72
        )
    }
}
