//
//  DemoDataSeeder.swift
//  Pawtrackr
//
//  Friendly starter data used by onboarding when the user chooses demo mode.
//

import Foundation
import SwiftData

enum DemoDataSeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        DataMigrations.ensureServiceCatalog(in: context)
        DataMigrations.ensureMessageTemplates(in: context)

        let services = try context.fetch(FetchDescriptor<Service>(sortBy: [SortDescriptor(\.name)]))
        applyPrices(to: services)

        let clientCount = try context.fetchCount(FetchDescriptor<Client>())
        if clientCount > 0 {
            if context.hasChanges {
                try context.save()
            }
            return
        }

        let ava = Client(
            firstName: "Ava",
            lastName: "Martinez",
            phone: "3125550110",
            email: "ava@example.com"
        )
        ava.setAddress("42 Cedar Street")

        let jordan = Client(
            firstName: "Jordan",
            lastName: "Lee",
            phone: "4155550142",
            email: "jordan@example.com"
        )
        jordan.setAddress("18 Harbor Avenue")

        let milo = Pet(name: "Milo", species: .dog, gender: .male)
        milo.setBreed("Mini Goldendoodle")
        milo.setColor("Apricot")
        milo.setPreferredGroomingFrequency(.monthly)
        milo.owner = ava
        ava.pets = [milo]

        let luna = Pet(name: "Luna", species: .dog, gender: .female)
        luna.setBreed("Shih Tzu")
        luna.setColor("White & Tan")
        luna.setPreferredGroomingFrequency(.monthly)
        luna.owner = jordan
        jordan.pets = [luna]

        context.insert(ava)
        context.insert(jordan)
        context.insert(milo)
        context.insert(luna)

        let now = Date()
        let activeVisit = Visit(pet: milo, startedAt: now.addingTimeInterval(-48 * 60))
        activeVisit.note = "Comfort breaks during drying help keep Milo relaxed."
        activeVisit.behaviorTags = ["Friendly", "Needs breaks"]
        context.insert(activeVisit)
        append(activeVisit, to: milo)

        let byName = Dictionary(uniqueKeysWithValues: services.map { ($0.name, $0) })

        var rebuiltDates: [Date] = []
        try addCompletedVisit(
            pet: milo,
            endedAt: now.addingTimeInterval(-2 * 86_400),
            serviceNames: ["Full Package", "Paw Trim"],
            paymentMethod: .cash,
            note: "Owner requested a shorter face tidy.",
            servicesByName: byName,
            context: context
        )
        rebuiltDates.append(now.addingTimeInterval(-2 * 86_400))

        try addCompletedVisit(
            pet: luna,
            endedAt: now.addingTimeInterval(-9 * 86_400),
            serviceNames: ["Bath", "Face Grooming"],
            paymentMethod: .creditCard,
            note: "Coat detangled well after conditioning treatment.",
            servicesByName: byName,
            context: context
        )
        rebuiltDates.append(now.addingTimeInterval(-9 * 86_400))

        try addCompletedVisit(
            pet: milo,
            endedAt: now.addingTimeInterval(-24 * 86_400),
            serviceNames: ["Haircut", "De-shedding"],
            paymentMethod: .zelle,
            note: "First full seasonal reset after winter coat growth.",
            servicesByName: byName,
            context: context
        )
        rebuiltDates.append(now.addingTimeInterval(-24 * 86_400))

        try context.save()

        for date in rebuiltDates {
            SummaryUpdater.rebuildDay(for: date, in: context)
        }
    }

    private static func addCompletedVisit(
        pet: Pet,
        endedAt: Date,
        serviceNames: [String],
        paymentMethod: Payment.Method,
        note: String,
        servicesByName: [String: Service],
        context: ModelContext
    ) throws {
        let startedAt = endedAt.addingTimeInterval(-75 * 60)
        let visit = Visit(pet: pet, startedAt: startedAt)
        visit.note = note
        context.insert(visit)
        append(visit, to: pet)

        for serviceName in serviceNames {
            guard let service = servicesByName[serviceName] else { continue }
            let item = VisitItem.from(service: service, visit: visit)
            context.insert(item)
            visit.items = (visit.items ?? []) + [item]
        }

        let total = max(visit.calculatedTotal, Decimal(25))
        let reference = paymentMethod.requiresExternalReference ? "DEMO-\(Int.random(in: 1000...9999))" : nil
        let payment = Payment(amount: total, method: paymentMethod, paidAt: endedAt, externalReference: reference)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: total, now: endedAt)
    }

    private static func applyPrices(to services: [Service]) {
        let prices: [String: Decimal] = [
            "Full Package": 95,
            "Basic Package": 72,
            "Spa Package": 118,
            "Bath": 45,
            "Haircut": 60,
            "De-shedding": 24,
            "Anal Glands Expression": 18,
            "Face Grooming": 22,
            "Paw Trim": 16,
            "Hygiene Area Trim": 20,
            "Knots and Matting Fee": 30,
            "Flea & Ticks Treatment": 28,
            "Hair Dye": 35
        ]

        for service in services {
            service.setBasePrice(prices[service.name] ?? 25)
            service.setEnabled(true)
        }
    }

    private static func append(_ visit: Visit, to pet: Pet) {
        var visits = pet.visits ?? []
        if !visits.contains(where: { $0.uuid == visit.uuid }) {
            visits.append(visit)
            pet.visits = visits
        }
    }
}
