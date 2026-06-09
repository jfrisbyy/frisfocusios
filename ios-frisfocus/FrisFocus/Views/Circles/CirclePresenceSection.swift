//
//  CirclePresenceSection.swift
//  FrisFocus
//
//  The body of a Witness circle: pure presence. A calm roster of who's
//  in the room and how they're showing up today — each member rendered
//  at the tier *they* share with you (Quiet / Open / Full), never a
//  group-wide level. No shared goal, no progress bar, and crucially no
//  ranking: a Witness circle is a room, not a scoreboard.
//

import SwiftUI
import UIKit

struct CirclePresenceSection: View {
    @Environment(Store.self) private var store
    let circle: FFCircle

    @State private var profileTarget: ProfileTarget?

    /// Self first, then everyone else in roster order — deliberately
    /// NOT sorted by any measure of activity.
    private var orderedMembers: [UUID] {
        let me = circle.memberIds.filter { $0 == store.currentUserId }
        let others = circle.memberIds.filter { $0 != store.currentUserId }
        return me + others
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 4)

            Text("Everyone's here, each on their own goals.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(orderedMembers, id: \.self) { memberId in
                    row(for: memberId)
                }
            }
        }
        .profileDestination($profileTarget, store: store)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("In the room")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(circle.memberIds.count) PRESENT")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private func row(for memberId: UUID) -> some View {
        let isMe = memberId == store.currentUserId
        let canOpen = store.profileTarget(forMemberId: memberId) != nil
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let target = store.profileTarget(forMemberId: memberId) {
                profileTarget = target
            }
        } label: {
            HStack(spacing: 12) {
                avatar(for: memberId, isMe: isMe)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMe ? "You" : nameFor(memberId))
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(presenceLine(for: memberId, isMe: isMe))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .accessibilityLabel("\(isMe ? "You" : nameFor(memberId)), \(presenceLine(for: memberId, isMe: isMe))")
    }

    /// The member's avatar wrapped in a calm progress ring rendered at
    /// the tier *they* share with you — full reads today's completion,
    /// open shows momentum, quiet stays a faint empty track. Never a
    /// ranking: rows keep roster order, the ring just gives a warm sense
    /// of how their day is going.
    private func avatar(for id: UUID, isMe: Bool) -> some View {
        DayProgressRing(
            fraction: ringFraction(for: id, isMe: isMe),
            tint: isMe ? Theme.sunOuter : accentFor(id),
            lineWidth: 2.5,
            trackOpacity: 0.16
        ) {
            ZStack {
                Circle().fill(isMe ? Theme.textPrimary : accentFor(id))
                Text(initialsFor(id, isMe: isMe))
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 34, height: 34)
        }
        .frame(width: 46, height: 46)
    }

    private func ringFraction(for id: UUID, isMe: Bool) -> Double {
        if isMe { return store.myTodayFraction }
        guard let friend = store.friend(by: id) else { return 0 }
        return store.dayRingFraction(for: friend)
    }

    // MARK: - Presence, per pairwise tier

    /// A warm, tier-appropriate line about how this person is showing up.
    /// Reuses the friend's `sharesWithMe` tier so the same room reads
    /// differently per relationship — never a group-wide level.
    private func presenceLine(for id: UUID, isMe: Bool) -> String {
        if isMe { return "Here today" }
        guard let friend = store.friend(by: id) else { return "In the room" }
        switch friend.sharesWithMe.tier {
        case .full:
            if let score = friend.todayScore { return "\(score) logged today" }
            if let hit = friend.hitGoalToday { return hit ? "Hit today\u{2019}s goal" : "Working toward today\u{2019}s goal" }
            return friend.currentSeasonName.map { "In \($0)" } ?? "Showing up"
        case .open:
            if let hit = friend.hitGoalToday { return hit ? "Hit today\u{2019}s goal" : "Working toward it" }
            if let name = friend.currentSeasonName { return "In \(name)" }
            return "Showing up"
        case .quiet:
            if let name = friend.currentSeasonName, let day = friend.currentSeasonDay {
                return "\(name) \u{00b7} day \(day)"
            }
            return "Quietly present"
        }
    }

    private func nameFor(_ id: UUID) -> String {
        id == store.currentUserId ? "You" : (store.friend(by: id)?.displayName ?? "Member")
    }

    private func initialsFor(_ id: UUID, isMe: Bool) -> String {
        isMe ? "J" : (store.friend(by: id)?.initials ?? "?")
    }

    private func accentFor(_ id: UUID) -> Color {
        if let hex = store.friend(by: id)?.accentColorHex { return Color(hex: hex) }
        return Theme.textTertiary
    }
}
