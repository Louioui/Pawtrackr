//
//  IconCircle.swift
//  Pawtrackr
//
//  Reusable circular icon with configurable size, sources (SF Symbol, initials, photo),
//  gender-aware tinting, optional badge, and strong accessibility defaults.
//  Updated to fix conditional-compilation init issues, return-path issues in @ViewBuilder,
//  and to support cross‑platform image decoding.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct IconCircle: View {
    // MARK: - Types

    enum SizeToken {
        case xs, sm, md, lg
        case custom(CGFloat)

        /// Convenience to create a size token from an explicit pixel dimension.
        static func px(_ value: CGFloat) -> SizeToken { .custom(value) }

        var dimension: CGFloat {
            switch self {
            case .xs: return 24
            case .sm: return 32
            case .md: return 40
            case .lg: return 56
            case .custom(let px): return px
            }
        }
        /// Fraction of the circle dimension used for the inner glyph (symbol/initials).
        var iconScale: CGFloat {
            switch self {
            case .xs: return 0.46
            case .sm: return 0.44
            case .md: return 0.42
            case .lg: return 0.40
            case .custom(let px):
                // Interpolate between 24pt→0.46 and 56pt→0.40 for sensible scaling at arbitrary sizes.
                let minD: CGFloat = 24
                let maxD: CGFloat = 56
                let t = max(0, min(1, (px - minD) / (maxD - minD)))
                return 0.46 - (0.06 * t)
            }
        }
        var fontWeight: Font.Weight {
            switch self {
            case .lg: return .semibold
            case .xs, .sm, .md: return .medium
            case .custom(let px): return px >= 56 ? .semibold : .medium
            }
        }
    }

    enum Style: Equatable {
        case solid(Color, Color)                          // bg, foreground
        case tinted(Color)                                // bg with white fg
        case auto(species: Species?, gender: PetGender?)  // DS-driven tint
    }

    // MARK: - Inputs

    private let systemImage: String?
    private let initials: String?
    private let imageData: Data?
    private let imageURL: URL? // Always present to avoid conditional-init mismatches
    private let sizeToken: SizeToken
    private let style: Style
    private let lineWidth: CGFloat
    private let badgeSystemImage: String?
    private let badgeColor: Color?
    private let accessibilityLabel: String?

    // MARK: - Init

    init(systemImage: String? = nil,
         initials: String? = nil,
         imageData: Data? = nil,
         imageURL: URL? = nil,
         size: SizeToken = .md,
         style: Style = .tinted(Color.blue.opacity(0.15)),
         lineWidth: CGFloat = 0,
         badgeSystemImage: String? = nil,
         badgeColor: Color? = nil,
         accessibilityLabel: String? = nil) {
        self.systemImage = systemImage
        self.initials = IconCircle.makeInitials(from: initials)
        self.imageData = imageData
        self.imageURL = imageURL
        self.sizeToken = size
        self.style = style
        self.lineWidth = lineWidth
        self.badgeSystemImage = badgeSystemImage
        self.badgeColor = badgeColor
        self.accessibilityLabel = accessibilityLabel
    }

    // MARK: - Body

    var body: some View {
        let dim = sizeToken.dimension
        let (bg, fg) = colors(for: style)

        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(bg)
                .overlay(
                    Circle().strokeBorder(fg.opacity(lineWidth > 0 ? 0.25 : 0), lineWidth: lineWidth)
                )
                .frame(width: dim, height: dim)
                .overlay(glyph(foreground: fg, dimension: dim))
                .contentShape(Circle())

            if let badgeSystemImage {
                badge(fg: fg, dim: dim, systemImage: badgeSystemImage)
            } else if let badgeColor {
                badgeDot(color: badgeColor, dim: dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? defaultAXLabel))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - Glyph Content

    @ViewBuilder
    private func glyph(foreground fg: Color, dimension dim: CGFloat) -> some View {
        // 1) Remote image via URL (AsyncImage)
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .frame(width: dim, height: dim)
                        .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                case .empty:
                    ProgressView().scaleEffect(0.6)
                case .failure:
                    fallbackGlyph(fg: fg, dim: dim)
                @unknown default:
                    fallbackGlyph(fg: fg, dim: dim)
                }
            }
        }
        // 2) Image from raw Data (platform-aware decode)
        else if let image = imageFromData(imageData) {
            image
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .frame(width: dim, height: dim)
                .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
        }
        // 3) Initials
        else if let initials = initials, !initials.isEmpty {
            Text(initials)
                .font(.system(size: dim * sizeToken.iconScale, weight: sizeToken.fontWeight, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(fg)
        }
        // 4) SF Symbol
        else if let systemImage = systemImage {
            Image(systemName: systemImage)
                .font(.system(size: dim * sizeToken.iconScale, weight: .semibold))
                .foregroundStyle(fg)
        }
        // 5) Fallback
        else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: dim * sizeToken.iconScale, weight: .semibold))
                .foregroundStyle(fg)
        }
    }

    @ViewBuilder
    private func fallbackGlyph(fg: Color, dim: CGFloat) -> some View {
        if let initials = initials, !initials.isEmpty {
            Text(initials)
                .font(.system(size: dim * sizeToken.iconScale, weight: sizeToken.fontWeight, design: .rounded))
                .foregroundStyle(fg)
        } else if let systemImage = systemImage {
            Image(systemName: systemImage)
                .font(.system(size: dim * sizeToken.iconScale, weight: .semibold))
                .foregroundStyle(fg)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: dim * sizeToken.iconScale, weight: .semibold))
                .foregroundStyle(fg)
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private func badge(fg: Color, dim: CGFloat, systemImage: String) -> some View {
        let badgeDim = max(14, dim * 0.36)
        ZStack {
            Circle().fill(Color.white.opacity(0.95)).shadow(radius: 0.5, x: 0, y: 0)
            Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            Image(systemName: systemImage)
                .font(.system(size: badgeDim * 0.55, weight: .bold))
                .foregroundStyle(fg)
        }
        .frame(width: badgeDim, height: badgeDim)
        .offset(x: dim * 0.08, y: dim * 0.08)
    }

    @ViewBuilder
    private func badgeDot(color: Color, dim: CGFloat) -> some View {
        let badgeDim = max(10, dim * 0.22)
        Circle()
            .fill(color)
            .frame(width: badgeDim, height: badgeDim)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .offset(x: dim * 0.08, y: dim * 0.08)
    }

    // MARK: - Colors

    private func colors(for style: Style) -> (Color, Color) {
        switch style {
        case let .solid(bg, fg):
            return (bg, fg)
        case let .tinted(bg):
            return (bg, .white)
        case let .auto(species: _, gender: gender):
            // Pull from DS; fall back to system colors if DS is unavailable
            #if canImport(SwiftUI)
            let tint = DS.ColorToken.gender(gender ?? .unknown)
            #else
            let tint = Color.blue
            #endif
            return (tint.opacity(0.15), tint)
        }
    }

    // MARK: - AX

    private var defaultAXLabel: String {
        if let accessibilityLabel { return accessibilityLabel }
        if let initials, !initials.isEmpty { return initials }
        if let systemImage { return systemImage.replacingOccurrences(of: ".", with: " ") }
        return "avatar"
    }

    // MARK: - Image decode helper

    private func imageFromData(_ data: Data?) -> Image? {
        guard let data = data else { return nil }
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        #if canImport(AppKit)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }
}

// MARK: - Pet Convenience

extension IconCircle {
    /// Pet-specific convenience (gender-tinted; symbol varies by species)
    init(species: Species, gender: PetGender, size: SizeToken = .md, badge: String? = nil) {
        let sys = (species == .cat) ? "pawprint.circle.fill" : "pawprint.fill"
        self.init(systemImage: sys,
                  initials: nil,
                  imageData: nil,
                  imageURL: nil,
                  size: size,
                  style: .auto(species: species, gender: gender),
                  lineWidth: 0,
                  badgeSystemImage: badge,
                  badgeColor: nil,
                  accessibilityLabel: "Pet avatar")
    }
}

// MARK: - Utilities

extension IconCircle {
    /// Build safe initials from any name (multilingual & whitespace aware)
    static func makeInitials(from name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let parts = name.split(separator: " ").prefix(2)
        let scalars = parts.compactMap { $0.unicodeScalars.first }.map(Character.init)
        let letters = scalars.map { String($0) }.joined()
        return letters.uppercased()
    }
}

// MARK: - Preview

struct IconCircle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                IconCircle(systemImage: "plus")
                IconCircle(systemImage: "scissors", style: .tinted(Color.purple.opacity(0.15)))
                IconCircle(systemImage: "pawprint.fill", style: .solid(.white, .blue))
                IconCircle(species: .dog, gender: .male)
                IconCircle(species: .cat, gender: .female)
            }
            HStack(spacing: 16) {
                IconCircle(initials: "Bella Luna", size: .lg, style: .tinted(Color.pink.opacity(0.2)), badgeSystemImage: "checkmark.seal.fill")
                IconCircle(systemImage: "camera.fill", size: .sm, badgeColor: .green)
                IconCircle(systemImage: "pawprint.fill", size: .xs)
            }
        }
        .padding()
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemGroupedBackground))
        #endif
        .previewLayout(.sizeThatFits)
    }
}
