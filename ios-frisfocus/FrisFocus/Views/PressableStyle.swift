//
//  PressableStyle.swift
//  FrisFocus
//
//  The app's one press language. Every primary tappable — nav items,
//  plan cards, chips, tiles — compresses slightly and dims under the
//  finger, then springs back on release. Touch is acknowledged in the
//  first frame, everywhere, identically.
//
//  Two flavors:
//   • .pressable      — chips, pills, small controls (0.94 scale)
//   • .pressableCard  — full-width cards and rows (0.975 scale, subtler)
//

import SwiftUI

/// Compress-and-dim for chips, pills, and small controls.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A subtler compress for full-width cards and rows — enough to feel,
/// never enough to wobble a reading surface.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// The shared chip/pill press effect.
    static var pressable: PressableStyle { PressableStyle() }
}

extension ButtonStyle where Self == PressableCardStyle {
    /// The shared card/row press effect.
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}
