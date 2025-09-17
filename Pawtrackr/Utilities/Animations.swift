//
//  Animations.swift
//  Pawtrackr
//
//  Centralized animation palette and common transitions.
//  Use these to keep motion consistent and respect reduce-motion automatically.
//

import SwiftUI

enum Animations {
    // Springs
    static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.8)
    static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let gentleSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)

    // Eases
    static let fastEaseOut = Animation.easeOut(duration: 0.20)
    static let ease = Animation.easeInOut(duration: 0.30)
    static let slowEase = Animation.easeInOut(duration: 0.45)

    // Transitions
    static let moveAndFade = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    static let slideUpFade = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    static let slideIn = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
}

extension View {
    /// Applies the animation if Reduce Motion is off; otherwise no animation.
    func animated(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ConditionalAnimation(animation: animation, value: value))
    }
}

private struct ConditionalAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

