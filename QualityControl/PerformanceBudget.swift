import Darwin

/// Measures an operation for a performance budget in CPU time, not wall time.
///
/// On CI the simulator clones run as separate processes on a few cores, so
/// wall time mostly measures how busy the other clones are: a dashboard
/// refresh that takes about 100 ms took 300 ms per run for several seconds
/// in a row there. The CPU time this process spends is what a regression in
/// our code changes, and other processes don't add to it.
///
/// Each run gets a fresh fixture from `setUp` (not measured), and the
/// fastest run is returned, so leftover background work from an earlier test
/// in the same process can only inflate some of the runs.
enum PerformanceBudget {
    static let defaultRuns = 5

    /// Returns the smallest process CPU time, in milliseconds, of `runs`
    /// calls of `operation`.
    @MainActor
    static func fastestCPUMilliseconds<Fixture>(
        runs: Int = defaultRuns,
        setUp: () throws -> Fixture,
        _ operation: (Fixture) async throws -> Void
    ) async rethrows -> Double {
        precondition(runs > 0)
        var fastest = UInt64.max
        for _ in 0..<runs {
            let fixture = try setUp()
            let start = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
            try await operation(fixture)
            fastest = min(fastest, clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - start)
        }
        return Double(fastest) / 1_000_000
    }
}
