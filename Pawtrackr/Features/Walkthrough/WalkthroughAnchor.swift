//
//  WalkthroughAnchor.swift
//  Pawtrackr
//
//  Lets any control register its on-screen frame so the guided-tour overlay can
//  spotlight it. Uses SwiftUI `Anchor<CGRect>` preferences, which the overlay
//  resolves against its own coordinate space — no manual coordinate math, and it
//  stays correct through scrolling and rotation.
//

import SwiftUI

/// Collects the bounds of every registered walkthrough target in a subtree.
struct WalkthroughAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [WalkthroughAnchorID: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [WalkthroughAnchorID: Anchor<CGRect>],
        nextValue: () -> [WalkthroughAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Registers this view as a spotlight target for the guided tour. Harmless
    /// when no tour is running; the overlay only reads anchors while active.
    func walkthroughAnchor(_ id: WalkthroughAnchorID) -> some View {
        anchorPreference(key: WalkthroughAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}
