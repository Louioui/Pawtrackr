import XCTest
import SwiftData
@testable import Pawtrackr

final class MessageTemplateTests: XCTestCase {
    
    @MainActor
    func testProcessedContent_ReplacesPlaceholders() {
        let owner = Client(firstName: "John", lastName: "Doe")
        let pet = Pet(name: "Buster", species: .dog)
        pet.owner = owner
        
        let visit = Visit(pet: pet, startedAt: Calendar.current.date(from: DateComponents(hour: 14, minute: 0))!)
        visit.total = Decimal(string: "65.50")!
        
        let template = MessageTemplate(title: "Test", content: "Hi [OwnerName], [PetName] is ready! Total: [Total] at [Time].")
        
        let processed = template.processedContent(pet: pet, visit: visit)
        
        XCTAssertTrue(processed.contains("John"))
        XCTAssertTrue(processed.contains("Buster"))
        XCTAssertTrue(processed.contains("$65.50"))
        XCTAssertTrue(processed.contains("2:00"))
    }
    
    @MainActor
    func testProcessedContent_HandlesMissingDataGracefully() {
        let template = MessageTemplate(title: "Test", content: "Hi [OwnerName], [PetName] is ready!")
        
        // No owner, no visit
        let pet = Pet(name: "Buster", species: .dog)
        let processed = template.processedContent(pet: pet, visit: nil)
        
        XCTAssertEqual(processed, "Hi [OwnerName], Buster is ready!")
    }
}
