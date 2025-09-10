//
//  String+CSV.swift
//  Pawtrackr
//
//  Shared CSV escaping for text fields used by export features.
//

import Foundation

extension String {
    /// Escape a string for CSV cells:
    /// - doubles any embedded quotes,
    /// - wraps in quotes if it contains comma, quote, newline, or leading/trailing space.
    var csvEscaped: String {
        guard !isEmpty else { return "" }
        let doubledQuotes = self.replacingOccurrences(of: "\"", with: "\"\"")
        let needsWrap =
            doubledQuotes.contains(",") ||
            doubledQuotes.contains("\n") ||
            doubledQuotes.contains("\"") ||
            self.first?.isWhitespace == true ||
            self.last?.isWhitespace == true
        return needsWrap ? "\"\(doubledQuotes)\"" : doubledQuotes
    }
}

