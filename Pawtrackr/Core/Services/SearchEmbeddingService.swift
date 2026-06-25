import Foundation

/// Service for generating embeddings from pet notes and behavior tags to support semantic search.
final class SearchEmbeddingService {
    static let shared = SearchEmbeddingService()

    private static let dimensions = 128

    /// Generates a stable local text vector on a utility-priority background task.
    func generateEmbedding(for text: String) async throws -> [Float] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return Self.makeDeterministicEmbedding(for: text)
        }.value
    }

    /// Converts text into a normalized hashing-vector embedding suitable for local ranking fallback.
    private static func makeDeterministicEmbedding(for text: String) -> [Float] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else {
            return Array(repeating: 0, count: dimensions)
        }

        var vector = Array(repeating: Float.zero, count: dimensions)
        for token in tokens {
            let hash = stableHash(token)
            let index = Int(hash % UInt64(dimensions))
            let sign: Float = ((hash >> 8) & 1) == 0 ? 1 : -1
            vector[index] += sign
        }

        normalize(&vector)
        return vector
    }

    /// Produces locale-stable alphanumeric tokens while preserving words that matter for pet notes.
    private static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// FNV-1a gives deterministic buckets across launches, unlike Swift's randomized `hashValue`.
    private static func stableHash(_ token: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    /// Scales non-empty vectors to unit length so score magnitudes remain bounded and finite.
    private static func normalize(_ vector: inout [Float]) {
        let magnitudeSquared = vector.reduce(Double.zero) { partial, value in
            partial + Double(value * value)
        }
        guard magnitudeSquared > 0 else { return }

        let magnitude = Float(sqrt(magnitudeSquared))
        guard magnitude.isFinite, magnitude > 0 else { return }
        for index in vector.indices {
            vector[index] /= magnitude
        }
    }
}
