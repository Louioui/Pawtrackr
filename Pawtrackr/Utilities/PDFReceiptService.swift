//
//  PDFReceiptService.swift
//  Pawtrackr
//
//  Generates a professional PDF receipt for a Visit.
//

import Foundation
import SwiftUI
import PDFKit

@MainActor
class PDFReceiptService {
    static let shared = PDFReceiptService()
    
    func generatePDF(for visit: Visit) -> Data {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)) // Standard US Letter
        
        let data = pdfRenderer.pdfData { context in
            pdfRenderer.beginPage()
            
            let margin: CGFloat = 50
            let contentWidth: CGFloat = 512
            var currentY: CGFloat = 60
            
            // --- HEADER ---
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold)
            ]
            let title = "RECEIPT: #\(visit.uuid.uuidString.prefix(8))"
            title.draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttributes)
            
            currentY += 40
            
            // --- BUSINESS INFO (Placeholder) ---
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            "Pawtrackr Grooming".draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            currentY += 15
            "Professional Pet Care Services".draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            
            currentY += 40
            
            // --- CLIENT & PET INFO ---
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
            ]
            "BILL TO:".draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttributes)
            "DATE:".draw(at: CGPoint(x: 400, y: currentY), withAttributes: headerAttributes)
            
            currentY += 20
            
            let clientName = visit.pet?.owner?.fullName ?? "Valued Customer"
            clientName.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            
            let dateStr = visit.endedAt?.formatted(date: .long, time: .shortened) ?? visit.startedAt.formatted(date: .long, time: .shortened)
            dateStr.draw(at: CGPoint(x: 400, y: currentY), withAttributes: bodyAttributes)
            
            currentY += 15
            if let phone = visit.pet?.owner?.phone {
                PhoneUtils.display(phone)?.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
                currentY += 15
            }
            
            currentY += 10
            "Pet: \(visit.pet?.name ?? "Unknown") (\(visit.pet?.breed ?? "General"))".draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
            
            currentY += 40
            
            // --- SERVICES TABLE ---
            let tableHeaderY = currentY
            "Service".draw(at: CGPoint(x: margin, y: tableHeaderY), withAttributes: headerAttributes)
            "Price".draw(at: CGPoint(x: 480, y: tableHeaderY), withAttributes: headerAttributes)
            
            currentY += 25
            
            // Draw a line
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: currentY))
            path.addLine(to: CGPoint(x: 562, y: currentY))
            path.lineWidth = 1
            UIColor.lightGray.setStroke()
            path.stroke()
            
            currentY += 10
            
            for item in visit.items {
                item.name.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
                item.lineTotal.moneyString.draw(at: CGPoint(x: 480, y: currentY), withAttributes: bodyAttributes)
                currentY += 20
            }
            
            currentY += 20
            
            // --- TOTAL ---
            let totalAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold)
            ]
            "TOTAL".draw(at: CGPoint(x: 380, y: currentY), withAttributes: totalAttributes)
            visit.total.moneyString.draw(at: CGPoint(x: 480, y: currentY), withAttributes: totalAttributes)
            
            currentY += 40
            
            // --- PAYMENT INFO ---
            if let payment = visit.payment {
                let payInfo = "Paid via \(payment.method.displayName) on \(payment.paidAt.formatted(date: .abbreviated, time: .omitted))"
                payInfo.draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
                
                if let ref = payment.externalReference {
                    currentY += 15
                    "Reference: \(ref)".draw(at: CGPoint(x: margin, y: currentY), withAttributes: bodyAttributes)
                }
            }
            
            // --- FOOTER ---
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
            let footer = "Thank you for trusting Pawtrackr with your pet's care!"
            let footerSize = footer.size(withAttributes: footerAttributes)
            footer.draw(at: CGPoint(x: (612 - footerSize.width) / 2, y: 740), withAttributes: footerAttributes)
        }
        
        return data
    }
}
