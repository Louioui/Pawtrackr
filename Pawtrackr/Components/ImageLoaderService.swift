//
//  ImageLoaderService.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import Foundation
import Combine
import SwiftUI

class ImageLoaderService {
    static let shared = ImageLoaderService()
    
    private var publishers = [URL: AnyPublisher<Data, Error>]()
    private let cache = NSCache<NSURL, NSData>()
    
    private init() {}
    
    func publisher(for url: URL) -> AnyPublisher<Data, Error> {
        let nsurl = url as NSURL
        if let publisher = publishers[url] {
            return publisher
        }
        
        if let data = cache.object(forKey: nsurl) {
            return Just(data as Data)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        let publisher = URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .mapError { $0 as Error }
            // Cache the downloaded data before publishing it
            .handleEvents(receiveOutput: { [weak self] data in
                self?.cache.setObject(data as NSData, forKey: nsurl)
            })
            .share()
            .eraseToAnyPublisher()
        
        publishers[url] = publisher
        
        return publisher
    }
}
