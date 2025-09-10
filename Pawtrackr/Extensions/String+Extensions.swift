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
}
