//
//  CircleCollectiveSection.swift
//  FrisFocus
//
//  The shared-number body for a local circle's detail page: one number
//  the group builds toward, an animated progress bar, and each member's
//  contribution. Used by Collective circles and the number half of a
//  Hybrid. Green-tinted so a "number" goal always reads as the number
//  goal — even sitting beside a violet shared list in a hybrid.
//
//  Read-only in the night-sky room (a calm lookback); live contribution
//  logging lives in the synced shared circles.
//

import SwiftUI

struct CircleCollectiveSection: View {
    @Environment(Store.self) private var store
    let circle: FFCircle

    /// The number goal always reads green so it's distinguishable from a
    /// violet shared list inside a hybrid.
    private let tint = CircleType.collective.tint
    private let tintDark = CircleType.collective.tintDark

    private var contributions: [CircleContribution] {
        store.circleContributions.filter { $0.circleId == circle.id }
    }

    private var loggedTotal: Double {
        contributions.reduce(0) { $0 + $1.amount }
    }

    /// Prefer the live contribution sum; fall back to the stored progress
    /// (e.g. a number resumed from dormancy before any new logs land).
    private var total: Double {
        loggedTotal > 0 ? loggedTotal : (circle.collectiveProgress ?? 0)
    }

    private var unit: String { circle.collectiveUnit ?? "" }

    private var fraction: Double {
        guard let target = circle.collectiveTarget, target > 0 else { return 0 }
        return min(1, total / target)
    }

    /// Members ranked by contribution (collective circles celebrate the
    /// shared total — this is contribution, not a witness ranking).
    private var ranked: [(id: UUID, amount: Double)] {
        let totals: [UUID: Double] = contributions.reduce(into: [:]) { acc, c in
            acc[c.memberId, default: 0] += c.amount
        }
        return circle.memberIds
            .map { (id: $0, amount: totals[$0] ?? 0) }
            .sorted { lhs, rhs in
                lhs.amount != rhs.amount ? lhs.amount > rhs.amount : nameFor(lhs.id) < nameFor(rhs.id)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            progressCard
            contributors
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The number")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("TOGETHER")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(tintDark.opacity(0.8))
        }
    }

    private var progressCard: some View {
        let pct = Int((fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(circleNumber(total))
                    .font(.serif(38, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.4), value: total)
                if let target = circle.collectiveTarget {
                    Text("/ \(circleNumber(target)) \(unit)")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                } else if !unit.isEmpty {
                    Text(unit)
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if circle.collectiveTarget != nil {
                CircleProgressBar(fraction: fraction, tint: tint, height: 12)
                HStack {
                    Text("\(pct)% there")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(tintDark)
                    Spacer()
                    Text("together so far")
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
        )
    }

    private var contributors: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ranked, id: \.id) { entry in
                contributorRow(memberId: entry.id, amount: entry.amount)
            }
        }
    }

    private func contributorRow(memberId: UUID, amount: Double) -> some View {
        let share = total > 0 ? amount / total : 0
        let isMe = memberId == store.currentUserId
        return HStack(spacing: 12) {
            avatar(for: memberId, isMe: isMe)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(isMe ? "You" : nameFor(memberId))
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(circleNumber(amount)) \(unit)")
                        .font(.sans(12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(amount > 0 ? Theme.textPrimary.opacity(0.7) : Theme.textPrimary.opacity(0.4))
                }
                CircleProgressBar(fraction: share, tint: tint, height: 6)
            }
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
        .opacity(amount > 0 ? 1 : 0.75)
    }

    @ViewBuilder
    private func avatar(for id: UUID, isMe: Bool) -> some View {
        ZStack {
            Circle().fill(isMe ? Theme.textPrimary : accentFor(id))
            Text(initialsFor(id, isMe: isMe))
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 32, height: 32)
        .overlay {
            if isMe {
                Circle().strokeBorder(
                    LinearGradient(colors: [Theme.sunWarm, Theme.sunOuter], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.6
                )
            } else {
                Circle().strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            }
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
