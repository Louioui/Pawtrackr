//
//  View+Extensions.swift
//  Pawtrackr
//
//  UI utility extensions for View-level logic.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform URL opener. On iOS uses UIApplication.open; on macOS uses NSWorkspace.
/// Silently does nothing on platforms without either, but in practice both ship.
@MainActor
enum URLOpener {
    static func open(_ url: URL) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        open(url)
    }
}

extension View {
    /// Presents a full screen cover on iOS and a standard sheet on macOS.
    /// This ensures a high-impact experience on mobile while respecting macOS windowing conventions.
    @ViewBuilder
    func adaptiveCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
    
    /// Presents a full screen cover for an item on iOS and a standard sheet on macOS.
    @ViewBuilder
    func adaptiveCover<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }

    /// Keeps a text binding within a fixed character budget while the user types or pastes.
    func textLengthLimit(_ text: Binding<String>, to maxLength: Int) -> some View {
        modifier(TextLengthLimitModifier(text: text, maxLength: maxLength))
    }
}

private struct TextLengthLimitModifier: ViewModifier {
    @Binding var text: String
    let maxLength: Int

    func body(content: Content) -> some View {
        content
            .onAppear(perform: clampTextIfNeeded)
            .onChange(of: text) { _, _ in
                clampTextIfNeeded()
            }
    }

    private func clampTextIfNeeded() {
        let limitedText = TextInputLimits.limited(text, to: maxLength)
        if limitedText != text {
            text = limitedText
        }
    }
}
