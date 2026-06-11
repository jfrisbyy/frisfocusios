//
//  FriendAvatarView.swift
//  FrisFocus
//
//  The one avatar for a local `Friend`: their saved profile photo when
//  they have one, otherwise the familiar initials disc on their accent
//  color. Every surface that shows a person — member stacks, cheers,
//  send-to pickers, threads, pacts, story viewers — renders through
//  this view so a saved photo appears everywhere at once.
//
//  Rings, gold "you" strokes, and size-specific chrome stay at the
//  call site; this view only owns the circle's contents.
//

import SwiftUI

struct FriendAvatarView: View {
    let friend: Friend?
    var size: CGFloat = 34
    /// Fallbacks for call sites that only carry denormalized identity
    /// (e.g. a cheer's stored initials) when the friend isn't resolvable.
    var fallbackInitials: String? = nil
    var fallbackColor: Color? = nil

    private var initialsText: String {
        friend?.initials ?? fallbackInitials ?? "?"
    }

    private var discColor: Color {
        if let friend { return Color(hex: friend.accentColorHex) }
        return fallbackColor ?? Theme.textTertiary
    }

    var body: some View {
        ZStack {
            if let url = friend?.avatarURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    disc
                }
            } else {
                disc
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var disc: some View {
        ZStack {
            Circle().fill(discColor)
            Text(initialsText)
                .font(.sans(max(9, size * 0.36), weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }
}
