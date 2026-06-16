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

    func testSpanishBundlesContainEverySwiftLocalizationKey() throws {
        let repositoryRoot = try Self.repositoryRoot()
        let sourceRoot = repositoryRoot.appendingPathComponent("Pawtrackr")
        let localizationRoot = sourceRoot.appendingPathComponent("App/Navigation/Coordinators/Localizable")
        let keysUsedInSwift = try Self.swiftLocalizationKeys(under: sourceRoot)

        for locale in ["es", "es-419"] {
            let stringsURL = localizationRoot
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
            let localizedKeys = try Self.keys(inStringsFile: stringsURL)
            let missing = keysUsedInSwift.subtracting(localizedKeys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(locale).lproj is missing localization keys: \(missing.joined(separator: ", "))")
        }
    }

    private static func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
        while candidate.path != "/" {
            let project = candidate.appendingPathComponent("Pawtrackr.xcodeproj")
            if FileManager.default.fileExists(atPath: project.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate Pawtrackr repository root.")
    }

    private static func swiftLocalizationKeys(under sourceRoot: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        let patterns = [
            #"(?:NSLocalizedString|LocalizedStringKey|localized|settingsLocalized|devicesLocalized)\(\s*"([A-Za-z_][A-Za-z0-9_.-]*)""#,
            #"(?:Text|TextField|SecureField|Label|Button|Picker|Toggle|DatePicker|ContentUnavailableView|navigationTitle)\(\s*"([A-Za-z_][A-Za-z0-9_.-]*\.[A-Za-z0-9_.-]*)""#
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys = Set<String>()

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for regex in regexes {
                for match in regex.matches(in: source, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                    keys.insert(String(source[keyRange]))
                }
            }
        }

        return keys
    }

    private static func keys(inStringsFile url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: String] else {
            XCTFail("Could not parse \(url.path) as a strings table.")
            return []
        }
        return Set(dictionary.keys)
    }
}
