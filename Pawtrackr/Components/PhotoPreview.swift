//
//  PhotoPreview.swift
//  Pawtrackr
//
//  Full-screen, accessible photo preview with pinch-to-zoom and pan.
//  Used by VisitDetailView to preview Before/After photos.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct PhotoPreview: View {
    let imageData: Data
    let title: String
    @Environment(\.dismiss) private var dismiss

    // Simple zoom/pan state using gestures (cross-platform SwiftUI)
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white)
                    }
                    Spacer()
                    Text(title).foregroundStyle(.white.opacity(0.9)).font(.headline)
                    Spacer()
                    // spacer for symmetry
                    Image(systemName: "xmark.circle.fill").opacity(0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer(minLength: 0)

                if let image = cachedImage(imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnifyGesture)
                        .gesture(dragGesture)
                        .onTapGesture(count: 2, perform: toggleZoom)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: scale)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: offset)
                        .accessibilityLabel(Text("\(title) photo preview"))
                        .accessibilityHint(Text("Pinch with two fingers to zoom"))
                } else {
                    Text(NSLocalizedString("photo_preview.unable_to_load", comment: "")).foregroundStyle(.white)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clampScale(lastScale * value.magnification)
            }
            .onEnded { value in
                lastScale = clampScale(lastScale * value.magnification)
                if lastScale <= 1 { // reset pan if fully zoomed out
                    lastScale = 1
                    scale = 1
                    lastOffset = .zero
                    offset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { value in
                guard scale > 1 else { return }
                lastOffset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
            }
    }

    private func toggleZoom() {
        if scale > 1.01 {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        } else {
            scale = 2
            lastScale = 2
        }
    }

    private func clampScale(_ s: CGFloat) -> CGFloat { max(1.0, min(4.0, s)) }
}

// Data → SwiftUI Image helper (module-wide safe)
fileprivate func cachedImage(_ data: Data) -> Image? {
    #if canImport(UIKit)
    if let ui = ImageCache.shared.image(data: data, maxDimension: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 2) {
        return Image(uiImage: ui)
    }
    #elseif canImport(AppKit)
    if let ns = NSImage(data: data) { return Image(nsImage: ns) }
    #endif
    return nil
}
