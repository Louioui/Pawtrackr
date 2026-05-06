//
//  PhotoWell.swift
//  Pawtrackr
//
//  Created by Assistant on 9/15/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A reusable component that displays a photo, a placeholder, and handles the tap-to-pick-image action.
struct PhotoWell: View {
    @Binding var imageData: Data?
    let title: String
    let allowsEditing: Bool

    init(imageData: Binding<Data?>, title: String, allowsEditing: Bool = true) {
        self._imageData = imageData
        self.title = title
        self.allowsEditing = allowsEditing
    }

    var body: some View {
        ImagePicker(imageData: $imageData, allowsEditing: allowsEditing) {
            ZStack {
                if let data = imageData {
                    LazyImageDataImage(data: data, maxDimension: 512)
                } else {
                    #if os(macOS)
                    AddPhotoPlaceholder(title: title, subtitle: "Click to add")
                    #else
                    AddPhotoPlaceholder(title: title, subtitle: "Tap to add")
                    #endif
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .contextMenu {
            if imageData != nil {
                Button(role: .destructive) {
                    imageData = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        }
    }
}

/// Decodes image data asynchronously to keep the UI perfectly fluid.
struct LazyImageDataImage: View {
    let data: Data
    let maxDimension: CGFloat
    
    @State private var image: Image? = nil
    
    var body: some View {
        ZStack {
            if let image = image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .task(id: data) {
            // Decode off the main thread
            await loadImage()
        }
    }
    
    private func loadImage() async {
        let decoded = await Task.detached(priority: .userInitiated) { () -> Image? in
            #if canImport(UIKit)
            if let ui = ImageCache.shared.image(data: data, maxDimension: maxDimension) {
                return Image(uiImage: ui)
            }
            #elseif canImport(AppKit)
            if let ns = ImageCache.shared.image(data: data, maxDimension: maxDimension) {
                return Image(nsImage: ns)
            }
            #endif
            return nil
        }.value
        
        await MainActor.run {
            self.image = decoded
        }
    }
}

/// A standardized placeholder for photo wells.
struct AddPhotoPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
            VStack(spacing: 4) {
                Image(systemName: "camera")
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
