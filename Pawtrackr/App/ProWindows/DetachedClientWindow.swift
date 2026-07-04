import SwiftData
import SwiftUI
import OSLog

enum DetachedClientWindowMode: String, Codable, Hashable, Sendable {
    case detail
    case loyalty
}

struct DetachedClientWindowRoute: Codable, Hashable, Sendable {
    let clientUUID: UUID
    let mode: DetachedClientWindowMode
}

@MainActor
struct DetachedClientWindow: View {
    private static let logger = Logger(subsystem: "com.pawtrackr", category: "DetachedClientWindow")

    @Environment(\.modelContext) private var modelContext
    @Namespace private var namespace

    let route: DetachedClientWindowRoute

    var body: some View {
        NavigationStack {
            if let client {
                switch route.mode {
                case .detail:
                    ClientDetailView(client: client, namespace: namespace)
                case .loyalty:
                    ClientLoyaltyView(client: client)
                }
            } else {
                ContentUnavailableView(
                    "Client Unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("This client was deleted or is not available on this device yet.")
                )
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var client: Client? {
        var descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { client in
                client.uuid == route.clientUUID
            }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Self.logger.error("Failed to fetch detached client window route: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
