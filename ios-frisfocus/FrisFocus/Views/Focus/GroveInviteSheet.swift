//
//  GroveInviteSheet.swift
//  FrisFocus
//
//  Add another friend to an already-running grove. Lists friends not yet
//  in the session (respecting the 3-friend cap); tapping one sends them
//  the join prompt and seeds a soft "waiting" tree in the grove until
//  they accept.
//

import SwiftUI
import UIKit

struct GroveInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pull a friend into the grove. They'll get a prompt to join, and a waiting tree appears for them until they do.")
                        .font(.serifItalic(14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))

                    let candidates = store.groveInvitableFriends
                    if candidates.isEmpty {
                        Text("No one left to invite right now — the grove's full.")
                            .font(.serifItalic(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(candidates) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Invite to grove")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friend: Friend) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.inviteFriendToActiveGrove(friend.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 32)
                Text(friend.displayName)
                    .font(.serif(16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
    }
}
