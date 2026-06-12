//
//  MyAvatarDisc.swift
//  FrisFocus
//
//  The current user's avatar as a simple disc: their real profile
//  photo when one is set (ProfileStore first, then the identity
//  provider's picture), otherwise a charcoal disc with their real
//  initials. Ring/sizing are left to callers so the same disc works
//  in attendee stacks, story headers, and member rows.
//

import SwiftUI

struct MyAvatarDisc: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AuthManager.self) private var auth

    var size: CGFloat = 30
    /// Type scale for the initials fallback. Defaults to ~40% of size.
    var initialsSize: CGFloat? = nil

    private var photoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var initials: String {
        if let fromProfile = profileStore.myProfile?.initials,
           !fromProfile.isEmpty, fromProfile != "?" {
            return fromProfile
        }
        return auth.user?.initials ?? ""
    }

    var body: some View {
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("You")
    }

    @ViewBuilder
    private var placeholderDisc: some View {
        ZStack {
            Theme.textPrimary
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            } else {
                Text(initials)
                    .font(.sans(initialsSize ?? max(10, size * 0.4), weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
        }
    }
}
