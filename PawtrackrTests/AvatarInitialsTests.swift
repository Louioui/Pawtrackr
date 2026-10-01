//
//  AvatarInitialsTests.swift
//  PawtrackrTests
//
//  `IconCircle.makeInitials` against names that broke or blanked the
//  avatar: invisible characters, Zalgo marks, complex emoji, letters whose
//  uppercase is longer than one letter, and the poisoned stress book.
//

import XCTest
@testable import Pawtrackr

@MainActor
final class AvatarInitialsTests: XCTestCase {
    private func initials(_ name: String?) -> String? {
        IconCircle.makeInitials(from: name)
    }

    func testOrdinaryNames() {
        XCTAssertEqual(initials("Jane Doe"), "JD")
        XCTAssertEqual(initials("jane doe"), "JD")
        XCTAssertEqual(initials("Jane"), "J")
        XCTAssertEqual(initials("Jane Q Doe"), "JQ", "Only the first two words.")
        XCTAssertEqual(initials("  Jane\t\nDoe  "), "JD")
        XCTAssertEqual(initials("Client 9"), "C9")
    }

    func testNothingVisibleMeansNoInitials() {
        for name in [nil, "", " ", "\n\t", "\u{00A0}\u{2003}\u{3000}",
                     "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{2060}\u{00AD}",
                     "\u{200E}\u{200F}", "\u{3164}", "\u{115F}", "\u{202E}", "%_% --"] as [String?] {
            XCTAssertNil(initials(name), "\(String(describing: name?.unicodeScalars.map { $0.value }))")
        }
    }

    func testInvisibleCharactersAreSkippedNotDrawn() {
        XCTAssertEqual(initials("\u{200B}Zero Width"), "ZW")
        XCTAssertEqual(initials("\u{202E}gnp.exe Override"), "GO")
        XCTAssertEqual(initials("Bell\u{0007} Ringer"), "BR")
        XCTAssertEqual(initials("Ann\u{200D}a"), "A")
        XCTAssertEqual(initials("\"Quoted\" Name"), "QN")
    }

    func testEmojiStayWhole() {
        XCTAssertEqual(initials("👨‍👩‍👧‍👦"), "👨‍👩‍👧‍👦")
        XCTAssertEqual(initials("👨‍👩‍👧‍👦")?.count, 1)
        XCTAssertEqual(initials("Dog 🐶 Mom"), "D🐶")
        XCTAssertEqual(initials("👩🏽‍⚕️ Doctor"), "👩🏽‍⚕️D")
        XCTAssertEqual(initials("🏳️‍🌈"), "🏳️‍🌈")
        XCTAssertEqual(initials("🇺🇸🇲🇽"), "🇺🇸")
    }

    func testZalgoKeepsOnlyTheBaseLetter() {
        let marks = (0x0300...0x031F).compactMap(Unicode.Scalar.init).map(String.init).joined()
        XCTAssertEqual(initials("Z" + marks + "algo T" + marks + "ext"), "ZT")
        XCTAssertEqual(initials("A" + String(repeating: "\u{0308}", count: 500)), "A")
    }

    func testComposedAccentsSurvive() {
        XCTAssertEqual(initials("E\u{301}lise"), "É", "A decomposed accent composes back.")
        XCTAssertEqual(initials("élise"), "É")
        XCTAssertEqual(initials("İsmail"), "İ")
        XCTAssertEqual(initials("ıpek"), "I")
    }

    func testUppercaseLongerThanOneLetterIsNotUsed() {
        XCTAssertEqual(initials("ß"), "ß")
        XCTAssertEqual(initials("ﬃ"), "ﬃ")
    }

    func testOtherScripts() {
        XCTAssertEqual(initials("محمد Lee"), "مL")
        XCTAssertEqual(initials("山田 太郎"), "山太")
        XCTAssertEqual(initials("김 민준"), "김민")
        XCTAssertEqual(initials("Владимир Иванов"), "ВИ")
    }

    func testHugeNameIsCheap() {
        let name = String(repeating: "A", count: 10_000) + " " + String(repeating: "🐶", count: 2_500)
        measure {
            XCTAssertEqual(initials(name), "A🐶")
        }
    }

    /// Whatever the name, at most two initials, and each one is a single
    /// scalar or an emoji: never an invisible character or a mark stack.
    func testEveryStressAndPoisonedNameGivesDrawableInitials() {
        let specs = ClientStressDataset.makeSpecs(count: 600) + ClientStressDataset.poisonedSpecs()
        for spec in specs {
            for name in [spec.firstName + " " + spec.lastName, spec.lastName, spec.firstName] {
                guard let result = initials(name) else { continue }
                XCTAssertLessThanOrEqual(result.count, 2, name.debugDescription)
                for character in result {
                    let scalars = character.unicodeScalars
                    XCTAssertTrue(
                        scalars.count == 1 || scalars.contains { $0.properties.isEmoji },
                        "\(name.debugDescription) gave \(scalars.map { String($0.value, radix: 16) })"
                    )
                    XCTAssertFalse(scalars.allSatisfy { $0.properties.isDefaultIgnorableCodePoint }, name.debugDescription)
                }
            }
        }
    }
}
