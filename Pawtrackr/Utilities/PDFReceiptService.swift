//
//  PDFReceiptService.swift
//  Pawtrackr
//
//  Generates a professional PDF receipt for a Visit.
//

import Foundation
import SwiftUI
import PDFKit

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

@MainActor
class PDFReceiptService {
    static let shared = PDFReceiptService()
    
    func generatePDF(for visit: Visit) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        #if canImport(UIKit)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: bounds)
        
        return pdfRenderer.pdfData { rendererContext in
            rendererContext.beginPage()
            drawContent(in: rendererContext.cgContext, for: visit, bounds: bounds)
        }
        #else
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }
        
        context.beginPDFPage(nil)
        
        // On macOS, the coordinate system is bottom-left. We flip it to match iOS top-down.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        drawContent(in: context, for: visit, bounds: bounds)
        
        context.endPDFPage()
        context.closePDF()
        
        return data as Data
        #endif
    }
    
    private func drawContent(in context: CGContext, for visit: Visit, bounds: CGRect) {
        let margin: CGFloat = 50
        var currentY: CGFloat = 60
        
        // Fetch Business Config
        let config: BusinessConfig
        if let modelContext = visit.modelContext {
            let descriptor = FetchDescriptor<BusinessConfig>()
            config = (try? modelContext.fetch(descriptor).first) ?? .default
        } else {
            config = .default
        }
        
        // --- HEADER ---
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 28, weight: .black),
            .foregroundColor: PlatformColor.systemBlue
        ]
        let title = config.name.uppercased()
        title.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
        
        let receiptNumAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: PlatformColor.darkGray
        ]
        let receiptNum = "RECEIPT: #\(visit.uuid.uuidString.prefix(8).uppercased())"
        let receiptNumSize = receiptNum.size(withAttributes: receiptNumAttributes)
        receiptNum.draw(at: CGPoint(x: 612 - margin - receiptNumSize.width, y: currentY + 10), withAttributes: receiptNumAttributes)
        
        currentY += 45
        
        // Draw a thick header line
        context.setStrokeColor(PlatformColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: margin, y: currentY))
        context.addLine(to: CGPoint(x: 612 - margin, y: currentY))
        context.strokePath()
        
        currentY += 25
        
        // --- BUSINESS INFO ---
        let businessNameAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 14, weight: .bold)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11)
        ]
        
        config.name.draw(at: CGPoint(x: margin, y: currentY), withAttributes: businessNameAttributes)
        currentY += 18
        
        if let address = config.address, !address.isEmpty {
            address.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            currentY += 15
        }
        
        let contactParts = [config.email, config.phone].compactMap { $0 }.filter { !$0.isEmpty }
        if !contactParts.isEmpty {
            contactParts.joined(separator: " | ").draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            currentY += 15
        }
        
        currentY += 30
        
        // --- CLIENT & PET INFO ---
        let sectionHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: PlatformColor.gray
        ]
        
        "BILL TO".draw(at: CGPoint(x: margin, y: currentY), withAttributes: sectionHeaderAttributes)
        "DETAILS".draw(at: CGPoint(x: 350, y: currentY), withAttributes: sectionHeaderAttributes)
        
        currentY += 20
        
        let clientName = visit.pet?.owner?.fullName ?? "Valued Customer"
        let clientAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        clientName.draw(at: CGPoint(x: margin, y: currentY), withAttributes: clientAttributes)
        
        let dateStr = "Date: " + (visit.endedAt?.formatted(date: .long, time: .shortened) ?? visit.startedAt.formatted(date: .long, time: .shortened))
        dateStr.draw(at: CGPoint(x: 350, y: currentY), withAttributes: bodyAttributes)
        
        currentY += 18
        if let phone = visit.pet?.owner?.phone {
            let formattedPhone = PhoneUtils.display(phone) ?? phone
            formattedPhone.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            currentY += 15
        }
        
        let petStr = "Pet: \(visit.pet?.name ?? "Unknown") (\(visit.pet?.breed ?? "General"))"
        petStr.draw(at: CGPoint(x: 350, y: currentY), withAttributes: bodyAttributes)
        
        currentY += 50
        
        // --- SERVICES TABLE ---
        let tableHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: PlatformColor.white
        ]
        
        // Draw table header background
        let tableHeaderRect = CGRect(x: margin, y: currentY, width: 512, height: 25)
        context.setFillColor(PlatformColor.darkGray.cgColor)
        context.fill(tableHeaderRect)
        
        "SERVICE DESCRIPTION".draw(at: CGPoint(x: margin + 10, y: currentY + 6), withAttributes: tableHeaderAttributes)
        let priceHeader = "AMOUNT"
        let priceHeaderSize = priceHeader.size(withAttributes: tableHeaderAttributes)
        priceHeader.draw(at: CGPoint(x: 612 - margin - 10 - priceHeaderSize.width, y: currentY + 6), withAttributes: tableHeaderAttributes)
        
        currentY += 35
        
        for item in visit.items {
            item.name.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bodyAttributes)
            let priceStr = item.lineTotal.moneyString
            let priceSize = priceStr.size(withAttributes: bodyAttributes)
            priceStr.draw(at: CGPoint(x: 612 - margin - 10 - priceSize.width, y: currentY), withAttributes: bodyAttributes)
            
            currentY += 20
            
            // Draw a very light line between items
            context.setStrokeColor(PlatformColor.lightGray.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: currentY))
            context.addLine(to: CGPoint(x: 612 - margin, y: currentY))
            context.strokePath()
            
            currentY += 10
        }
        
        currentY += 20
        
        // --- TOTAL ---
        let totalLabelAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let totalValueAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 20, weight: .black),
            .foregroundColor: PlatformColor.systemBlue
        ]
        
        "GRAND TOTAL".draw(at: CGPoint(x: 350, y: currentY + 5), withAttributes: totalLabelAttributes)
        
        let totalStr = visit.total.moneyString
        let totalSize = totalStr.size(withAttributes: totalValueAttributes)
        totalStr.draw(at: CGPoint(x: 612 - margin - 10 - totalSize.width, y: currentY), withAttributes: totalValueAttributes)
        
        currentY += 60
        
        // --- PAYMENT INFO ---
        if let payment = visit.payment {
            let payTitleAttributes: [NSAttributedString.Key: Any] = [
                .font: PlatformFont.systemFont(ofSize: 12, weight: .bold)
            ]
            "PAYMENT INFORMATION".draw(at: CGPoint(x: margin, y: currentY), withAttributes: payTitleAttributes)
            currentY += 20
            
            let payInfo = "Paid via \(payment.method.displayName) on \(payment.paidAt.formatted(date: .abbreviated, time: .omitted))"
            payInfo.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            
            if let ref = payment.externalReference {
                currentY += 15
                "Reference: \(ref)".draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            }
        }
        
        // --- FOOTER ---
        #if canImport(UIKit)
        let italicFont = PlatformFont.italicSystemFont(ofSize: 10)
        #else
        let italicFont = NSFontManager.shared.convert(PlatformFont.systemFont(ofSize: 10), toHaveTrait: .italicFontMask)
        #endif
        
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: italicFont,
            .foregroundColor: PlatformColor.gray
        ]
        let footer = "Thank you for choosing Pawtrackr! We look forward to seeing your pet again soon."
        let footerSize = footer.size(withAttributes: footerAttributes)
        footer.draw(at: CGPoint(x: (612 - footerSize.width) / 2, y: 740), withAttributes: footerAttributes)
    }
}
