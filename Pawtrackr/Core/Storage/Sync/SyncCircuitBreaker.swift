//
//  SyncCircuitBreaker.swift
//  Pawtrackr
//
//  Battery-aware app-level governor around manual CloudKit probes.
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

struct SyncCircuitBreaker: Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case uploadStalled
        case networkUnavailable
        case cloudKitFailure
        case constrainedNetwork
        case lowPower

        var displayText: String {
            switch self {
            case .uploadStalled:
                return "Cloud uploads are stalled, so Pawtrackr is protecting battery and staying local-first."
            case .networkUnavailable:
                return "Network is unavailable. Changes stay safe on this device."
            case .cloudKitFailure:
                return "iCloud rejected the last sync attempt. Pawtrackr will retry with backoff."
            case .constrainedNetwork:
                return "Network is constrained or expensive. Pawtrackr is reducing background sync checks."
            case .lowPower:
                return "Low Power Mode is on, so Pawtrackr is reducing background sync checks."
            }
        }
    }

    enum State: Equatable, Sendable {
        case closed
        case open(until: Date, reason: Reason, failures: Int)
        case halfOpen(probeStartedAt: Date, reason: Reason, failures: Int)

        var isOpen: Bool {
            if case .open = self { return true }
            return false
        }

        var nextProbeDate: Date? {
            if case .open(let until, _, _) = self { return until }
            return nil
        }

        var reason: Reason? {
            switch self {
            case .closed:
                return nil
            case .open(_, let reason, _), .halfOpen(_, let reason, _):
                return reason
            }
        }
    }

    struct Configuration: Equatable, Sendable {
        var baseDelay: TimeInterval = 30
        var multiplier: Double = 2
        var maximumDelay: TimeInterval = 30 * 60
        var constrainedMultiplier: Double = 2
        var jitterRatio: Double = 0.15
    }

    private(set) var state: State = .closed
    private(set) var consecutiveFailures = 0
    var configuration = Configuration()

    var allowsAggressiveWork: Bool {
        switch state {
        case .closed, .halfOpen:
            return true
        case .open:
            return false
        }
    }

    mutating func observeNetwork(_ condition: NetworkCondition, now: Date = Date()) {
        if !condition.isOnline {
            open(reason: .networkUnavailable, now: now, constrained: condition.slowsBackgroundWork)
        } else if case .open(let until, _, _) = state, now >= until {
            state = .halfOpen(probeStartedAt: now, reason: state.reason ?? .cloudKitFailure, failures: consecutiveFailures)
        }
    }

    mutating func recordPendingStall(now: Date = Date(), constrained: Bool = false) {
        open(reason: constrained ? .constrainedNetwork : .uploadStalled, now: now, constrained: constrained)
    }

    mutating func recordFailure(reason: Reason = .cloudKitFailure, now: Date = Date(), constrained: Bool = false) {
        open(reason: reason, now: now, constrained: constrained)
    }

    mutating func recordSuccess() {
        consecutiveFailures = 0
        state = .closed
    }

    mutating func beginProbeIfAllowed(now: Date = Date()) -> Bool {
        switch state {
        case .closed:
            return true
        case .halfOpen:
            return true
        case .open(let until, let reason, _):
            guard now >= until else { return false }
            state = .halfOpen(probeStartedAt: now, reason: reason, failures: consecutiveFailures)
            return true
        }
    }

    private mutating func open(reason: Reason, now: Date, constrained: Bool) {
        consecutiveFailures = min(consecutiveFailures + 1, 10)
        var delay = configuration.baseDelay * pow(configuration.multiplier, Double(max(0, consecutiveFailures - 1)))
        delay = min(delay, configuration.maximumDelay)
        if constrained {
            delay = min(delay * configuration.constrainedMultiplier, configuration.maximumDelay)
        }
        let jitter = delay * configuration.jitterRatio
        let deterministicJitter = Double(abs(reason.rawValue.hashValue % 1_000)) / 1_000.0 * jitter
        state = .open(until: now.addingTimeInterval(delay + deterministicJitter), reason: reason, failures: consecutiveFailures)
    }
}
