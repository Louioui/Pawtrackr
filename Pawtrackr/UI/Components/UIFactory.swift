//
//  UIFactory.swift
//  Pawtrackr
//
//  Centralized UI component factory for consistent, theme-aware components.
//  Use these builders in views to reduce one-off styling.
//

import SwiftUI

enum UIFactory {
    // MARK: - Buttons
    static func primaryButton(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title, systemImage: systemImage)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(DS.ColorToken.primary))
                .foregroundStyle(.white)
        }
        .buttonStyle(PressScaleStyle())
    }

    static func secondaryButton(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title, systemImage: systemImage)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(DS.ColorToken.surface))
                .foregroundStyle(.primary)
                .hairlineBorder(DS.ColorToken.border, cornerRadius: DS.Radius.pill)
        }
        .buttonStyle(PressScaleStyle())
    }

    static func destructiveButton(_ title: String, systemImage: String? = "trash", action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            label(title, systemImage: systemImage)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color.red.opacity(0.12)))
                .foregroundStyle(.red)
                .hairlineBorder(Color.red.opacity(0.25), cornerRadius: DS.Radius.pill)
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - Avatars
    static func clientAvatar(name: String, imageData: Data? = nil, url: URL? = nil, size: AvatarView.Size = .md) -> some View {
        AvatarView(.client(name: name, imageData: imageData, imageURL: url), size: size)
    }

    static func petAvatar(name: String?, species: Species?, gender: PetGender?, imageData: Data? = nil, url: URL? = nil, size: AvatarView.Size = .md) -> some View {
        AvatarView(.pet(species: species, gender: gender, name: name, imageData: imageData, imageURL: url), size: size)
    }

    // MARK: - Rows & Accessories
    static func chevronAccessory() -> some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
    }

    static func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let s = systemImage { Image(systemName: s) }
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.clear)
    }

    // MARK: - Internal
    private static func label(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).font(.callout.weight(.semibold))
        }
        .contentShape(Rectangle())
    }
}

// Slight scale-down on press that defers to centralized Animations.
private struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : Animations.quickSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticManager.impact(.light)
                }
            }
    }
}

