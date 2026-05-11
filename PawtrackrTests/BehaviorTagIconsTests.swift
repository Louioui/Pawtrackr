import XCTest
@testable import Pawtrackr

final class BehaviorTagIconsTests: XCTestCase {
    
    func testDisplay_ReturnsCorrectEmojiAndLabel() {
        let calm = BehaviorTagIcons.display(for: "Calm")
        XCTAssertEqual(calm.emoji, "🧘")
        XCTAssertEqual(calm.label, "Calm")
        
        let aggressive = BehaviorTagIcons.display(for: "aggressive")
        XCTAssertEqual(aggressive.emoji, "🛑")
        XCTAssertEqual(aggressive.label, "Aggressive")
        
        let puppy = BehaviorTagIcons.display(for: " Puppy ")
        XCTAssertEqual(puppy.emoji, "🐶")
        XCTAssertEqual(puppy.label, "Puppy / Young")
    }
    
    func testDisplay_Fallback_ReturnsTitleCase() {
        let unknown = BehaviorTagIcons.display(for: "likes belly rubs")
        XCTAssertNil(unknown.emoji)
        XCTAssertEqual(unknown.label, "Likes Belly Rubs")
    }
}
