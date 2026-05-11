import XCTest
import SwiftData
@testable import Pawtrackr

/// A specialized base class for SwiftData unit tests.
/// Handles automatic container cleanup and provides helper methods for data state.
class XCTDataTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = container.mainContext
        } catch {
            XCTFail("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }
    
    /// Snapshots the current count of a model type.
    func assertCount<T: PersistentModel>(_ type: T.Type, equals expected: Int, file: StaticString = #file, line: UInt = #line) {
        let count = (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
        XCTAssertEqual(count, expected, "Count of \(T.self) does not match.", file: file, line: line)
    }
}
