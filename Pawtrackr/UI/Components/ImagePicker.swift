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
import UniformTypeIdentifiers
import ImageIO
import OSLog

#if canImport(UIKit)
import PhotosUI
#endif

private let imagePickerLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ImagePicker")

// MARK: - Public Types (Cross-Platform)
public enum ImagePickerSource: Equatable {
    case library
    case camera
    /// Presents a prompt letting the user choose camera or library at runtime.
    /// On macOS, this behaves as .library since there's no device camera.
    case prompt
}

#if canImport(UIKit) // iOS/visionOS implementation

public struct ImagePicker<Label: View>: View {
    @Binding private var imageData: Data?
    private let source: ImagePickerSource
    private let allowsEditing: Bool
    private let maxDimension: CGFloat?
    private let jpegQuality: CGFloat?
    private let label: () -> Label

    @State private var isPresenting = false
    @State private var isPrompting = false
    @State private var resolvedSource: ImagePickerSource = .library
    
    public init(imageData: Binding<Data?>,
                source: ImagePickerSource = .prompt,
                allowsEditing: Bool = true,
                maxDimension: CGFloat? = nil,
                jpegQuality: CGFloat? = nil,
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
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    resolvedSource = .camera
                    isPresenting = true
                }
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
    let jpegQuality: CGFloat?
    
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
                if let image = await loadImage(from: result.itemProvider) {
                    let md = parent.maxDimension ?? DeviceConfig.imageMaxDimension
                    let jq = parent.jpegQuality ?? DeviceConfig.jpegQuality
                    let processor = ImageProcessor(maxDimension: md, jpegQuality: jq)
                    let data = await processor.process(image: image)
                    await MainActor.run {
                        parent.imageData = data
                    }
                }
            }
        }
        
        // UIImagePicker (Camera) Delegate
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage else { return }
            
            Task {
                let md = parent.maxDimension ?? DeviceConfig.imageMaxDimension
                let jq = parent.jpegQuality ?? DeviceConfig.jpegQuality
                let processor = ImageProcessor(maxDimension: md, jpegQuality: jq)
                let data = await processor.process(image: image)
                await MainActor.run {
                    parent.imageData = data
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        
        private func loadImage(from provider: NSItemProvider) async -> UIImage? {
            // Prefer UIImage for correct color profiles; fall back to raw data.
            if provider.canLoadObject(ofClass: UIImage.self) {
                do {
                    return try await loadUIImage(from: provider)
                } catch {
                    imagePickerLog.error("Failed to load UIImage from provider: \(error.localizedDescription, privacy: .public)")
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                do {
                    let data = try await loadData(from: provider, typeIdentifier: UTType.image.identifier)
                    return UIImage(data: data)
                } catch {
                    imagePickerLog.error("Failed to load image Data from provider: \(error.localizedDescription, privacy: .public)")
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

#elseif canImport(AppKit) // macOS implementation

import AppKit

public struct ImagePicker<Label: View>: View {
    @Binding private var imageData: Data?
    private let source: ImagePickerSource
    private let allowsEditing: Bool
    private let maxDimension: CGFloat?
    private let jpegQuality: CGFloat?
    private let label: () -> Label

    public init(imageData: Binding<Data?>,
                source: ImagePickerSource = .library,
                allowsEditing: Bool = true,
                maxDimension: CGFloat? = nil,
                jpegQuality: CGFloat? = nil,
                @ViewBuilder label: @escaping () -> Label) {
        _imageData = imageData
        self.source = source
        self.allowsEditing = allowsEditing
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.label = label
    }

    public var body: some View {
        Button(action: openFilePicker) {
            label()
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select Image"
        panel.message = "Choose an image file"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await loadImage(from: url)
            }
        }
    }

    @MainActor
    private func loadImage(from url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }

        let md = maxDimension ?? DeviceConfig.imageMaxDimension
        let jq = jpegQuality ?? DeviceConfig.jpegQuality
        let processor = MacImageProcessor(maxDimension: md, jpegQuality: jq)
        imageData = await processor.process(data: data)
    }
}

// MARK: - macOS Image Processing Actor
private actor MacImageProcessor {
    let maxDimension: CGFloat?
    let jpegQuality: CGFloat

    init(maxDimension: CGFloat?, jpegQuality: CGFloat) {
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
    }

    func process(data: Data) -> Data? {
        guard let nsImage = NSImage(data: data) else { return nil }
        return process(image: nsImage)
    }

    func process(image: NSImage) -> Data? {
        let downsized = image.downsized(toMaxDimension: maxDimension)

        // Convert to JPEG
        guard let tiffData = downsized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
    }
}

// MARK: - NSImage Helpers
fileprivate extension NSImage {
    func downsized(toMaxDimension maxDimension: CGFloat?) -> NSImage {
        guard let maxDimension, maxDimension > 0 else { return self }

        let width = size.width
        let height = size.height
        let longest = max(width, height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let newSize = NSSize(width: floor(width * scale), height: floor(height * scale))

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

#endif
