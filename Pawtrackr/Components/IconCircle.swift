//
//  IconCircle.swift
//  Pawtrackr
//
//  Reusable circular icon with configurable content, styles, and badges.
//  - Logic is simplified using a GlyphContent enum for clear rendering paths.
//  - Uses shared helpers for cross-platform image decoding.
//
//  Updated by Assistant on 2025-08-28.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct IconCircle: View {
    // MARK: - Types
    typealias SizeToken = IconSizeToken
    
    enum Style: Equatable {
        case solid(bg: Color, fg: Color)
        case tinted(Color) // bg; fg will default to white
        case auto(species: Species?, gender: PetGender?) // gender/species-aware tinting
    }

    /// Defines the content to be rendered, determined by priority in the initializer.
    private indirect enum GlyphContent {
        case remote(url: URL, fallback: GlyphContent)
        case thumbnail(data: Data, original: Data?)
        case local(data: Data)
        case initials(String)
        case symbol(String)
        case fallback
    }
    
    // MARK: - Properties
    private let sizeToken: SizeToken
    private let style: Style
    private let lineWidth: CGFloat
    private let badgeSystemImage: String?
    private let badgeColor: Color?
    private let accessibilityLabel: String?
    private let isDecorative: Bool
    private let glyphContent: GlyphContent

    // MARK: - Initializer
    
    /// Creates a versatile circular icon.
    ///
    /// The content is determined by priority: `imageURL` > `thumbnailData` > `imageData` > `initials` > `systemImage`.
    ///
    /// - Parameters:
    ///   - systemImage: The name of an SF Symbol to display.
    ///   - initials: A name or string to be converted into initials.
    ///   - imageData: Raw `Data` for a local image.
    ///   - thumbnailData: Small pre-downsampled `Data` for performance.
    ///   - imageURL: A `URL` for a remote image to be loaded asynchronously.
    ///   - size: A predefined or custom size token.
    ///   - style: The color and fill style of the circle.
    ///   - lineWidth: The width of an optional stroke around the circle.
    ///   - badgeSystemImage: An optional SF Symbol to display in a bottom-trailing badge.
    ///   - badgeColor: An optional `Color` for a simple dot badge.
    ///   - accessibilityLabel: A custom label for VoiceOver.
    ///   - isDecorative: If `true`, the icon is ignored by accessibility services.
    public init(systemImage: String? = nil,
                initials: String? = nil,
                imageData: Data? = nil,
                thumbnailData: Data? = nil,
                imageURL: URL? = nil,
                size: SizeToken = .md,
                style: Style = .tinted(Color.accentColor.opacity(0.15)),
                lineWidth: CGFloat = 0,
                badgeSystemImage: String? = nil,
                badgeColor: Color? = nil,
                accessibilityLabel: String? = nil,
                isDecorative: Bool = false) {
        self.sizeToken = size
        self.style = style
        self.lineWidth = lineWidth
        self.badgeSystemImage = badgeSystemImage
        self.badgeColor = badgeColor
        self.accessibilityLabel = accessibilityLabel
        self.isDecorative = isDecorative
        
        // Determine the glyph content based on priority
        let initialsGlyph = Self.makeInitials(from: initials).map { GlyphContent.initials($0) }
        let symbolGlyph = systemImage.map { GlyphContent.symbol($0) }
        let fallback = initialsGlyph ?? symbolGlyph ?? .fallback

        if let url = imageURL {
            self.glyphContent = .remote(url: url, fallback: fallback)
        } else if let thumb = thumbnailData {
            self.glyphContent = .thumbnail(data: thumb, original: imageData)
        } else if let data = imageData {
            self.glyphContent = .local(data: data)
        } else {
            self.glyphContent = fallback
        }
    }

    // MARK: - Body
    var body: some View {
        let dim = sizeToken.diameter
        let tints = self.tints(for: style)

        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(tints.bg)
                .overlay(Circle().strokeBorder(tints.ring, lineWidth: lineWidth > 0 ? lineWidth : 0))
                .frame(width: dim, height: dim)

            glyphView(content: glyphContent, tints: tints)
            
            badgeView(tints: tints)
        }
        .contentShape(Circle())
        .modifier(AccessibilityModifier(
            label: accessibilityLabel,
            defaultLabel: defaultAccessibilityLabel,
            isDecorative: isDecorative
        ))
    }

    // MARK: - Subviews
    
    @ViewBuilder
    private func glyphView(content: GlyphContent, tints: (bg: Color, fg: Color, ring: Color)) -> some View {
        let dim = sizeToken.diameter
        
        switch content {
        case .remote(let url, _):
            CachedAsyncImage(url: url, maxDimension: dim * 2) {
                ZStack { Circle().fill(tints.bg); ProgressView() }
            } failure: {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tints.fg)
            }
            .frame(width: dim, height: dim)
            .clipShape(Circle())

        case .thumbnail(let data, let original):
            #if canImport(UIKit)
            if let ui = ImageCache.shared.image(data: data, maxDimension: dim * 2) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: dim, height: dim)
                    .clipShape(Circle())
            } else if let orig = original, let ui = ImageCache.shared.image(data: orig, maxDimension: dim * 2) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: dim, height: dim)
                    .clipShape(Circle())
            } else {
                fallbackSymbol(tints: tints)
            }
            #else
            if let image = Image(platformImage: data) {
                image.resizable().scaledToFill()
                    .frame(width: dim, height: dim)
                    .clipShape(Circle())
            } else {
                fallbackSymbol(tints: tints)
            }
            #endif

        case .local(let data):
            #if canImport(UIKit)
            if let ui = ImageCache.shared.image(data: data, maxDimension: dim * 2) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: dim, height: dim)
                    .clipShape(Circle())
            } else {
                fallbackSymbol(tints: tints)
            }
            #else
            if let image = Image(platformImage: data) {
                image.resizable().scaledToFill()
                    .frame(width: dim, height: dim)
                    .clipShape(Circle())
            } else {
                fallbackSymbol(tints: tints)
            }
            #endif

        case .initials(let text):
            Text(text)
                .font(.system(size: dim * sizeToken.iconScale, weight: sizeToken.fontWeight, design: .rounded))
                .foregroundStyle(tints.fg)

        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: dim * sizeToken.iconScale, weight: sizeToken.fontWeight))
                .foregroundStyle(tints.fg)

        case .fallback:
            fallbackSymbol(tints: tints)
        }
    }

    private func fallbackSymbol(tints: (bg: Color, fg: Color, ring: Color)) -> some View {
        let dim = sizeToken.diameter
        return Image(systemName: "pawprint.fill")
            .font(.system(size: dim * sizeToken.iconScale, weight: sizeToken.fontWeight))
            .foregroundStyle(tints.fg)
    }
    
    @ViewBuilder
    private func badgeView(tints: (bg: Color, fg: Color, ring: Color)) -> some View {
        let dim = sizeToken.diameter
        let badgeOffset = dim * 0.08
        
        if let badgeSystemImage {
            let badgeDim = max(14, dim * 0.36)
            Image(systemName: badgeSystemImage)
                .font(.system(size: badgeDim * 0.55, weight: .bold))
                .foregroundStyle(tints.fg)
                .frame(width: badgeDim, height: badgeDim)
                .background(Circle().fill(.thickMaterial))
                .overlay(Circle().stroke(.separator, lineWidth: 0.5))
                .offset(x: badgeOffset, y: badgeOffset)
                .accessibilityHidden(true)
        } else if let badgeColor {
            let badgeDim = max(10, dim * 0.22)
            Circle()
                .fill(badgeColor)
                .frame(width: badgeDim, height: badgeDim)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .offset(x: badgeOffset, y: badgeOffset)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Private Helpers
    
    private func tints(for style: Style) -> (bg: Color, fg: Color, ring: Color) {
        switch style {
        case .solid(let bg, let fg):
            return (bg, fg, fg.opacity(0.85))

        case .tinted(let bg):
            return (bg, .white, .white.opacity(0.9))

        case .auto(_, let gender):
            if let gender {
                let base = DS.ColorToken.gender(gender)
                return (base.opacity(0.15), .white, .white.opacity(0.9))
            } else {
                let base = Color.secondary.opacity(0.55)
                return (base.opacity(0.15), .white, .white.opacity(0.9))
            }
        }
    }

    private var defaultAccessibilityLabel: String {
        switch glyphContent {
        case .initials(let str): return "Avatar with initials \(str)"
        case .symbol(let name): return name.replacingOccurrences(of: ".", with: " ") + " icon"
        default: return "Avatar"
        }
    }
}

// MARK: - Convenience Initializers & Utilities
extension IconCircle {
    /// Creates a pet-specific avatar using the `.auto` style for gender-aware tinting.
    init(pet: Pet, size: SizeToken = .md, badge: String? = nil) {
        self.init(
            systemImage: (pet.species == .cat) ? "cat.fill" : "dog.fill", // More specific icons
            initials: pet.name,
            imageData: pet.photoData,
            size: size,
            style: .auto(species: pet.species, gender: pet.gender),
            badgeSystemImage: badge
        )
    }
    
    /// A robust utility to generate initials from a name string.
    static func makeInitials(from name: String?) -> String? {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let parts = raw.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let initials = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return initials.isEmpty ? nil : initials
    }
}

// MARK: - Private Modifier
private struct AccessibilityModifier: ViewModifier {
    let label: String?
    let defaultLabel: String
    let isDecorative: Bool
    
    func body(content: Content) -> some View {
        if isDecorative {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label ?? defaultLabel))
                .accessibilityAddTraits(.isImage)
        }
    }
}

// MARK: - Data → SwiftUI Image helper
private extension Image {
    init?(platformImage data: Data) {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            self = Image(uiImage: ui)
        } else { return nil }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) {
            self = Image(nsImage: ns)
        } else { return nil }
        #else
        return nil
        #endif
    }
}
