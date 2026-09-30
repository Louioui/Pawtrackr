import Foundation

/// Times an operation for a wall-clock performance budget.
///
/// A single timed run fails whenever the simulator stalls, and the CI runner
/// stalls often: it runs several simulator clones at once, and the dashboard
/// refresh that normally takes a few milliseconds once took over two seconds
/// there. Each run gets a fresh fixture from `setUp` (not timed), and the
/// fastest run is compared to the budget. A real regression slows every run;
/// a stall on a loaded runner slows only some of them.
@MainActor
enum PerformanceBudget {
    static let defaultRuns = 5

    /// Returns the fastest of `runs` timed calls of `operation`, in milliseconds.
    static func fastestMilliseconds<Fixture>(
        runs: Int = defaultRuns,
        setUp: () throws -> Fixture,
        _ operation: (Fixture) async throws -> Void
    ) async rethrows -> Double {
        precondition(runs > 0)
        let clock = ContinuousClock()
        var fastest: Duration?
        for _ in 0..<runs {
            let fixture = try setUp()
            let start = clock.now
            try await operation(fixture)
            let elapsed = clock.now - start
            fastest = fastest.map { min($0, elapsed) } ?? elapsed
        }
        let parts = fastest!.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
