//
//  InviteToCircleSheet.swift
//  FrisFocus
//
//  Invite more friends to an existing circle. Lists the friends who
//  aren't already in it, lets you pick several, and sends each an
//  invitation they choose to accept. Calm sheet styling to match the
//  rest of the circles surfaces.
//

import SwiftUI
import UIKit

struct InviteToCircleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let circleName: String
    let friends: [RemoteProfile]
    let existingMemberIds: Set<String>
    let onInvite: ([String]) -> Void

    @State private var selected: Set<String> = []

    private var invitable: [RemoteProfile] {
        friends.filter { !existingMemberIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if invitable.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(invitable) { friend in
                                friendRow(friend)
                            }
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }

            if !invitable.isEmpty {
                VStack {
                    Spacer()
                    sendButton
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("INVITE TO")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text(circleName)
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func friendRow(_ friend: RemoteProfile) -> some View {
        let isSelected = selected.contains(friend.id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected { selected.remove(friend.id) } else { selected.insert(friend.id) }
        } label: {
            HStack(spacing: 12) {
                RemoteAvatarView(profile: friend, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let handle = friend.handle {
                        Text(handle)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                }
                Spacer(minLength: 4)
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Color.clear)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : Theme.textPrimary.opacity(0.25), lineWidth: 1.5)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.sans(12, weight: .bold))
                            .foregroundStyle(Theme.textCream)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite \(friend.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sendButton: some View {
        Button {
            guard !selected.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onInvite(Array(selected))
            dismiss()
        } label: {
            Text(selected.isEmpty ? "Pick friends to invite" : "Send \(selected.count) invite\(selected.count == 1 ? "" : "s")")
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(selected.isEmpty ? Theme.textPrimary.opacity(0.35) : Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.bottom, 28)
        .padding(.top, 10)
        .background(
            LinearGradient(
                colors: [Theme.warmWheat.opacity(0), Theme.warmWheat],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.05)).frame(width: 64, height: 64)
                Image(systemName: "person.2")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            Text("Everyone's already here")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("All of your friends are already in this circle. Add more friends to invite them.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
