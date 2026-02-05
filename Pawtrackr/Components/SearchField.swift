
//
//  SearchField.swift
//  Pawtrackr
//
//  Created by Assistant on 9/15/25.
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    init(text: Binding<String>, placeholder: String = "Search...") {
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(DS.ColorToken.surface, in: .capsule)
    }
}
