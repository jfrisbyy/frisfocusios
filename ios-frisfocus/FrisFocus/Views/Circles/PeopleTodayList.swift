//
//  PeopleTodayList.swift
//  FrisFocus
//
//  The "TODAY" list on the People page — every friend as a hairline-
//  divided row directly on the parchment. No cards. Privacy-first:
//
//   • Ring avatar (50 pt) — fills proportionally to how close they are
//     to their daily goal. Only the RATIO is ever shared. Goal reached
//     = full ring + a small ✓ badge; a private day = dashed neutral
//     ring with the whole row at ~65 % opacity.
//   • Status line — templated locally from data, never a model call,
//     and NEVER a point total: task counts, shape words, interaction
//     notices, or the quiet private line.
//   • Inline action — a season-color pill (Open / View) with a red dot
//     when something is waiting; a quiet outline chat glyph otherwise.
//
//  Witness-model calm: no rankings, no leaderboards, nothing red about
//  an unfinished day.
//

import SwiftUI
import UIKit

struct PeopleTodayList: View {
    @Environment(Store.self) private var store

    /// Open the friend's detail page (separate from story viewing).
    let onRowTap: (Friend) -> Void
    /// Open the 1:1 proof/message thread with this friend.
    let onActionTap: (Friend) -> Void

    var body: some View {
        VStack(spacing: 0) {
            labelRow
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 4)

            ForEach(Array(store.friends.enumerated()), id: \.element.id) { idx, friend in
                if idx > 0 {
                    hairline
                }
                PersonTodayRow(
                    friend: friend,
                    onTap: { onRowTap(friend) },
                    onActionTap: { onActionTap(friend) }
                )
            }
        }
    }

    private var labelRow: some View {
        HStack {
            Text("TODAY")
                .font(.sans(10.5, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Spacer()
            Text("\(store.friends.count) FRIENDS")
                .font(.sans(10.5, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.trailing, Theme.pageHorizontalPadding)
    }
}

// MARK: - One person, one row

private struct PersonTodayRow: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let friend: Friend
    let onTap: () -> Void
    let onActionTap: () -> Void

    @State private var ringFill: Double = 0

    private var accent: Color { Color(hex: friend.accentColorHex) }
    private var tier: VisibilityTier { friend.sharesWithMe.tier }
    private var day: FriendDay { store.friendDay(for: friend) }

    /// A quiet tier reads as a fully private day — dashed ring, row
    /// dimmed, the season line and nothing more.
    private var isPrivateDay: Bool { tier == .quiet }

    private var goalReached: Bool {
        friend.hitGoalToday == true || store.dayRingFraction(for: friend) >= 0.999
    }

    private var unread: Int { store.unreadCount(fromFriendId: friend.id) }
    private var latestUnread: DirectShare? { store.latestUnread(fromFriendId: friend.id) }
    private var hasProofUnread: Bool { latestUnread?.isProof == true }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 14) {
                    ringAvatar
                    identityBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName), \(statusText)")

            actionAffordance
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.vertical, 14)
        .opacity(isPrivateDay ? 0.65 : 1)
        .onAppear {
            let target = isPrivateDay ? 0 : min(1, store.dayRingFraction(for: friend))
            if reduceMotion {
                ringFill = target
            } else {
                withAnimation(.easeOut(duration: 0.4)) { ringFill = target }
            }
        }
    }

    // MARK: Ring avatar

    private var ringAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if isPrivateDay {
                    Circle()
                        .strokeBorder(
                            Theme.textPrimary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.6, dash: [3.5, 3])
                        )
                } else {
                    Circle()
                        .strokeBorder(accent.opacity(0.15), lineWidth: 2.6)
                    Circle()
                        .trim(from: 0, to: goalReached ? 1 : ringFill)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.3)
                }

                RefinedAvatarDisc(
                    accent: accent,
                    initials: friend.initials,
                    avatarURL: friend.avatarURL,
                    size: 40,
                    initialsSize: 15
                )
            }
            .frame(width: 50, height: 50)

            if goalReached && !isPrivateDay {
                ZStack {
                    Circle()
                        .fill(Theme.alertGreen)
                        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.6))
                    Image(systemName: "checkmark")
                        .font(.sans(7.5, weight: .bold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 15, height: 15)
                .offset(x: 1, y: 1)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(ringAccessibility)
    }

    private var ringAccessibility: String {
        if isPrivateDay { return "\(friend.displayName), private day" }
        if goalReached { return "\(friend.displayName), reached their goal" }
        return "\(friend.displayName), partway to their goal"
    }

    // MARK: Identity + status

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(friend.displayName)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let meta = seasonMeta {
                    Text(meta)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Text(statusText)
                .font(.sans(12.5, weight: hasNotice ? .medium : .regular))
                .foregroundStyle(hasNotice ? accent : Theme.textPrimary.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var seasonMeta: String? {
        guard let full = friend.currentSeasonName else { return nil }
        let short = full.replacingOccurrences(of: " Season", with: "")
        guard let dayN = friend.currentSeasonDay else { return short }
        return "\(short) · day \(dayN)"
    }

    private var hasNotice: Bool { latestUnread != nil }

    /// The privacy-safe status line — templated entirely from local
    /// data. Never a point total, never a target as a number.
    private var statusText: String {
        if let u = latestUnread {
            let kind = u.isProof ? "proof" : "note"
            return "Sent you a \(kind) · \(PeopleRowFormat.shortElapsed(from: u.createdAt))"
        }
        if isPrivateDay {
            return "In their season, quietly"
        }
        if goalReached {
            return "Reached their goal ✓"
        }
        switch tier {
        case .full:
            return "\(day.doneCount) of \(day.totalCount) done today"
        case .open:
            if day.momentum < 0.3 { return "Just getting going" }
            return "Showing up · \(day.rhythmSummary)"
        case .quiet:
            return "In their season, quietly"
        }
    }

    // MARK: Inline action

    @ViewBuilder
    private var actionAffordance: some View {
        if unread > 0 {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onActionTap()
            } label: {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        Image(systemName: hasProofUnread ? "camera.fill" : "bubble.left.fill")
                            .font(.sans(11.5, weight: .semibold))
                        Text(hasProofUnread ? "View" : "Open")
                            .font(.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(Capsule(style: .continuous).fill(accent))
                    .shadow(color: accent.opacity(0.35), radius: 7, x: 0, y: 3)

                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasProofUnread
                ? "View proof from \(friend.displayName)"
                : "Open message from \(friend.displayName)")
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onActionTap()
            } label: {
                Image(systemName: "bubble.left")
                    .font(.sans(16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message \(friend.displayName)")
        }
    }
}

// MARK: - Row formatting

enum PeopleRowFormat {
    /// "just now", "5m", "2h", "1d" — the compact elapsed form used in
    /// row notices ("Sent you a proof · 1d").
    static func shortElapsed(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

#Preview {
    ScrollView {
        PeopleTodayList(onRowTap: { _ in }, onActionTap: { _ in })
            .environment(Store())
    }
    .background(Theme.warmWheat)
}
