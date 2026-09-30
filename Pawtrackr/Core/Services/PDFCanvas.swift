//
//  PDFCanvas.swift
//  Pawtrackr
//
//  Renders PDF pages with a top-left origin on iOS and macOS alike. On the
//  Mac, AppKit draws strings into the *current* NSGraphicsContext, so the
//  PDF's context has to be made current (and flipped to match the drawing
//  coordinates). Without that, text drawn with NSString.draw never reached
//  the PDF. Safe off the main actor.
//

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PDFCanvas {
    /// US Letter, in points.
    static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// Draws `pageCount` pages. `drawPage` gets the page's index and a
    /// context whose origin is the page's top-left corner.
    static func render(
        bounds: CGRect = letter,
        pageCount: Int,
        drawPage: (_ index: Int, _ context: CGContext) -> Void
    ) -> Data {
        let pages = max(1, pageCount)
        #if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { rendererContext in
            for index in 0..<pages {
                rendererContext.beginPage()
                drawPage(index, rendererContext.cgContext)
            }
        }
        #else
        let data = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawPage(index, context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
        #endif
    }
}
