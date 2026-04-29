//
//  View+Extensions.swift
//  Pawtrackr
//
//  UI utility extensions for View-level logic.
//

import SwiftUI

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
}
