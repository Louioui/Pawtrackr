//
//  CachedAsyncImage.swift
//  Pawtrackr
//
//  A small wrapper that fetches an image from URL with URLCache + in-memory Data cache,
//  then decodes via ImageCache for downsampled rendering.
//

import SwiftUI
import Combine

final class ImageRemoteLoader: ObservableObject {
    @Published var data: Data? = nil
    @Published var error: Error? = nil
    private var task: URLSessionDataTask?
    private static let mem = NSCache<NSURL, NSData>()

    func load(_ url: URL) {
        let nsurl = url as NSURL
        if let cached = Self.mem.object(forKey: nsurl) {
            self.data = cached as Data
            return
        }
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error
                    return
                }
                if let data = data {
                    Self.mem.setObject(data as NSData, forKey: nsurl)
                    self?.data = data
                }
            }
        }
        task?.priority = URLSessionTask.lowPriority
        task?.resume()
    }

    func cancel() { task?.cancel() }
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

