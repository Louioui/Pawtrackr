import Foundation
import OSLog

/// A simple remote configuration service for feature flagging and version gating.
final class RemoteConfigService {
    static let shared = RemoteConfigService()
    
    private let configURL = URL(string: "https://your-server.com/pawtrackr-config.json")!
    
    @Published private(set) var isPredictiveSchedulingEnabled: Bool = true
    @Published private(set) var minimumSupportedVersion: String = "1.0.0"
    
    private init() {}
    
    func fetchConfig() async {
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
