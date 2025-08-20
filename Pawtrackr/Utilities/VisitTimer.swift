//
//  VisitTimer.swift
//  Pawtrackr
//
//  Created by mac on 8/17/25.
//


//
//  VisitTimer.swift
//  Pawtrackr
//
//  Created by mac on 8/17/25.
//

import Foundation
import Combine

/// A lightweight, UI-friendly stopwatch for active visits.
/// - Does **not** reference app model types to avoid access-control cycles.
/// - Ticks on the main actor every 1s with a small tolerance to save battery.
/// - Survives background/foreground by computing elapsed from absolute dates.
@MainActor
final class VisitTimer: ObservableObject {

    // MARK: - Published state

    /// `true` while the timer is running.
    @Published private(set) var isRunning: Bool = false

    /// Start timestamp for the current run.
    @Published private(set) var startedAt: Date?

    /// Optional end timestamp (set on stop); nil while running.
    @Published private(set) var endedAt: Date?

    /// Whole seconds elapsed for the *current* run (derived from `startedAt`).
    @Published private(set) var elapsedSeconds: Int = 0 {
        didSet { formattedElapsed = Self.format(seconds: elapsedSeconds) }
    }

    /// Human-friendly clock string like "1h 12m" (USD app uses English).
    @Published private(set) var formattedElapsed: String = "0m"

    // MARK: - Internal state

    /// Accumulated seconds from previous runs (if the timer was paused/resumed).
    private var accumulatedSeconds: Int = 0

    /// The ticking subscription.
    private var tickCancellable: AnyCancellable?

    // MARK: - Lifecycle

    deinit {
        tickCancellable?.cancel()
    }

    // MARK: - Public API

    /// Start (or resume) the timer at a specific wall-clock time.
    /// - Parameter date: If omitted, uses `Date.now`.
    func start(at date: Date = .now) {
        // If already running, ignore.
        guard !isRunning else { return }

        // If there was a previous run that ended, *resume* by keeping accumulatedSeconds.
        if startedAt == nil {
            startedAt = date
        } else {
            // On resume, shift startedAt so (now - startedAt) + accumulated == total so far.
            startedAt = date.addingTimeInterval(TimeInterval(-accumulatedSeconds))
        }

        endedAt = nil
        isRunning = true
        beginTicking()
        updateElapsed(now: date)
    }

    /// Stop the timer and freeze elapsed.
    /// - Parameter date: If omitted, uses `Date.now`.
    func stop(at date: Date = .now) {
        guard isRunning else { return }
        isRunning = false
        endedAt = date

        // Finalize accumulation and clear startedAt (we keep endedAt for reference).
        if let started = startedAt {
            accumulatedSeconds = Self.seconds(between: started, and: date)
        }
        startedAt = nil

        endTicking()
        updateElapsed(now: date)
    }

    /// Reset to initial state (not running, zeroed time).
    func reset() {
        endTicking()
        isRunning = false
        startedAt = nil
        endedAt = nil
        accumulatedSeconds = 0
        elapsedSeconds = 0
    }

    /// Manually set the elapsed total (e.g., when restoring from a visit).
    /// If `running` is true, it will continue from this value.
    func setElapsed(seconds: Int, running: Bool) {
        accumulatedSeconds = max(0, seconds)
        if running {
            // Continue from now with accumulated baseline.
            startedAt = .now.addingTimeInterval(TimeInterval(-accumulatedSeconds))
            endedAt = nil
            isRunning = true
            beginTicking()
            updateElapsed(now: .now)
        } else {
            startedAt = nil
            endedAt = .now
            isRunning = false
            endTicking()
            elapsedSeconds = accumulatedSeconds
        }
    }

    // MARK: - Formatting

    /// Short human format like `1h 05m`, `12m`, or `45s` for sub-minute.
    static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60

        if hours > 0 {
            // e.g., 1h 02m
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            // e.g., 12m
            return "\(minutes)m"
        } else {
            // e.g., 45s
            return "\(secs)s"
        }
    }

    // MARK: - Private helpers

    private func beginTicking() {
        // Cancel any previous ticking.
        tickCancellable?.cancel()

        // Publisher fires roughly every second on the main run loop.
        tickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.updateElapsed(now: now)
            }
    }

    private func endTicking() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }

    private func updateElapsed(now: Date) {
        if let started = startedAt {
            elapsedSeconds = Self.seconds(between: started, and: now)
        } else {
            elapsedSeconds = accumulatedSeconds
        }
    }

    private static func seconds(between from: Date, and to: Date) -> Int {
        max(0, Int(to.timeIntervalSince(from).rounded()))
    }
}

// MARK: - Preview / Manual test hooks (DEBUG only)

#if DEBUG
extension VisitTimer {
    static func demoRunning() -> VisitTimer {
        let t = VisitTimer()
        t.setElapsed(seconds: 75, running: true) // 1m 15s and counting
        return t
    }
    static func demoStopped() -> VisitTimer {
        let t = VisitTimer()
        t.setElapsed(seconds: 3725, running: false) // 1h 2m 5s
        return t
    }
}
#endif
