import Foundation
import OSLog

/// A simple remote configuration service for feature flagging and version gating.
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    /// Set this to the live config URL once one exists. While it's nil, fetchConfig
    /// is a no-op — the previous placeholder ("https://your-server.com/...") returned
    /// an HTML 404 body that JSONDecoder couldn't parse, which spammed an error log
    /// on every launch and hid genuine networking issues.
    private let configURL: URL? = nil

    @Published private(set) var isPredictiveSchedulingEnabled: Bool = true
    @Published private(set) var minimumSupportedVersion: String = "1.0.0"

    private init() {}

    func fetchConfig() async {
        guard let configURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: configURL)
            let config = try JSONDecoder().decode(RemoteConfig.self, from: data)

            await MainActor.run {
                self.isPredictiveSchedulingEnabled = config.isPredictiveSchedulingEnabled
                self.minimumSupportedVersion = config.minimumSupportedVersion
            }
        } catch {
            Logger.performance.error("Failed to fetch remote config: \(error.localizedDescription)")
        }
    }
}

struct RemoteConfig: Codable {
    let isPredictiveSchedulingEnabled: Bool
    let minimumSupportedVersion: String
}
