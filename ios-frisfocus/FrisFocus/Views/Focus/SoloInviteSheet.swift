//
//  SoloInviteSheet.swift
//  FrisFocus
//
//  Invite one or more friends into a running solo focus session. Picking
//  friends here blossoms the lone tree into a shared grove without
//  interrupting the timer — the host swaps the solo cover for the grove
//  and the live focus session carries straight over.
//

import SwiftUI
import UIKit

struct SoloInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    /// Called with the chosen friend ids when the user confirms.
    let onInvite: ([UUID]) -> Void

    @State private var selectedFriendIds: Set<UUID> = []

    private let friendCap: Int = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pull friends into your focus. Your tree becomes a shared grove and theirs appear alongside it.")
                        .font(.serifItalic(14))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))

                    let candidates = store.sharedFocusInviteCandidates
                    if candidates.isEmpty {
                        Text("Add a friend first to focus together.")
                            .font(.serifItalic(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(candidates) { friend in
                                friendRow(friend)
                            }
                        }

                        Button(action: confirm) {
                            Text(selectedFriendIds.isEmpty ? "Pick someone" : "Start the grove")
                                .font(.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.warmWheat)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedFriendIds.isEmpty
                                              ? Theme.textPrimary.opacity(0.35)
                                              : Theme.textPrimary)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedFriendIds.isEmpty)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        let isCapped = !isSelected && selectedFriendIds.count >= friendCap
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggle(friend)
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 32)
                Text(friend.displayName)
                    .font(.serif(16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(isCapped ? 0.45 : 0.95))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.alertGreen.opacity(0.10) : Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCapped)
    }

    private func toggle(_ friend: Friend) {
        if selectedFriendIds.contains(friend.id) {
            selectedFriendIds.remove(friend.id)
        } else if selectedFriendIds.count < friendCap {
            selectedFriendIds.insert(friend.id)
        }
    }

    private func confirm() {
        guard !selectedFriendIds.isEmpty else { return }
        let ordered = store.sharedFocusInviteCandidates
            .map(\.id)
            .filter { selectedFriendIds.contains($0) }
        onInvite(ordered)
        dismiss()
    }
}
