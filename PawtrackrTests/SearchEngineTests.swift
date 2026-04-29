import XCTest
@testable import Pawtrackr

final class SearchEngineTests: XCTestCase {

    func testMatches_EmptyQuery_ReturnsTrue() {
        let fields: [String?] = ["Golden Retriever", "Max"]
        XCTAssertTrue(SearchEngine.matches("", in: fields))
        XCTAssertTrue(SearchEngine.matches("   ", in: fields))
    }

    func testMatches_CaseInsensitive() {
        let fields: [String?] = ["Golden Retriever", "Max"]
        XCTAssertTrue(SearchEngine.matches("GOLDEN", in: fields))
        XCTAssertTrue(SearchEngine.matches("max", in: fields))
    }

    func testMatches_DiacriticInsensitive() {
        let fields: [String?] = ["Béla", "San José"]
        XCTAssertTrue(SearchEngine.matches("bela", in: fields))
        XCTAssertTrue(SearchEngine.matches("jose", in: fields))
    }

    func testMatches_NoMatch_ReturnsFalse() {
        let fields: [String?] = ["Golden Retriever", "Max"]
        XCTAssertFalse(SearchEngine.matches("Poodle", in: fields))
    }

    func testFilter_ReturnsCorrectItems() {
        let items = ["Apple", "Banana", "Cherry", "Date"]
        let filtered = SearchEngine.filter(items, query: "a") { [$0] }
        XCTAssertEqual(filtered.count, 3) // Apple, Banana, Date
        XCTAssertTrue(filtered.contains("Apple"))
        XCTAssertTrue(filtered.contains("Banana"))
        XCTAssertTrue(filtered.contains("Date"))
    }
}
