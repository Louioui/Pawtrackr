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
    private var timer: DispatchSourceTimer?

    private init() { resume() }

    /// Start a wall-clock-aligned 1s ticker on the main actor.
    func resume() {
        guard !isRunning else { return }
        timer?.cancel()
        timer = nil

        // Align the first fire to the next whole second to avoid drift.
        let nowDate = Date()
        let nowRef = nowDate.timeIntervalSinceReferenceDate
        let nextWhole = ceil(nowRef)
        let delay = max(0, nextWhole - nowRef)

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + delay, repeating: .seconds(1), leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            self?.now = Date()
        }
        t.resume()
        timer = t
        isRunning = true
    }

    func pause() {
        guard isRunning else { return }
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    deinit { timer?.cancel() }
}
