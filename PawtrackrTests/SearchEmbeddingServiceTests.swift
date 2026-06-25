import XCTest
@testable import Pawtrackr

final class SearchEmbeddingServiceTests: XCTestCase {

    func testGenerateEmbedding_EmptyTextReturnsFiniteZeroVector() async throws {
        let embedding = try await SearchEmbeddingService().generateEmbedding(for: "   ")

        XCTAssertEqual(embedding.count, 128)
        XCTAssertTrue(embedding.allSatisfy(\.isFinite))
        XCTAssertTrue(embedding.allSatisfy { $0 == 0 })
    }

    func testGenerateEmbedding_TextReturnsStableNonZeroVector() async throws {
        let first = try await SearchEmbeddingService().generateEmbedding(for: "Milo snapped during nail trim")
        let second = try await SearchEmbeddingService().generateEmbedding(for: "Milo snapped during nail trim")

        XCTAssertEqual(first.count, 128)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(first.reduce(Float.zero) { $0 + abs($1) }, 0)
    }

    func testGenerateEmbedding_DistinctNotesProduceDistinctVectors() async throws {
        let hazardNote = try await SearchEmbeddingService().generateEmbedding(for: "snapped growled bite risk")
        let calmNote = try await SearchEmbeddingService().generateEmbedding(for: "calm friendly loves bath")

        XCTAssertNotEqual(hazardNote, calmNote)
    }
}
