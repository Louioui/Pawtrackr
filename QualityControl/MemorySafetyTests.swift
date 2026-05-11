import XCTest
import SwiftData
@testable import Pawtrackr

final class MemorySafetyTests: XCTestCase {

    @MainActor
    func testViewModelLifecycleDeallocation() async {
        // Test 1: DashboardViewModel
        await assertDeallocates {
            DashboardViewModel(dataStore: DataStoreService(inMemory: true), eventBus: GlobalEventBus())
        }
        
        // Test 2: CheckoutViewModel
        await assertDeallocates {
            let pet = Pet(name: "Test", species: .dog, gender: .male)
            return CheckoutViewModel(pet: pet, visit: nil, eventBus: GlobalEventBus())
        }
        
        // Test 3: InsightsViewModel
        await assertDeallocates {
            InsightsViewModel(dataStore: DataStoreService(inMemory: true), eventBus: GlobalEventBus())
        }
        
        // Test 4: ClientsViewModel
        await assertDeallocates {
            ClientsViewModel(modelContext: DataStoreService(inMemory: true).container.mainContext)
        }
    }

    private func assertDeallocates<T: AnyObject>(factory: () -> T, file: StaticString = #file, line: UInt = #line) async {
        var instance: T? = factory()
        weak var weakInstance = instance
        
        instance = nil
        
        // Give runloop a chance to clear
        try? await Task.sleep(for: .milliseconds(50))
        
        XCTAssertNil(weakInstance, "Object of type \(T.self) leaked memory", file: file, line: line)
    }
}
