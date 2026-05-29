//
//  View+PhoneField.swift
//  Pawtrackr
//
//  Centralizes live phone-number formatting for text inputs.
//

import SwiftUI

extension View {
    /// Live-formats a bound phone string as the user types — e.g. "(555) 123-4567" —
    /// on every platform (iOS, iPadOS, macOS), and adds the phone keypad +
    /// telephone content type on iOS.
    ///
    /// Replaces six near-identical `onChange` blocks, several of which were wrapped
    /// in `#if os(iOS)` and therefore never inserted "()" / "-" on macOS.
    func phoneFieldFormatting(_ text: Binding<String>) -> some View {
        modifier(PhoneFieldFormatting(text: text))
    }
}

private struct PhoneFieldFormatting: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .autocorrectionDisabled()
            // Reformatting is idempotent: formatting an already-formatted string
            // yields the same value, so the `!=` guard stops the onChange loop
            // after a single rewrite.
            .onChange(of: text) { _, newValue in
                let formatted = PhoneUtils.formatAsYouType(newValue, includeExtension: false)
                if formatted != newValue { text = formatted }
            }
            #if os(iOS)
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
            #endif
    }
}
