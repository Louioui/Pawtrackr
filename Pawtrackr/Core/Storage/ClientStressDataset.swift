//
//  ClientStressDataset.swift
//  Pawtrackr
//
//  A large, deterministic, deliberately hostile client book for stress tests
//  of the client list: long, empty, whitespace-only, accented, decomposed,
//  right-to-left, CJK, emoji and injection-looking names; valid, formatted,
//  international and garbage phone numbers; exact duplicate names; ties on
//  every sort key. DEBUG only. Unit tests seed it into an in-memory container,
//  and a UI-test launch with PAWTRACKR_SCENARIO=heavy_load seeds it into the
//  UI-test store (always in memory), so it never reaches a real salon's data.
//

#if DEBUG
import Foundation
import SwiftData

enum ClientStressDataset {
    /// Seeded once per book with a unique name, so a UI test can search for it
    /// and count its rows.
    static let sentinelFirstName = "Stress"
    static let sentinelLastName = "Aaaa Sentinel"

    struct Spec: Sendable, Equatable {
        var firstName: String
        var lastName: String
        var phone: String?
        var email: String?
        var petNames: [String]
        /// True: written straight to the stored properties, the way an import
        /// or a sync from an older build can leave them (untrimmed, longer than
        /// the form allows, phone not normalized). False: through `Client.init`
        /// and the setters, like the New Client form.
        var bypassesSetters: Bool
        var createdAt: Date
        var lastVisitDate: Date?
    }

    // MARK: - Edge-case pools

    static let edgeFirstNames: [String] = [
        "", " ", "   ", "\n", "\t Ana \t",
        "José", "Jose\u{301}",                       // precomposed vs decomposed é
        "Zoë", "Ægir", "Øyvind", "Łukasz", "Şebnem", "İsmail", "ı", "Strauß",
        "Renée", "Chloé", "François", "Nuño", "Björk",
        "محمد", "שרה", "山田", "김", "Владимир", "Αλέξανδρος", "अर्जुन", "สมชาย",
        "🐶", "Dog 🐶 Mom", "👩🏽‍⚕️", "\u{200B}Zero", "Ann\u{200D}a",
        "O'Brien", "Mary-Kate", "J.R.", "St. John", "D'Angelo", "Mc Donald",
        "<script>alert(1)</script>", "Robert'); DROP TABLE Client;--", "%_%", "\\", "\"Quoted\"",
        "lowercase", "UPPERCASE", "mIxEd", "Client 9", "Client 10", "Client 100",
        "a", "A", "Á", "Z", "z", "Ω",
        "n:fake", "p:555", "pet:Bella",              // look like search prefixes
    ]

    static let edgeLastNames: [String] = [
        "", " ", "\u{00A0}",                         // no-break space
        "de la Cruz", "De La Cruz", "van Houten", "Van Houten", "von Trapp", "d'Arc", "DEAN", "dean", "Delgado",
        "Müller", "Mueller", "Muller", "Ñúñez", "Nunez", "Ångström", "Ølgaard", "Œuvre",
        "García-Márquez", "O'Neil", "ONeil", "Smith-Jones", "Smith Jones",
        "Al-Fayed", "بن سلمان", "כהן", "田中", "이", "Иванов", "Παπαδόπουλος", "शर्मा",
        "🐾", "Paws 🐾", "Zzz", "zzz", "ZZZ", "Ẕ",
        "Lopez", "López", "LOPEZ", "Number 2", "Number 10", "Number 1",
        "Tab\tName", "Line\nBreak", "  Spaced  ", ";", "--", "NULL", "nil", "undefined",
    ]

    static let commonFirstNames = [
        "Maria", "James", "Sofia", "Liam", "Olivia", "Noah", "Emma", "Mateo", "Ava", "Lucas",
        "Isabella", "Ethan", "Mia", "Leo", "Camila", "Elijah", "Aria", "Daniel", "Luna", "Diego",
    ]

    static let commonLastNames = [
        "Smith", "Johnson", "Garcia", "Martinez", "Brown", "Lee", "Nguyen", "Patel", "Kim", "Lopez",
        "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Perez", "White",
    ]

    static let phonePool: [String?] = [
        nil, "", "   ",
        "+13125550123", "3125550123", "(312) 555-0123", "312.555.0123", "312-555-0123", "1 312 555 0123",
        "+1 (312) 555-0123 ext. 45", "312-555-0123 x45",
        "+44 20 7946 0958", "+52 55 1234 5678", "+34 600 12 34 56", "+81 3-1234-5678", "+91 98765 43210",
        "123", "0", "000-000-0000", "999999999999999999999999999999999999999",
        "abcdefg", "555-CALL-NOW", "phone: none", "📞 312 555 0123", "+", "++1312", "-1", "1e10",
        "٣١٢٥٥٥٠١٢٣",                               // Arabic-Indic digits
    ]

    static let petNamePool = [
        "Bella", "bella", "BELLA", "Max", "Luna", "Charlie", "Coco", "Milo", "Rocky", "Zoë",
        "", "  ", "Señor Bigotes", "Mr. Whiskers", "🐕", "ポチ", "Шарик", "Rex 2", "Rex 10", "Ab",
    ]

    // MARK: - Generation

    /// The same `seed` always gives the same book, so a failure reproduces.
    static func makeSpecs(count: Int = 600, seed: UInt64 = 0x5EED_C11E) -> [Spec] {
        var rng = SplitMix64(seed: seed)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var specs: [Spec] = []
        specs.reserveCapacity(count + 1)

        specs.append(Spec(
            firstName: sentinelFirstName,
            lastName: sentinelLastName,
            phone: "+13125559999",
            email: "sentinel@example.com",
            petNames: ["Sentinel Pup"],
            bypassesSetters: false,
            createdAt: base,
            lastVisitDate: nil
        ))

        for index in 0..<max(0, count - 1) {
            let bucket = index % 10
            var first: String
            var last: String
            var bypasses = rng.chance(0.3)

            switch bucket {
            case 0, 1:
                // 120 edge slots in a 600-client book: every edge first name
                // and last name is used, paired differently each time.
                let slot = index / 10 * 2 + bucket
                first = edgeFirstNames[slot % edgeFirstNames.count]
                last = edgeLastNames[(slot * 7 + 3) % edgeLastNames.count]
            case 2:
                // Exact duplicate names: ties the sort must break the same way every time.
                first = "Maria"
                last = "Lopez"
            case 3:
                // Longer than the form allows; only an import can store these.
                first = String(repeating: "Bartholomew", count: rng.int(in: 6...30))
                last = String(repeating: "Featherstonehaugh-", count: rng.int(in: 4...20))
                bypasses = true
            case 4:
                first = rng.pick(commonFirstNames).lowercased()
                last = rng.pick(commonLastNames).uppercased()
            default:
                first = rng.pick(commonFirstNames)
                last = rng.pick(commonLastNames)
            }

            let petCount = rng.int(in: 0...3)
            let pets = (0..<petCount).map { _ in rng.pick(petNamePool) }

            // Some share a creation instant and some a visit date, so those
            // sorts need their tiebreak too.
            let createdAt = rng.chance(0.2) ? base : base.addingTimeInterval(TimeInterval(index * 3_600))
            let lastVisit: Date? = rng.chance(0.4)
                ? nil
                : base.addingTimeInterval(TimeInterval(rng.int(in: 0...30) * 86_400))

            specs.append(Spec(
                firstName: first,
                lastName: last,
                phone: rng.pick(phonePool),
                email: rng.chance(0.5) ? "client\(index)@example.com" : (rng.chance(0.2) ? "not-an-email" : nil),
                petNames: pets,
                bypassesSetters: bypasses,
                createdAt: createdAt,
                lastVisitDate: lastVisit
            ))
        }
        return specs
    }

    // MARK: - Poison

    /// Names meant to break layout, text handling and the avatar rather than
    /// sorting: 10,000 characters, emoji only, Zalgo, invisible characters,
    /// bidi overrides and mixed right-to-left/left-to-right text. All go in
    /// the way an import would (no clamping or trimming).
    static func poisonedSpecs() -> [Spec] {
        let zalgoMarks = (0x0300...0x036F).compactMap(Unicode.Scalar.init).map(String.init)
        func zalgo(_ text: String, marks: Int) -> String {
            text.map { character in
                String(character) + (0..<marks).map { zalgoMarks[($0 * 7 + Int(character.asciiValue ?? 0)) % zalgoMarks.count] }.joined()
            }.joined()
        }

        let names: [(String, String)] = [
            (String(repeating: "A", count: 10_000), "Long"),
            ("Long", String(repeating: "Wolfeschlegelsteinhausenbergerdorff ", count: 280)),
            (String(repeating: "محمد Lee ", count: 1_200), String(repeating: "🐶", count: 2_500)),
            ("🐶🐱🐭", "🦊🐻🐼"),
            ("👨‍👩‍👧‍👦", ""),
            ("🏳️‍🌈", "🇺🇸🇲🇽"),
            ("👩🏽‍⚕️", "9️⃣"),
            (zalgo("Zalgo", marks: 30), zalgo("Text", marks: 30)),
            ("Ä" + String(repeating: "\u{0308}", count: 500), "Umlaut"),
            ("\u{200B}", "\u{200C}"),                    // zero-width space / non-joiner
            ("\u{200D}", "\u{FEFF}"),                    // zero-width joiner / BOM
            ("\u{3164}", "\u{115F}"),                    // Hangul fillers
            ("\u{2060}\u{00AD}", "\u{200E}\u{200F}"),    // word joiner + soft hyphen / LRM + RLM
            (" \u{00A0}\u{2003}\u{3000} ", ""),           // Unicode spaces only
            ("\u{202E}gnp.exe", "Override"),             // right-to-left override
            ("Ali علي", "Smith סמית"),
            ("שלום John", "\u{2067}محمد\u{2069} Lee"),     // isolates
            ("Bell\u{0007}", "Escape\u{001B}[31m"),       // control characters
            ("Line\nBreak", "Carriage\r\nReturn"),
            ("ß", "ﬃ"),                                  // uppercase to more than one letter
        ]
        let base = Date(timeIntervalSince1970: 1_700_500_000)
        return names.enumerated().map { index, name in
            Spec(
                firstName: name.0,
                lastName: name.1,
                phone: index.isMultiple(of: 2) ? "\u{202E}0123 555 213" : String(repeating: "9", count: 500),
                email: nil,
                petNames: index.isMultiple(of: 3) ? [zalgo("Rex", marks: 12), String(repeating: "🐾", count: 300)] : [],
                bypassesSetters: true,
                createdAt: base.addingTimeInterval(TimeInterval(index)),
                lastVisitDate: nil
            )
        }
    }

    /// Inserts one client (and its pets) for `spec` without saving.
    @discardableResult
    static func insert(_ spec: Spec, into context: ModelContext) -> Client {
        let client: Client
        if spec.bypassesSetters {
            client = Client(firstName: "", lastName: "")
            client.firstName = spec.firstName
            client.lastName = spec.lastName
            client.phone = spec.phone
            client.email = spec.email
        } else {
            client = Client(firstName: spec.firstName, lastName: spec.lastName, phone: nil, email: spec.email)
            client.setPhone(spec.phone)
        }
        client.createdAt = spec.createdAt
        client.lastVisitDate = spec.lastVisitDate
        context.insert(client)

        for (index, name) in spec.petNames.enumerated() {
            let pet = Pet(name: name, species: index.isMultiple(of: 2) ? .dog : .cat, gender: index.isMultiple(of: 3) ? .female : .male)
            pet.owner = client
            context.insert(pet)
        }
        return client
    }

    /// Seeds `count` clients (the sentinel included), plus the poisoned ones
    /// when asked, and saves in batches.
    @discardableResult
    static func seed(
        into context: ModelContext,
        count: Int = 600,
        seed: UInt64 = 0x5EED_C11E,
        includingPoison: Bool = false,
        batchSize: Int = 100
    ) throws -> [Client] {
        let specs = makeSpecs(count: count, seed: seed) + (includingPoison ? poisonedSpecs() : [])
        var clients: [Client] = []
        for (index, spec) in specs.enumerated() {
            clients.append(insert(spec, into: context))
            if (index + 1).isMultiple(of: batchSize) {
                try context.save()
            }
        }
        try context.save()
        return clients
    }
}

/// Small, fast, seedable generator; `SystemRandomNumberGenerator` can't be seeded.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }
    mutating func pick<T>(_ items: [T]) -> T { items[int(in: 0...(items.count - 1))] }
}

/// Writes a large book off the main actor in chunks, each through its own
/// short-lived `ModelContext`. A context keeps every model it touched until
/// it goes away, so one context for 1,000+ inserts holds them all; a context
/// per chunk caps that at one chunk, and each chunk is saved (durable) before
/// the next starts. Only `Sendable` values cross the actor boundary.
@ModelActor
actor ClientStressWriter {
    struct Report: Sendable {
        var inserted = 0
        var chunks = 0
    }

    func insert(_ specs: [ClientStressDataset.Spec], chunkSize: Int = 100) throws -> Report {
        var report = Report()
        var start = specs.startIndex
        while start < specs.endIndex {
            let end = min(start + max(1, chunkSize), specs.endIndex)
            try autoreleasepool {
                let chunkContext = ModelContext(modelContainer)
                chunkContext.autosaveEnabled = false
                for spec in specs[start..<end] {
                    ClientStressDataset.insert(spec, into: chunkContext)
                }
                try chunkContext.save()
            }
            report.inserted += end - start
            report.chunks += 1
            start = end
        }
        return report
    }
}
#endif
