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
final class ImageRemoteLoader: ObservableObject {
    @Published var data: Data? = nil
    @Published var error: Error? = nil
    
    private var cancellable: AnyCancellable?

    func load(_ url: URL) {
        cancellable = ImageLoaderService.shared.publisher(for: url)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error
                }
            }, receiveValue: { [weak self] data in
                self?.data = data
            })
    }

    func cancel() {
        cancellable?.cancel()
    }
}

struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    let url: URL
    let maxDimension: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @StateObject private var loader = ImageRemoteLoader()

    var body: some View {
        content
            .onAppear { loader.load(url) }
            .onDisappear { loader.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(UIKit)
        if let data = loader.data, let ui = ImageCache.shared.image(data: data, maxDimension: maxDimension) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else if loader.error != nil {
            failure()
        } else {
            placeholder()
        }
        #else
        if let data = loader.data, let ns = NSImage(data: data) {
            Image(nsImage: ns).resizable().scaledToFill()
        } else if loader.error != nil {
            failure()
        } else {
            placeholder()
        }
        #endif
    }
}

