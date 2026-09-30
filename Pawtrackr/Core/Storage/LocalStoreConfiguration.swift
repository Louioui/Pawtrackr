import Foundation
import SwiftData

/// Builds the local configuration shared by production and persistence tests.
enum LocalStoreConfiguration {
    /// Preserves the named store location while disabling remote persistence.
    static func make(
        schema: Schema,
        isStoredInMemoryOnly: Bool = false,
        url: URL? = nil
    ) -> ModelConfiguration {
        let name = isStoredInMemoryOnly ? "PawtrackrTests" : "Pawtrackr"
        if let url {
            return ModelConfiguration(name, schema: schema, url: url, cloudKitDatabase: .none)
        }
        return ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
    }
}
