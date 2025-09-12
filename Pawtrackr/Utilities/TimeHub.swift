//
//  TimeHub.swift
//  Pawtrackr
//
//  A shared, main-actor time source that ticks once per second.
//  Views and helpers (e.g., VisitTimer) can subscribe to keep all timers in sync.
//

import Foundation
import Combine

@MainActor
final class TimeHub: ObservableObject {
    static let shared = TimeHub()

    @Published var now: Date = Date()
    private(set) var isRunning: Bool = false
    private var timer: Timer?

    private init() { resume() }

    func resume() {
        guard !isRunning else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
    }

    func pause() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    deinit { timer?.invalidate() }
}
