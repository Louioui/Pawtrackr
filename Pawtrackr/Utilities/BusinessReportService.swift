//
//  BusinessReportService.swift
//  Pawtrackr
//
//  Generates comprehensive business performance reports in PDF format.
//  Snapshot is built on the main actor (uses main-actor formatters);
//  rendering runs nonisolated so it can execute off the main thread.
//

import Foundation
import SwiftUI
import PDFKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private extension PlatformColor {
    static var pawSecondaryLabel: PlatformColor {
        #if canImport(UIKit)
        return .secondaryLabel
        #else
        return .secondaryLabelColor
        #endif
    }
    static var pawLabel: PlatformColor {
        #if canImport(UIKit)
        return .label
        #else
        return .labelColor
        #endif
    }
}

public final class BusinessReportService {
    static let shared = BusinessReportService()

    struct MonthlySummary {
        let month: Date
        let totalRevenue: Decimal
        let visitCount: Int
        let newClients: Int
        let topServices: [(name: String, count: Int, revenue: Decimal)]
        let retentionRate: Double
    }

    /// Pre-formatted snapshot safe to render off the main actor.
    struct ReportSnapshot: Sendable {
        struct ServiceRow: Sendable {
            let name: String
            let countString: String
            let revenueString: String
        }
        let monthString: String
        let totalRevenueString: String
        let visitCountString: String
        let newClientsString: String
        let retentionString: String
        let topServices: [ServiceRow]
        let timestampString: String
    }

    @MainActor
    func makeSnapshot(summary: MonthlySummary) -> ReportSnapshot {
        let topRows = summary.topServices.map { svc in
            ReportSnapshot.ServiceRow(
                name: svc.name,
                countString: "\(svc.count)",
                revenueString: svc.revenue.moneyString
            )
        }
        return ReportSnapshot(
            monthString: summary.month.formatted(.dateTime.month(.wide).year()).uppercased(),
            totalRevenueString: summary.totalRevenue.moneyString,
            visitCountString: "\(summary.visitCount)",
            newClientsString: "\(summary.newClients)",
            retentionString: "\(Int(summary.retentionRate * 100))%",
            topServices: topRows,
            timestampString: "Generated on \(Date().formatted(date: .long, time: .shortened))"
        )
    }

    @MainActor
    func generateMonthlyReport(summary: MonthlySummary) -> Data {
        let snap = makeSnapshot(summary: summary)
        return Self.render(snapshot: snap)
    }

    /// Build the snapshot on main, then render the PDF off-main.
    @MainActor
    func generateMonthlyReportAsync(summary: MonthlySummary) async -> Data {
        let snap = makeSnapshot(summary: summary)
        return await Task.detached(priority: .userInitiated) {
            Self.render(snapshot: snap)
        }.value
    }

    nonisolated static func render(snapshot: ReportSnapshot) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        #if canImport(UIKit)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        return pdfRenderer.pdfData { rendererContext in
            rendererContext.beginPage()
            drawReport(in: rendererContext.cgContext, snapshot: snapshot, bounds: bounds)
        }
        #else
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        drawReport(in: context, snapshot: snapshot, bounds: bounds)
        context.endPDFPage()
        context.closePDF()
        return data as Data
        #endif
    }

    private nonisolated static func drawReport(in context: CGContext, snapshot: ReportSnapshot, bounds: CGRect) {
        let margin: CGFloat = 50
        var currentY: CGFloat = 60

        // --- HEADER ---
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 24, weight: .black),
            .foregroundColor: PlatformColor.systemBlue
        ]
        "PAWTRACKR BUSINESS REPORT".draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: PlatformColor.pawSecondaryLabel
        ]
        snapshot.monthString.draw(at: CGPoint(x: margin, y: currentY + 30), withAttributes: subtitleAttributes)

        currentY += 70

        // --- KEY METRICS GRID ---
        drawMetricBox(title: "TOTAL REVENUE", value: snapshot.totalRevenueString, at: CGPoint(x: margin, y: currentY), width: 240, context: context)
        drawMetricBox(title: "TOTAL VISITS", value: snapshot.visitCountString, at: CGPoint(x: margin + 260, y: currentY), width: 240, context: context)

        currentY += 80

        drawMetricBox(title: "NEW CLIENTS", value: snapshot.newClientsString, at: CGPoint(x: margin, y: currentY), width: 240, context: context)
        drawMetricBox(title: "RETENTION RATE", value: snapshot.retentionString, at: CGPoint(x: margin + 260, y: currentY), width: 240, context: context)

        currentY += 120

        // --- TOP SERVICES TABLE ---
        let sectionHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 16, weight: .bold)
        ]
        "SERVICE PERFORMANCE".draw(at: CGPoint(x: margin, y: currentY), withAttributes: sectionHeaderAttributes)

        currentY += 30

        let tableHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: PlatformColor.white
        ]

        let tableRect = CGRect(x: margin, y: currentY, width: 512, height: 20)
        context.setFillColor(PlatformColor.darkGray.cgColor)
        context.fill(tableRect)

        "SERVICE NAME".draw(at: CGPoint(x: margin + 10, y: currentY + 4), withAttributes: tableHeaderAttributes)
        "COUNT".draw(at: CGPoint(x: margin + 300, y: currentY + 4), withAttributes: tableHeaderAttributes)
        "REVENUE".draw(at: CGPoint(x: margin + 400, y: currentY + 4), withAttributes: tableHeaderAttributes)

        currentY += 25

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11)
        ]

        for svc in snapshot.topServices {
            svc.name.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bodyAttributes)
            svc.countString.draw(at: CGPoint(x: margin + 300, y: currentY), withAttributes: bodyAttributes)
            svc.revenueString.draw(at: CGPoint(x: margin + 400, y: currentY), withAttributes: bodyAttributes)

            currentY += 20
            context.setStrokeColor(PlatformColor.lightGray.withAlphaComponent(0.2).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: currentY))
            context.addLine(to: CGPoint(x: 612 - margin, y: currentY))
            context.strokePath()
            currentY += 5
        }

        // --- FOOTER ---
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 9),
            .foregroundColor: PlatformColor.pawSecondaryLabel
        ]
        snapshot.timestampString.draw(at: CGPoint(x: margin, y: 740), withAttributes: footerAttributes)
    }

    private nonisolated static func drawMetricBox(title: String, value: String, at point: CGPoint, width: CGFloat, context: CGContext) {
        let rect = CGRect(x: point.x, y: point.y, width: width, height: 60)
        context.setStrokeColor(PlatformColor.lightGray.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: PlatformColor.pawSecondaryLabel
        ]
        title.draw(at: CGPoint(x: point.x + 10, y: point.y + 10), withAttributes: titleAttributes)

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: PlatformColor.pawLabel
        ]
        value.draw(at: CGPoint(x: point.x + 10, y: point.y + 25), withAttributes: valueAttributes)
    }
}
