//
//  ImageLoaderService.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import Foundation
import Combine
import SwiftUI

/// A thread-safe image loader service that handles caching and deduplication of requests.
/// Refactored to an Actor for Swift 6 concurrency safety.
actor ImageLoaderService {
    static let shared = ImageLoaderService()
    
    private var publishers = [URL: AnyPublisher<Data, Error>]()
    private let cache = NSCache<NSURL, NSData>()
    
    private init() {}
    
    /// Returns a publisher for the given URL. 
    /// Note: This is nonisolated to allow Combine usage in views, but it handles internal state safely.
    nonisolated func publisher(for url: URL) -> AnyPublisher<Data, Error> {
        // We use a Task to bridge the actor's isolated state to the nonisolated publisher context
        // for checking the cache and existing publishers.
        return Deferred {
            Future { promise in
                Task {
                    let data = await self.getCachedData(for: url)
                    if let data = data {
                        promise(.success(data))
                        return
                    }
                    
                    let pub = await self.getOrCreatePublisher(for: url)
                    var cancellable: AnyCancellable?
                    cancellable = pub.sink(receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                        cancellable?.cancel()
                    }, receiveValue: { data in
                        promise(.success(data))
                        cancellable?.cancel()
                    })
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Modern async fetch method for image data.
    func fetch(for url: URL) async throws -> Data {
        if let data = cache.object(forKey: url as NSURL) {
            return data as Data
        }
        
        let publisher = getOrCreatePublisher(for: url)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var cancellable: AnyCancellable?
            cancellable = publisher
                .first()
                .sink(receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                }, receiveValue: { data in
                    continuation.resume(returning: data)
                    cancellable?.cancel()
                })
        }
    }
    
    // MARK: - Private Actor Isolated Helpers
    
    private func getCachedData(for url: URL) -> Data? {
        return cache.object(forKey: url as NSURL) as Data?
    }
    
    private func getOrCreatePublisher(for url: URL) -> AnyPublisher<Data, Error> {
        if let existing = publishers[url] {
            return existing
        }

        let publisher = URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .mapError { $0 as Error }
            .handleEvents(
                receiveOutput: { [weak self] data in
                    Task { [weak self] in
                        await self?.finalizeDownload(url: url, data: data)
                    }
                },
                receiveCompletion: { [weak self] completion in
                    // Failure case: the previous code only cleared `publishers[url]`
                    // on `receiveOutput`, so a failed download left a stale
                    // publisher entry forever. Clear on any terminal completion.
                    if case .failure = completion {
                        Task { [weak self] in
                            await self?.discardPublisher(for: url)
                        }
                    }
                }
            )
            .share()
            .eraseToAnyPublisher()

        publishers[url] = publisher
        return publisher
    }

    private func finalizeDownload(url: URL, data: Data) {
        cache.setObject(data as NSData, forKey: url as NSURL)
        publishers[url] = nil
    }

    private func discardPublisher(for url: URL) {
        publishers[url] = nil
    }
}
