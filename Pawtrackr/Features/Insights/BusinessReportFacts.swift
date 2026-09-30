//
//  BusinessReportFacts.swift
//  Pawtrackr
//
//  The numbers behind the Insights report, PDF and CSV alike, worked out
//  from finished visits for one period. Totals, the daily series, services,
//  payment methods and clients all come from the same visits, so every
//  figure in the report agrees with the others. Money stays Decimal.
//

import Foundation
import SwiftData

struct BusinessReportFacts: Sendable, Equatable {
    struct Day: Sendable, Equatable {
        let date: Date
        var revenue: Decimal = .zero
        var visits = 0
    }

    struct Month: Sendable, Equatable {
        let start: Date
        var revenue: Decimal = .zero
        var visits = 0
    }

    /// A service, payment method or client: how often, and how much.
    struct Line: Sendable, Equatable {
        let name: String
        var count = 0
        var amount: Decimal = .zero

        mutating func add(count: Int, amount: Decimal) {
            self.count += count
            self.amount += amount
        }

        /// Most money first, then most often, then by name.
        static func byAmount(_ lhs: Line, _ rhs: Line) -> Bool {
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    struct Weekday: Sendable, Equatable {
        /// `Calendar` weekday: 1 is Sunday.
        let weekday: Int
        let visits: Int
    }

    let generatedAt: Date
    let periodDays: Int
    /// The period's first day, at its start.
    let periodStart: Date
    /// The start of the day after the period's last day (today).
    let periodEnd: Date

    var revenue: Decimal = .zero
    var visits = 0
    /// The same number of days just before the period.
    var previousRevenue: Decimal = .zero
    var previousVisits = 0
    /// Clients with a finished visit in the period.
    var clients = 0
    /// Of those, the ones whose first ever visit is in the period.
    var firstTimeClients = 0
    /// Every day of the period, days without visits included.
    var days: [Day] = []
    /// The last six months, this one included, oldest first.
    var months: [Month] = []
    var services: [Line] = []
    var payments: [Line] = []
    /// The five clients who spent the most in the period.
    var topClients: [Line] = []
    var busiestWeekday: Weekday?

    var averageTicket: Decimal { Self.average(revenue, over: visits) }
    var previousAverageTicket: Decimal { Self.average(previousRevenue, over: previousVisits) }
    var returningClients: Int { clients - firstTimeClients }
    /// The period's last day, for labels.
    var periodLastDay: Date { days.last?.date ?? periodStart }

    static func average(_ amount: Decimal, over count: Int) -> Decimal {
        count > 0 ? (amount / Decimal(count)).roundedMoney() : .zero
    }
}

extension BusinessReportFacts {
    enum BuildError: Error {
        case invalidPeriod
    }

    /// Reads the store on a background context of its own.
    static func build(
        container: ModelContainer,
        periodDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> BusinessReportFacts {
        try await Task.detached(priority: .userInitiated) {
            try Self.build(in: ModelContext(container), periodDays: periodDays, now: now, calendar: calendar)
        }.value
    }

    /// The period ends with today, like the Insights charts: `periodDays`
    /// days up to and including the day of `now`.
    static func build(
        in context: ModelContext,
        periodDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> BusinessReportFacts {
        let dayCount = max(1, min(periodDays, 365))
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: today),
              let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today),
              let previousStart = calendar.date(byAdding: .day, value: -dayCount, to: start),
              let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let firstMonth = calendar.date(byAdding: .month, value: -5, to: thisMonth)
        else { throw BuildError.invalidPeriod }

        let from = min(previousStart, firstMonth)
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { visit in
                if let endedAt = visit.endedAt {
                    endedAt >= from && endedAt < end
                } else {
                    false
                }
            }
        )
        let visits = try context.fetch(descriptor)

        var facts = BusinessReportFacts(generatedAt: now, periodDays: dayCount, periodStart: start, periodEnd: end)

        var dayIndex: [Date: Int] = [:]
        var cursor = start
        while cursor < end {
            dayIndex[cursor] = facts.days.count
            facts.days.append(Day(date: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var monthIndex: [Date: Int] = [:]
        for offset in 0..<6 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: firstMonth) else { continue }
            monthIndex[month] = facts.months.count
            facts.months.append(Month(start: month))
        }

        var services: [String: Line] = [:]
        var payments: [String: Line] = [:]
        var clientLines: [UUID: Line] = [:]
        var clientsSeen: [UUID: Client] = [:]
        var weekdays: [Int: Int] = [:]

        for visit in visits {
            guard let ended = visit.endedAt else { continue }
            let total = visit.total

            if let month = calendar.date(from: calendar.dateComponents([.year, .month], from: ended)),
               let index = monthIndex[month] {
                facts.months[index].revenue += total
                facts.months[index].visits += 1
            }

            if ended >= previousStart && ended < start {
                facts.previousRevenue += total
                facts.previousVisits += 1
                continue
            }
            guard ended >= start && ended < end else { continue }

            facts.revenue += total
            facts.visits += 1
            if let index = dayIndex[calendar.startOfDay(for: ended)] {
                facts.days[index].revenue += total
                facts.days[index].visits += 1
            }
            weekdays[calendar.component(.weekday, from: ended), default: 0] += 1

            for item in visit.items ?? [] {
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                services[name, default: Line(name: name)].add(count: max(1, item.quantity), amount: item.lineTotal)
            }
            if let payment = visit.payment {
                let name = payment.method.displayName
                payments[name, default: Line(name: name)].add(count: 1, amount: payment.amount)
            }
            if let owner = visit.pet?.owner {
                clientLines[owner.uuid, default: Line(name: owner.fullName)].add(count: 1, amount: total)
                clientsSeen[owner.uuid] = owner
            }
        }

        facts.clients = clientsSeen.count
        facts.firstTimeClients = clientsSeen.values.filter { client in
            let firstVisit = (client.pets ?? [])
                .flatMap { $0.visits ?? [] }
                .compactMap(\.endedAt)
                .min()
            return firstVisit.map { $0 >= start } ?? false
        }.count
        facts.services = services.values.sorted(by: Line.byAmount)
        facts.payments = payments.values.sorted(by: Line.byAmount)
        facts.topClients = Array(clientLines.values.sorted(by: Line.byAmount).prefix(5))
        // Ties go to the earlier weekday.
        if let best = weekdays.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            facts.busiestWeekday = Weekday(weekday: best.key, visits: best.value)
        }
        return facts
    }
}
