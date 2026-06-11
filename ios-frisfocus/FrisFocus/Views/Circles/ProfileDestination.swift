//
//  ProfileDestination.swift
//  FrisFocus
//
//  Anywhere a person's photo or name shows up, it should be a doorway
//  to their profile — never a dead end. This file centralises that:
//
//   • `ProfileTarget` — a friend, or the current user.
//   • `.profileDestination($target, store:)` — a view modifier that
//     presents the right surface: a friend opens the relationship hub
//     full-screen over the current view; `.me` opens the user's own
//     profile page (the friend-profile mirror with edit shortcuts).
//     Closing returns the user exactly where they were.
//   • `MemberListSheet` — a calm, tappable member list so overlapping
//     avatar clusters (and their "+N" overflow) can still reach every
//     person behind the stack.
//
//  `store` is passed explicitly into the modifier so the presented
//  surface keeps the shared environment even when it opens from inside
//  a nested sheet or cover.
//

import SwiftUI
import UIKit

/// A person whose profile can be opened from anywhere they appear.
/// `.friend` opens the relationship hub; `.me` opens the user's own
/// profile page.
enum ProfileTarget {
    case friend(Friend)
    case me
}

extension Store {
    /// Resolve a member id into something openable, or `nil` when the
    /// id is a circle-only member who isn't in the local friend graph
    /// (no profile to show).
    func profileTarget(forMemberId id: UUID) -> ProfileTarget? {
        if id == currentUserId { return .me }
        if let friend = friend(by: id) { return .friend(friend) }
        return nil
    }
}

/// Stable identity for the "me" branch so the profile sheet presents
/// and dismisses cleanly off a single `ProfileTarget?` binding.
private struct MeProfileMarker: Identifiable { let id: String = "me.profile" }

extension View {
    /// Presents the profile surface for `target`. A friend opens the
    /// hub full-screen over the current view; `.me` opens the user's
    /// own profile page the same way. Pass the owning view's `store`
    /// so the presented surface keeps the shared state even across
    /// nested sheets/covers.
    func profileDestination(_ target: Binding<ProfileTarget?>, store: Store) -> some View {
        let friendBinding = Binding<Friend?>(
            get: {
                if case .friend(let friend) = target.wrappedValue { return friend }
                return nil
            },
            set: { newValue in
                if newValue == nil, case .friend = target.wrappedValue {
                    target.wrappedValue = nil
                }
            }
        )
        let meBinding = Binding<MeProfileMarker?>(
            get: {
                if case .me = target.wrappedValue { return MeProfileMarker() }
                return nil
            },
            set: { newValue in
                if newValue == nil, case .me = target.wrappedValue {
                    target.wrappedValue = nil
                }
            }
        )
        return self
            .fullScreenCover(item: friendBinding) { friend in
                FriendDetailView(friend: friend)
                    .environment(store)
            }
            .fullScreenCover(item: meBinding) { _ in
                MyProfileView()
                    .environment(store)
            }
    }
}

// MARK: - Member list sheet

/// A calm list of the members behind an avatar cluster. Each row opens
/// that person's profile. Used by the "+N" overflow so people hidden
/// behind a stack stay reachable, and as a standalone way to browse a
/// group's people. Circle-only members not in the friend graph render
/// as a quiet, non-tappable row.
struct MemberListSheet: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var title: String = "Members"
    let memberIds: [UUID]
    /// Called once the sheet has dismissed, with the chosen person.
    let onSelect: (ProfileTarget) -> Void

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(memberIds, id: \.self) { id in
                            row(for: id)
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MEMBERS")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text(title)
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
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func row(for id: UUID) -> some View {
        let isUser = id == store.currentUserId
        let friend = store.friend(by: id)
        let target: ProfileTarget? = isUser ? .me : friend.map { ProfileTarget.friend($0) }
        let name = isUser ? "You" : (friend?.displayName ?? "Member")
        let initials = isUser ? (auth.user?.initials ?? "?") : (friend?.initials ?? "?")
        let color: Color = isUser
            ? Theme.textPrimary
            : (friend.map { Color(hex: $0.accentColorHex) } ?? Theme.textTertiary)

        Button {
            guard let target else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(target)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color)
                    Text(initials)
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 46, height: 46)
                .overlay {
                    if isUser {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [Theme.sunWarm, Theme.sunOuter],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                    }
                }

                Text(name)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if target != nil {
                    Image(systemName: "chevron.right")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
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
        .disabled(target == nil)
        .accessibilityLabel(isUser ? "You" : (target != nil ? "Open \(name)'s profile" : name))
    }
}
