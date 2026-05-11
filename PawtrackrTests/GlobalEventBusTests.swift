import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class GlobalEventBusTests: XCTestCase {
    
    func testPublishAndSubscribe_DeliversEvents() async {
        let bus = GlobalEventBus()
        let expectation = XCTestExpectation(description: "Event received")
        
        let task = Task {
            for await event in bus.stream {
                if case .refreshRequired = event {
                    expectation.fulfill()
                }
            }
        }
        
        // Give the stream a moment to start
        try? await Task.sleep(for: .milliseconds(100))
        
        bus.publish(.refreshRequired)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        task.cancel()
    }
    
    func testCheckoutCompletedEvent_CarriesCorrectData() async {
        let bus = GlobalEventBus()
        let expectation = XCTestExpectation(description: "Checkout event received")
        let testID = PersistentIdentifier.demoClient // Using a demo ID for test
        let testTotal = Decimal(75.0)
        
        let task = Task {
            for await event in bus.stream {
                if case .checkoutCompleted(let context) = event {
                    XCTAssertEqual(context.total, testTotal)
                    expectation.fulfill()
                }
            }
        }
        
        try? await Task.sleep(for: .milliseconds(100))
        
        let context = CheckoutCompletionContext(
            visitID: testID,
            petID: nil,
            clientID: nil,
            endedAt: Date(),
            total: testTotal
        )
        bus.publish(.checkoutCompleted(context))
        
        await fulfillment(of: [expectation], timeout: 2.0)
        task.cancel()
    }
}

// Helper for PersistentIdentifier in tests
extension PersistentIdentifier {
    @MainActor
    static var demoClient: PersistentIdentifier {
        // This is a hack for testing purposes to create a 'valid-looking' ID
        // In real SwiftData tests, we'd fetch one from a container.
        let schema = Schema([Client.self])
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let client = Client(firstName: "Test", lastName: "Test")
            container.mainContext.insert(client)
            return client.persistentModelID
        } catch {
            preconditionFailure("Failed to create demo PersistentIdentifier: \(error.localizedDescription)")
        }
    }
}
