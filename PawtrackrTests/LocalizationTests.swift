import XCTest
@testable import Pawtrackr

final class LocalizationTests: XCTestCase {
    
    func testKeyStrings_AreLocalizedInEnglish() {
        // These keys should match the values in Localizable.strings (en)
        XCTAssertEqual(NSLocalizedString("clients.tab", comment: ""), "Clients")
        XCTAssertEqual(NSLocalizedString("insights.tab", comment: ""), "Insights")
        XCTAssertEqual(NSLocalizedString("settings.tab", comment: ""), "Settings")
        
        XCTAssertEqual(NSLocalizedString("common.save", comment: ""), "Save")
        XCTAssertEqual(NSLocalizedString("common.cancel", comment: ""), "Cancel")
        XCTAssertEqual(NSLocalizedString("common.done", comment: ""), "Done")
        
        XCTAssertEqual(NSLocalizedString("species.dog", comment: ""), "Dog")
        XCTAssertEqual(NSLocalizedString("species.cat", comment: ""), "Cat")
        
        XCTAssertEqual(NSLocalizedString("gender.male", comment: ""), "Male")
        XCTAssertEqual(NSLocalizedString("gender.female", comment: ""), "Female")
    }
    
    func testCheckoutStrings_ArePresent() {
        XCTAssertEqual(NSLocalizedString("checkout.complete_title", comment: ""), "Checkout Complete!")
        XCTAssertTrue(NSLocalizedString("checkout.processing", comment: "").contains("Processing"))
    }
}
