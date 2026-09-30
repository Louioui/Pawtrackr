//
//  BusinessReportCSV.swift
//  Pawtrackr
//
//  The Insights report as a spreadsheet: a short heading block, then one
//  titled table per topic (summary, daily revenue, services, payment
//  methods, top clients, monthly performance, data to review), separated by
//  blank lines. Numbers are plain so every column can be summed or charted.
//  Safe off the main actor.
//

import Foundation

/// Something in the salon's records worth a look (Insights' data quality
/// checks), as the report lists it.
struct BusinessReportReviewItem: Sendable, Equatable {
    let title: String
    let count: Int
    let detail: String
}

enum BusinessReportCSV {
    static func make(
        facts: BusinessReportFacts,
        businessName: String,
        currencySymbol: String,
        reviewItems: [BusinessReportReviewItem],
        calendar: Calendar = .current
    ) -> ExportDocument {
        let dates = CSVDateFormats(timeZone: calendar.timeZone)
        var weekdayCalendar = calendar
        weekdayCalendar.locale = AppLocalization.currentLocale
        let weekdayNames = weekdayCalendar.weekdaySymbols

        func label(_ key: String, _ value: String) -> String {
            CSVFormat.text(AppLocalization.localized(key, value: value))
        }
        let money = CSVFormat.money
        let count = CSVFormat.integer

        var rows: [[String]] = [
            [label("report.title", "Business Report")],
            [label("report.business", "Business"), CSVFormat.text(businessName)],
            [label("report.period", "Period"), dates.day(facts.periodStart), dates.day(facts.periodLastDay)],
            [label("report.days", "Days"), count(facts.periodDays)],
            [label("report.generated", "Generated"), dates.stamp(facts.generatedAt)],
            [label("report.currency", "Currency"), CSVFormat.text(currencySymbol)],
            []
        ]

        rows += [
            [label("report.summary", "Summary")],
            [
                label("report.metric", "Metric"),
                label("report.this_period", "This period"),
                label("report.previous_period", "Previous period"),
                label("report.change_percent", "Change (%)")
            ],
            [
                label("report.revenue", "Revenue"),
                money(facts.revenue),
                money(facts.previousRevenue),
                CSVFormat.change(from: facts.previousRevenue, to: facts.revenue)
            ],
            [
                label("report.visits", "Visits"),
                count(facts.visits),
                count(facts.previousVisits),
                CSVFormat.change(from: Decimal(facts.previousVisits), to: Decimal(facts.visits))
            ],
            [
                label("report.average_ticket", "Average visit"),
                money(facts.averageTicket),
                facts.previousVisits > 0 ? money(facts.previousAverageTicket) : "",
                facts.previousVisits > 0 ? CSVFormat.change(from: facts.previousAverageTicket, to: facts.averageTicket) : ""
            ],
            [label("report.clients", "Clients"), count(facts.clients), "", ""],
            [label("report.first_time_clients", "First-time clients"), count(facts.firstTimeClients), "", ""],
            [label("report.returning_clients", "Returning clients"), count(facts.returningClients), "", ""],
            []
        ]

        rows += [
            [label("report.daily_revenue", "Daily revenue")],
            [label("report.date", "Date"), label("report.weekday", "Weekday"), label("report.visits", "Visits"), label("report.revenue", "Revenue")]
        ]
        for day in facts.days {
            let weekday = calendar.component(.weekday, from: day.date)
            let name = weekdayNames.indices.contains(weekday - 1) ? weekdayNames[weekday - 1] : ""
            rows.append([dates.day(day.date), CSVFormat.text(name), count(day.visits), money(day.revenue)])
        }
        rows.append([])

        let serviceTotal = facts.services.reduce(Decimal.zero) { $0 + $1.amount }
        rows += [
            [label("report.services", "Services")],
            [label("report.service", "Service"), label("report.sales", "Sales"), label("report.revenue", "Revenue"), label("report.share_percent", "Share (%)")]
        ]
        rows += facts.services.map {
            [CSVFormat.text($0.name), count($0.count), money($0.amount), CSVFormat.percent($0.amount, of: serviceTotal)]
        }
        rows.append([])

        let paidTotal = facts.payments.reduce(Decimal.zero) { $0 + $1.amount }
        rows += [
            [label("report.payment_methods", "Payment methods")],
            [label("report.method", "Method"), label("report.payments", "Payments"), label("report.amount", "Amount"), label("report.share_percent", "Share (%)")]
        ]
        rows += facts.payments.map {
            [CSVFormat.text($0.name), count($0.count), money($0.amount), CSVFormat.percent($0.amount, of: paidTotal)]
        }
        rows.append([])

        rows += [
            [label("report.top_clients", "Top clients")],
            [label("report.client", "Client"), label("report.visits", "Visits"), label("report.spend", "Spend")]
        ]
        rows += facts.topClients.map { [CSVFormat.text($0.name), count($0.count), money($0.amount)] }
        rows.append([])

        rows += [
            [label("report.monthly", "Monthly performance")],
            [label("report.month", "Month"), label("report.visits", "Visits"), label("report.revenue", "Revenue"), label("report.average_ticket", "Average visit")]
        ]
        rows += facts.months.map {
            [dates.month($0.start), count($0.visits), money($0.revenue), money(BusinessReportFacts.average($0.revenue, over: $0.visits))]
        }

        if !reviewItems.isEmpty {
            rows += [
                [],
                [label("report.data_to_review", "Data to review")],
                [label("report.issue", "Issue"), label("report.count", "Count"), label("report.detail", "Detail")]
            ]
            rows += reviewItems.map { [CSVFormat.text($0.title), count($0.count), CSVFormat.text($0.detail)] }
        }

        return ExportDocument(
            csvData: CSVFormat.document(rows),
            filename: "Pawtrackr_Insights_\(dates.day(facts.generatedAt)).csv"
        )
    }
}
