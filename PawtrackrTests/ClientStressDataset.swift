//
//  ClientStressDataset.swift
//  PawtrackrTests
//
//  A reusable, deterministic book of 500+ awkward clients for stress tests:
//  very long names, punctuation, padding, empty first or last names, case
//  variants of one surname, accented and non-Latin scripts, emoji, numbered
//  names, exact duplicates, valid and invalid phones, zero to three pets,
//  and tied dates. Seed it into an in-memory container only.
//

import Foundation
import SwiftData
@testable import Pawtrackr

enum ClientStressDataset {
    /// Clients the tests look up by name. Each exists exactly once unless
    /// the name says otherwise.
    enum Landmark {
        static let anaZamora = ("Ana", "Zamora")
        static let nunez = ("José", "Ñúñez")
        static let obrien = ("Siobhán", "O'Brien")
        /// Three clients named exactly "Sam Lee".
        static let samLee = ("Sam", "Lee")
        /// "Smith", "SMITH" and "smith", one client each.
        static let smithVariants = ["Smith", "SMITH", "smith"]
        static let onlyFirstName = "Cher"
        static let chinese = ("伟", "王")
        static let phoneDigits = "3238170042"
        /// Pets "Zeus" and "apollo": the card lists apollo first.
        static let twoPetOwner = ("Pat", "Twopets")
    }

    static let fillerCount = 500

    private static let firstNames = [
        "Ana", "Émile", "Zoë", "Łukasz", "Søren", "Mary Ann", "Jean-Luc", "D'Arcy",
        "Анна", "Мария", "佐藤", "محمد", "שרה", "Nguyễn", "🐶 Lover", "x",
        "Bob", "bob", "BOB", "Chloé", "İsmail", "Ægir", "Ödön", "Ñandú"
    ]

    private static let lastNames = [
        "Adams", "adams", "ADAMS", "de la Cruz", "van Dyke", "O'Connor", "Smith-Jones",
        "Müller", "Øster", "Ångström", "Çelik", "Иванов", "Petrov", "王", "李", "خان",
        "כהן", "Nguyễn", "Zúñiga", "zimmerman", "Client 9", "Client 10", "Client 100",
        "  Padded  ", "#hashtag", "(Paren)", "Ünal", "Éclair"
    ]

    private static let petNames = ["Bella", "bella", "Max", "Zeus", "apollo", "Ñoño", "🐾", "Luna", "milo", "Rex 2", "Rex 10"]

    private static let phones: [String?] = [
        nil, "", "abc", "123", "+", "555-555-55555555", "☎️ 555",
        "(323) 817-5565", "323.817.0100", "+1 323 817 0101", "+44 20 7946 0958", "0000000000"
    ]

    /// Seeds `fillerCount` generated clients plus the landmarks and saves.
    /// The same `seed` always yields the same book.
    @discardableResult
    @MainActor
    static func seed(into context: ModelContext, seed: UInt64 = 0x5EED_C11E) throws -> [Client] {
        var rng = Generator(state: seed)
        var clients: [Client] = []
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<fillerCount {
            var first = firstNames[rng.nextInt(firstNames.count)]
            var last = lastNames[rng.nextInt(lastNames.count)]
            switch index % 50 {
            case 0: first = ""                                       // no first name
            case 1: last = ""                                        // no last name
            case 2: first = String(repeating: "Bartholomew", count: 30) // past the 64 limit
            case 3: last = String(repeating: "Featherstonehaugh-", count: 20)
            default: break
            }

            let client = Client(firstName: first, lastName: last)
            if rng.nextBool() {
                client.setPhone(phones[rng.nextInt(phones.count)])
            } else {
                client.phone = phones[rng.nextInt(phones.count)]
            }
            if rng.nextInt(3) == 0 { client.setEmail("client\(index)@example.com") }
            // Coarse dates so plenty of clients tie on them.
            client.createdAt = baseDate.addingTimeInterval(Double(rng.nextInt(20)) * 86_400)
            client.lastVisitDate = rng.nextInt(3) == 0 ? nil : baseDate.addingTimeInterval(Double(rng.nextInt(30)) * 86_400)
            context.insert(client)

            for _ in 0..<rng.nextInt(4) {
                let pet = Pet(name: petNames[rng.nextInt(petNames.count)], species: rng.nextBool() ? .dog : .cat)
                pet.owner = client
                context.insert(pet)
            }
            clients.append(client)
        }

        func landmark(_ first: String, _ last: String, phone: String? = nil) -> Client {
            let client = Client(firstName: first, lastName: last)
            client.setPhone(phone)
            client.createdAt = baseDate
            context.insert(client)
            clients.append(client)
            return client
        }

        _ = landmark(Landmark.anaZamora.0, Landmark.anaZamora.1)
        _ = landmark(Landmark.nunez.0, Landmark.nunez.1)
        _ = landmark(Landmark.obrien.0, Landmark.obrien.1)
        for _ in 0..<3 { _ = landmark(Landmark.samLee.0, Landmark.samLee.1) }
        for variant in Landmark.smithVariants { _ = landmark("Jo", variant) }
        _ = landmark(Landmark.onlyFirstName, "")
        _ = landmark(Landmark.chinese.0, Landmark.chinese.1)
        _ = landmark("Dial", "Tone", phone: "(323) 817-0042")
        _ = landmark("", "")

        let twoPets = landmark(Landmark.twoPetOwner.0, Landmark.twoPetOwner.1)
        for name in ["Zeus", "apollo"] {
            let pet = Pet(name: name, species: .dog)
            pet.owner = twoPets
            context.insert(pet)
        }

        try context.save()
        return clients
    }

    /// Checks in one pet for each of `count` clients that have pets.
    @MainActor
    static func checkIn(_ count: Int, from clients: [Client], in context: ModelContext) throws -> [Client] {
        let owners = clients.filter { !($0.pets ?? []).isEmpty }.prefix(count)
        for owner in owners {
            if let pet = owner.pets?.first {
                context.insert(Visit(pet: pet))
            }
        }
        try context.save()
        return Array(owners)
    }

    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11
        }

        mutating func nextInt(_ upperBound: Int) -> Int {
            Int(next() % UInt64(upperBound))
        }

        mutating func nextBool() -> Bool {
            nextInt(2) == 0
        }
    }
}
