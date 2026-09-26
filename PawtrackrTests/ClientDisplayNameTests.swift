import XCTest
@testable import Pawtrackr

final class ClientDisplayNameTests: XCTestCase {
    func testDisplayNameUsesFirstNameFirstByDefault() {
        let client = Client(firstName: "Alien", lastName: "Cullen")

        XCTAssertEqual(client.displayName(), "Alien Cullen")
    }

    func testDisplayNameCanUseLastNameFirstForLastNameSort() {
        let client = Client(firstName: "Alien", lastName: "Cullen")

        XCTAssertEqual(client.displayName(lastNameFirst: true), "Cullen Alien")
    }

    func testDisplayNameSkipsMissingNameParts() {
        let client = Client(firstName: "Alien", lastName: "")

        XCTAssertEqual(client.displayName(lastNameFirst: true), "Alien")
    }
}
