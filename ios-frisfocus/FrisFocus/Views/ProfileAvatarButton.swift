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
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                if let photoURL {
                    AsyncImage(url: photoURL) { image in
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
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Theme.sunWarm, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityHint("Open profile, settings, and season management")
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
