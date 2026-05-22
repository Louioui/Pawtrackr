//
//  CloudMediaPolicy.swift
//  Pawtrackr
//
//  Central media sizing policy for CloudKit-backed SwiftData payloads.
//

import Foundation
import CoreGraphics

enum CloudMediaPolicy {
    static let optimizedMediaDefaultsKey = "icloud.optimizeMediaForSync"
    static let largeAssetWarningBytes = 3 * 1024 * 1024

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

    static func optimizedFullImageData(_ data: Data, context: String) -> Data? {
        let output = ImageCache.shared.downsampleToData(
            data: data,
            maxDimension: fullImageMaxDimension ?? 1600,
            compressionQuality: jpegQuality
        )
        let byteCount = output?.count ?? data.count
        Task { @MainActor in
            CloudKitMonitor.shared.recordMediaSyncWarningIfNeeded(byteCount: byteCount, context: context)
        }
        return output
    }

    static func optimizedThumbnailData(_ data: Data) -> Data? {
        ImageCache.shared.downsampleToData(
            data: data,
            maxDimension: thumbnailMaxDimension,
            compressionQuality: 0.72
        )
    }
}
