 //
//  CachedAsyncImage.swift
//  Pawtrackr
//
//  A small wrapper that fetches an image from URL with URLCache + in-memory Data cache,
//  then decodes via ImageCache for downsampled rendering.
//

import SwiftUI
import Combine

@MainActor
@Observable
final class ImageRemoteLoader {
    var data: Data? = nil
    var error: Error? = nil
    var isLoading: Bool = false
    
    private var currentTask: Task<Void, Never>?

    func load(_ url: URL) {
        currentTask?.cancel()
        isLoading = true
        currentTask = Task {
            do {
                let data = try await ImageLoaderService.shared.fetch(for: url)
                
                guard !Task.isCancelled else { return }
                self.data = data
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                self.isLoading = false
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    let url: URL
    let maxDimension: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var loader = ImageRemoteLoader()

    var body: some View {
        Group {
            if let data = loader.data {
                #if canImport(UIKit)
                if let ui = ImageCache.shared.image(data: data, maxDimension: maxDimension) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    failure()
                }
                #else
                if let ns = ImageCache.shared.image(data: data, maxDimension: maxDimension) {
                    Image(nsImage: ns).resizable().scaledToFill()
                } else {
                    failure()
                }
                #endif
            } else if loader.error != nil {
                failure()
            } else {
                placeholder()
            }
        }
        .task { loader.load(url) }
    }
}

