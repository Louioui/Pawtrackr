//
//  String+Extensions.swift
//  Pawtrackr
//
//  Created by mac on 9/5/25.
//

import Foundation

extension String {
    /// Returns the string with leading and trailing whitespace and newlines removed.
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
    
    /// Returns a version of the string formatted for names (e.g. "o'brien" -> "O'Brien", "smith-jones" -> "Smith-Jones")
    var capitalizedName: String {
        let base = self.trimmed.lowercased()
        if base.isEmpty { return "" }
        
        let parts = base.split(separator: " ").map { part -> String in
            let p = String(part)
            if p.hasPrefix("o'"), p.count > 2 {
                let idx = p.index(p.startIndex, offsetBy: 2)
                let rest = p[idx...]
                return "O'" + rest.capitalized
            }
            return p.split(separator: "-").map { String($0).capitalized }.joined(separator: "-")
        }
        return parts.joined(separator: " ")
    }
}
