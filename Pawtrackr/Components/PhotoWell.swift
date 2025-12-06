
//
//  PhotoWell.swift
//  Pawtrackr
//
//  Created by Assistant on 9/15/25.
//

import SwiftUI

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
                if let data = imageData, let image = Image(fromData: data, maxDimension: UIScreen.main.bounds.width * UIScreen.main.scale) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    AddPhotoPlaceholder(title: title, subtitle: "Tap to add")
                }
            }
            .frame(maxWidth: .infinity, idealHeight: 160)
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
