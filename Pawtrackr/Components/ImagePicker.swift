//
//  ImagePicker.swift
//  Pawtrackr
//
//  Reusable SwiftUI image picker that binds to raw image `Data?`.
//  - Uses PHPicker on iOS 14+ (PhotosUI) — note: `allowsEditing` is ignored by PHPicker
//  - Falls back to UIImagePickerController where needed (respects `allowsEditing`)
//  - Optional downscaling + JPEG quality control to keep payloads small
//  - Safe no-op on non‑UIKit platforms
//  - Accepts a custom label/content (e.g., your dashed photo boxes)
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI

public struct ImagePicker<Label: View>: View {
    @Binding private var imageData: Data?
    private let allowsEditing: Bool
    private let maxDimension: CGFloat?
    private let jpegQuality: CGFloat
    @ViewBuilder private var label: () -> Label

    @State private var isPresenting = false

    public init(imageData: Binding<Data?>,
                allowsEditing: Bool = false,
                maxDimension: CGFloat? = nil,
                jpegQuality: CGFloat = 0.9,
                @ViewBuilder label: @escaping () -> Label) {
        self._imageData = imageData
        self.allowsEditing = allowsEditing
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.label = label
    }

    public var body: some View {
        Button(action: { isPresenting = true }) {
            label()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresenting) {
            #if canImport(UIKit)
            _PickerHost(imageData: $imageData, allowsEditing: allowsEditing, maxDimension: maxDimension, jpegQuality: jpegQuality)
            #else
            Text("Image picking not available on this platform")
                .padding()
            #endif
        }
    }
}

// MARK: - UIKit/PhotosUI bridge

#if canImport(UIKit)
import UIKit
#if canImport(PhotosUI)
import PhotosUI
#endif

fileprivate struct _PickerHost: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    let allowsEditing: Bool
    let maxDimension: CGFloat?
    let jpegQuality: CGFloat

    func makeUIViewController(context: Context) -> UIViewController {
        // Prefer PHPicker if available (modern, no permission prompt)
        #if canImport(PhotosUI)
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
        #else
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        return picker
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: _PickerHost
        init(_ parent: _PickerHost) { self.parent = parent }
    }
}

#if canImport(PhotosUI)
extension _PickerHost.Coordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        defer { picker.dismiss(animated: true) }
        guard let provider = results.first?.itemProvider else { return }
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    let processed = image._downsized(toMaxDimension: self.parent.maxDimension)
                    if let data = processed.jpegData(compressionQuality: self.parent.jpegQuality) {
                        DispatchQueue.main.async { self.parent.imageData = data }
                    }
                }
            }
        }
    }
}
#endif

extension _PickerHost.Coordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        defer { picker.dismiss(animated: true) }
        let key: UIImagePickerController.InfoKey = parent.allowsEditing ? .editedImage : .originalImage
        if let image = info[key] as? UIImage {
            let processed = image._downsized(toMaxDimension: parent.maxDimension)
            if let data = processed.jpegData(compressionQuality: parent.jpegQuality) {
                parent.imageData = data
            }
        }
    }
}

private extension UIImage {
    func _downsized(toMaxDimension maxDimension: CGFloat?) -> UIImage {
        guard let maxDimension, maxDimension > 0 else { return self }
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // we control pixel size explicitly
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif

// MARK: - Preview

struct ImagePicker_Previews: PreviewProvider {
    struct Demo: View {
        @State private var before: Data? = nil
        var body: some View {
            ImagePicker(imageData: $before, maxDimension: 2048, jpegQuality: 0.8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6,6]))
                        .foregroundStyle(.gray.opacity(0.25))
                        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.08)))
                        .frame(width: 140, height: 140)
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title3).foregroundStyle(.secondary)
                        Text("Pick Photo").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static var previews: some View {
        Demo().padding()
    }
}
