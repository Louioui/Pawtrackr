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

    func testMissingFirstNameShowsLastNameInBothOrders() {
        let client = Client(firstName: "", lastName: "Cullen")

        XCTAssertEqual(client.displayName(), "Cullen")
        XCTAssertEqual(client.displayName(lastNameFirst: true), "Cullen")
    }

    func testMissingLastNameShowsFirstNameInBothOrders() {
        let client = Client(firstName: "Alien", lastName: "")

        XCTAssertEqual(client.displayName(), "Alien")
        XCTAssertEqual(client.displayName(lastNameFirst: true), "Alien")
    }

    func testWhitespaceOnlyNamesAreTreatedAsMissing() {
        // Stored names can carry whitespace from older imports; set directly
        // so the init's own trimming doesn't hide it.
        let client = Client(firstName: "", lastName: "")
        client.firstName = "   "
        client.lastName = "\t "

        XCTAssertEqual(client.displayName(), "")
        XCTAssertEqual(client.displayName(lastNameFirst: true), "")

        client.lastName = "  Cullen "
        XCTAssertEqual(client.displayName(), "Cullen")
        XCTAssertEqual(client.displayName(lastNameFirst: true), "Cullen")
    }

    func testBothNamesAreTrimmedAndSpaceJoinedInEitherOrder() {
        let client = Client(firstName: "", lastName: "")
        client.firstName = " Alien "
        client.lastName = " Cullen"

        XCTAssertEqual(client.displayName(), "Alien Cullen")
        XCTAssertEqual(client.displayName(lastNameFirst: true), "Cullen Alien")
    }

    @MainActor
    func testClientRowFollowsTheLastNameSortOnlyWhenAsked() {
        let client = Client(firstName: "Alien", lastName: "Cullen")

        XCTAssertFalse(ClientRow(client: client, inProgress: false).displaysLastNameFirst, "Recent Clients and other unsorted rows stay first-name-first.")
        XCTAssertTrue(ClientRow(client: client, inProgress: false, displaysLastNameFirst: true).displaysLastNameFirst)
    }
}
