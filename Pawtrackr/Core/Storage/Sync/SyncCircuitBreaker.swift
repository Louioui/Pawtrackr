//
//  SyncCircuitBreaker.swift
//  Pawtrackr
//
//  Backoff for the manual "Check iCloud" action after CloudKit failures.
//

import Foundation
import Network
import Observation
import OSLog

struct NetworkCondition: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case unknown
        case online
        case offline
        case requiresConnection
    }

    var status: Status
    var isExpensive: Bool
    var isConstrained: Bool

    var isOnline: Bool { status == .online }
    var slowsBackgroundWork: Bool { isExpensive || isConstrained || ProcessInfo.processInfo.isLowPowerModeEnabled }

    static let unknown = NetworkCondition(status: .unknown, isExpensive: false, isConstrained: false)
}

@Observable
final class NetworkConditionMonitor {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "Pawtrackr.NetworkConditionMonitor", qos: .utility)
    private var didStart = false

    private(set) var condition: NetworkCondition = .unknown

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    func start(onChange: @escaping @Sendable (NetworkCondition) -> Void) {
        guard !didStart else { return }
        didStart = true
        monitor.pathUpdateHandler = { [weak self] path in
            let next = NetworkCondition(path: path)
            Task { @MainActor in
                self?.condition = next
                onChange(next)
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

extension NetworkCondition {
    init(path: NWPath) {
        switch path.status {
        case .satisfied:
            status = .online
        case .unsatisfied:
            status = .offline
        case .requiresConnection:
            status = .requiresConnection
        @unknown default:
            status = .unknown
        }
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
    }
}

/// Backs off the groomer's manual "Check iCloud" after CloudKit reports a
/// failure. That is all it governs: NSPersistentCloudKitContainer schedules
/// its own uploads and retries and can't be paused, so heartbeats, the
/// offline buffer and the account re-checks run regardless, and nothing here
/// changes what the status says. Network drops don't open it (a check while
/// offline just re-reads the account); coming back online lets a check
/// through straight away.
struct SyncCircuitBreaker: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case closed
        /// Manual checks wait until `until`.
        case open(until: Date, failures: Int)
        /// One check is allowed through; the next CloudKit result decides.
        case halfOpen(probeStartedAt: Date, failures: Int)

        var isOpen: Bool {
            if case .open = self { return true }
            return false
        }
    }

    struct Configuration: Equatable, Sendable {
        var baseDelay: TimeInterval = 30
        var multiplier: Double = 2
        /// A groomer who just freed iCloud storage shouldn't wait half an hour
        /// to see whether it worked.
        var maximumDelay: TimeInterval = 5 * 60
        var constrainedMultiplier: Double = 2
    }

    private(set) var state: State = .closed
    private(set) var consecutiveFailures = 0
    var configuration = Configuration()

    /// When a manual check is allowed again, or nil if it is allowed now.
    func manualCheckAvailableAt(now: Date = Date()) -> Date? {
        guard case .open(let until, _) = state, now < until else { return nil }
        return until
    }

    /// Conditions changed, so the last failure says less about the next try.
    mutating func observeNetwork(_ condition: NetworkCondition, now: Date = Date()) {
        guard condition.isOnline, state.isOpen else { return }
        state = .halfOpen(probeStartedAt: now, failures: consecutiveFailures)
    }

    mutating func recordFailure(now: Date = Date(), constrained: Bool = false) {
        consecutiveFailures = min(consecutiveFailures + 1, 10)
        var delay = configuration.baseDelay * pow(configuration.multiplier, Double(max(0, consecutiveFailures - 1)))
        if constrained {
            delay *= configuration.constrainedMultiplier
        }
        delay = min(delay, configuration.maximumDelay)
        state = .open(until: now.addingTimeInterval(delay), failures: consecutiveFailures)
    }

    mutating func recordSuccess() {
        consecutiveFailures = 0
        state = .closed
    }

    /// True when a manual check may run now; moves an expired `.open` to
    /// `.halfOpen`.
    mutating func beginProbeIfAllowed(now: Date = Date()) -> Bool {
        switch state {
        case .closed, .halfOpen:
            return true
        case .open(let until, _):
            guard now >= until else { return false }
            state = .halfOpen(probeStartedAt: now, failures: consecutiveFailures)
            return true
        }
    }
}

/// What a "Check iCloud" button can do right now. Never a zero-second wait:
/// a pause that has run out is `.available`.
enum ManualCheckAvailability: Equatable, Sendable {
    case available
    /// The 30-second cooldown after the last manual check.
    case coolingDown(seconds: Int)
    /// Backing off after an iCloud error.
    case pausedAfterError(until: Date)

    static func resolve(cooldownSeconds: Int, pausedUntil: Date?, now: Date) -> ManualCheckAvailability {
        if cooldownSeconds > 0 {
            return .coolingDown(seconds: cooldownSeconds)
        }
        if let pausedUntil, now < pausedUntil {
            return .pausedAfterError(until: pausedUntil)
        }
        return .available
    }

    var isAvailable: Bool { self == .available }

    /// The button title. "Check iCloud" when a check can run.
    var buttonTitle: String {
        switch self {
        case .available:
            return AppLocalization.localized("cloudkit.action.check_status", value: "Check iCloud")
        case .coolingDown(let seconds):
            return String(
                format: AppLocalization.localized("cloudkit.action.check_status_wait_fmt", value: "Check again in %ds"),
                seconds
            )
        case .pausedAfterError(let until):
            return String(
                format: AppLocalization.localized(
                    "cloudkit.action.check_paused_fmt",
                    value: "Paused after an iCloud error. Check again at %@"
                ),
                until.formatted(date: .omitted, time: .shortened)
            )
        }
    }
}
