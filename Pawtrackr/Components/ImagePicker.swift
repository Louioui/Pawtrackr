//
//  ImagePicker.swift
//  Pawtrackr
//
//  - Modernized with async/await for cleaner concurrency.
//  - Image processing logic is now encapsulated in a dedicated ImageProcessor actor.
//  - Uses modern PHPicker with async/await APIs where possible.
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 2025-09-03.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

#if canImport(UIKit) // Ensure this code only compiles on iOS/visionOS etc.

// MARK: - Public View
public enum ImagePickerSource: Equatable {
    case library
    case camera
    /// Presents a prompt letting the user choose camera or library at runtime.
    case prompt
}

public struct ImagePicker<Label: View>: View {
    @Binding private var imageData: Data?
    private let source: ImagePickerSource
    private let allowsEditing: Bool
    private let maxDimension: CGFloat?
    private let jpegQuality: CGFloat
    private let label: () -> Label

    @State private var isPresenting = false
    @State private var isPrompting = false
    @State private var resolvedSource: ImagePickerSource = .library
    
    public init(imageData: Binding<Data?>,
                source: ImagePickerSource = .prompt,
                allowsEditing: Bool = true,
                maxDimension: CGFloat? = 1600,
                jpegQuality: CGFloat = 0.85,
                @ViewBuilder label: @escaping () -> Label) {
        _imageData = imageData
        self.source = source
        self.allowsEditing = allowsEditing
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.label = label
    }

    public var body: some View {
        Button(action: present) {
            label()
        }
        .confirmationDialog("Choose Photo Source", isPresented: $isPrompting, titleVisibility: .visible) {
            Button("Camera") {
                resolvedSource = .camera
                isPresenting = true
            }
            Button("Photo Library") {
                resolvedSource = .library
                isPresenting = true
            }
        }
        .sheet(isPresented: $isPresenting) {
            ImagePickerRepresentable(
                imageData: $imageData,
                source: resolvedSource,
                allowsEditing: allowsEditing,
                maxDimension: maxDimension,
                jpegQuality: jpegQuality
            )
        }
    }

    private func present() {
        if source == .prompt {
            isPrompting = true
        } else {
            resolvedSource = source
            isPresenting = true
        }
    }
}

// MARK: - Core Representable
private struct ImagePickerRepresentable: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    let source: ImagePickerSource
    let allowsEditing: Bool
    let maxDimension: CGFloat?
    let jpegQuality: CGFloat
    
    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .library, .prompt:
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
            
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.allowsEditing = allowsEditing
                picker.delegate = context.coordinator
                return picker
            } else {
                let vc = UIViewController()
                let label = UILabel()
                label.text = "Camera Not Available"
                label.textAlignment = .center
                vc.view = label
                return vc
            }
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePickerRepresentable
        
        init(parent: ImagePickerRepresentable) {
            self.parent = parent
        }
        
        // PHPicker (Library) Delegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            
            Task {
                if let data = await loadImageData(from: result.itemProvider) {
                    let processor = ImageProcessor(maxDimension: parent.maxDimension, jpegQuality: parent.jpegQuality)
                    parent.imageData = await processor.process(data: data)
                }
            }
        }
        
        // UIImagePicker (Camera) Delegate
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage else { return }
            
            Task {
                let processor = ImageProcessor(maxDimension: parent.maxDimension, jpegQuality: parent.jpegQuality)
                parent.imageData = await processor.process(image: image)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        private func loadImageData(from provider: NSItemProvider) async -> Data? {
            // Prefer UIImage for correct color profiles; fall back to raw data.
            if provider.canLoadObject(ofClass: UIImage.self) {
                do {
                    let image = try await loadUIImage(from: provider)
                    return image.jpegData(compressionQuality: 1.0)
                } catch {
                    print("Failed to load UIImage from provider: \(error.localizedDescription)")
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                do {
                    let data = try await loadData(from: provider, typeIdentifier: UTType.image.identifier)
                    return data
                } catch {
                    print("Failed to load image Data from provider: \(error.localizedDescription)")
                }
            }

            return nil
        }

        // MARK: - Async wrappers for NSItemProvider
        private func loadUIImage(from provider: NSItemProvider) async throws -> UIImage {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let image = object as? UIImage {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ImagePicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UIImage"]))
                    }
                }
            }
        }

        private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ImagePicker", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data returned"]))
                    }
                }
            }
        }
    }
}

// MARK: - Image Processing Actor
private actor ImageProcessor {
    let maxDimension: CGFloat?
    let jpegQuality: CGFloat

    init(maxDimension: CGFloat?, jpegQuality: CGFloat) {
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
    }
    
    func process(image: UIImage) -> Data? {
        let normalized = image.normalizedOrientation()
        let downsized = normalized.downsized(toMaxDimension: maxDimension)
        return downsized.jpegData(compressionQuality: jpegQuality)
    }

    func process(data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return process(image: image)
    }
}

// MARK: - UIImage Helpers
fileprivate extension UIImage {
    func downsized(toMaxDimension maxDimension: CGFloat?) -> UIImage {
        guard let maxDimension, maxDimension > 0 else { return self }
        let width = size.width
        let height = size.height
        let longest = max(width, height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif

