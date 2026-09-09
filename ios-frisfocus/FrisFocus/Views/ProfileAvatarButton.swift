//
//  ProfileAvatarButton.swift
//  FrisFocus
//
//  Small 32 pt avatar disc that lives in the homepage's top-right
//  corner. Charcoal disc with cream initials by default, or the user's
//  photo if one is set. Always wears a thin warm-gold ring so it reads
//  as an interactive element against the Sun zone's painterly sky.
//
//  Stateless — the parent owns the action. Fires a light haptic on tap.
//

import SwiftUI
import UIKit

struct ProfileAvatarButton: View {
    let initials: String
    var photoURL: URL? = nil
    /// A small alert dot at the disc's top-trailing corner — unseen
    /// friend requests waiting behind the profile surfaces.
    var showDot: Bool = false
    let action: () -> Void

    /// The disc people see.
    private let discSize: CGFloat = 32
    /// The frame that actually receives touches. Apple's minimum is
    /// 44 pt and this button sits in the top-right corner, where a
    /// thumb arrives at an angle and misses are cheapest to cause.
    ///
    /// This used to be a 32 pt disc padded by +9 and then un-padded by
    /// -9, on the theory that negative padding buys a bigger tap target
    /// for free. It does not. Negative padding shrinks the view's
    /// LAYOUT frame while leaving the content drawn outside it, and
    /// SwiftUI's containers hit-test their children by layout frame —
    /// so every touch in that 9 pt ring landed on the HStack, not on
    /// the button. The real target was the 32 pt disc, twelve points
    /// under the minimum, in the hardest corner of the screen to hit.
    /// Reported twice as "I can't click the profile".
    private let tapSize: CGFloat = 44

    var body: some View {
        // Two layers, deliberately: the disc is pure picture and takes
        // no touches at all; the Button on top has a label that is
        // nothing but a clear 44pt hit surface. Nothing rendered inside
        // the disc — an image loader, a retry glyph, a gesture it
        // carries — can ever again stand between a touch and this
        // button's action.
        ZStack {
            disc
                .allowsHitTesting(false)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Log.app.debug("profile: avatar tap delivered")
                action()
            } label: {
                Color.clear
                    .frame(width: tapSize, height: tapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .frame(width: tapSize, height: tapSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showDot ? "Profile, new friend requests waiting" : "Profile")
        .accessibilityHint("Open profile, settings, and season management")
        .accessibilityIdentifier("profile.avatar")
        .accessibilityAddTraits(.isButton)
    }

    /// The disc people see: photo or initials, warm ring, alert dot.
    private var disc: some View {
        ZStack {
            if let photoURL {
                CachedImage(url: photoURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderDisc
                }
            } else {
                placeholderDisc
            }
        }
        .frame(width: discSize, height: discSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Theme.sunWarm, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if showDot {
                Circle()
                    .fill(Theme.alertRed)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.9), lineWidth: 1.2))
                    .offset(x: 1.5, y: -1.5)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private var placeholderDisc: some View {
        ZStack {
            Theme.textPrimary
            if initials.isEmpty {
                // Signed out — a quiet person glyph that reads as
                // "tap to sign in" rather than a stale initial.
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            } else {
                Text(initials)
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
        }
    }
}

#Preview {
    ZStack {
        Theme.skyMid.ignoresSafeArea()
        ProfileAvatarButton(initials: "J") {}
    }
}
