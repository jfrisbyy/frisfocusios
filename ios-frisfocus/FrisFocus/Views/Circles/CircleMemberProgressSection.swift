//
//  CircleMemberProgressSection.swift
//  FrisFocus
//
//  "The circle today" — per-member progress under a parallel circle's
//  detail page. One row per `circle.memberIds`, each carrying their
//  avatar (user gets the gold ring), a segmented bar with one slot per
//  `circle.tasks` filled in the member's accent colour, and a
//  `{done}/{total}` count on the right.
//
//  The scope (`Today` vs `Overall`) is owned by `CircleDetailView` and
//  passed in, so both this section and "The work" stay in agreement
//  about what time slice they're rendering. Quiet members (0 unique
//  tasks done in scope) dim slightly so the row reads as present, not
//  shamed.
//

import SwiftUI

// MARK: - Scope (shared with The work + Member progress)

/// Which time slice the parallel detail body is rendering. Owned by
/// `CircleDetailView`; surfaced to every body section so they all read
/// from the same underlying ledger window.
enum CircleScope: String, Hashable, CaseIterable {
    case today
    case overall
}

// MARK: - Section

struct CircleMemberProgressSection: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let scope: CircleScope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 4)

            Text(sublineText)
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(circle.memberIds, id: \.self) { memberId in
                    MemberProgressRow(
                        circle: circle,
                        memberId: memberId,
                        scope: scope
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The circle today")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text("\(circle.memberIds.count) PEOPLE")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private var sublineText: String {
        switch scope {
        case .today: return "who\u{2019}s done the work"
        case .overall: return "who\u{2019}s shown up across the whole run"
        }
    }
}

// MARK: - Row

private struct MemberProgressRow: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let memberId: UUID
    let scope: CircleScope

    private var isUser: Bool { memberId == store.currentUserId }

    private var displayName: String {
        if isUser { return "You" }
        return store.friend(by: memberId)?.displayName ?? "Member"
    }

    private var initials: String {
        if isUser { return "J" }
        return store.friend(by: memberId)?.initials ?? "?"
    }

    private var accentColor: Color {
        if isUser { return Theme.textPrimary }
        if let hex = store.friend(by: memberId)?.accentColorHex {
            return Color(hex: hex)
        }
        return Theme.textTertiary
    }

    /// Which task ids the member has completed in the current scope.
    /// Today = same-day completions; Overall = at-least-once across
    /// the circle's whole timeframe (we de-duplicate so multiple
    /// completions of the same task still read as a single segment).
    private var completedTaskIds: Set<UUID> {
        let cal = Calendar.current
        let today = Date()
        let matches = store.circleTaskCompletions.filter { c in
            guard c.circleId == circle.id, c.memberId == memberId else { return false }
            switch scope {
            case .today:
                return cal.isDate(c.date, inSameDayAs: today)
            case .overall:
                return true
            }
        }
        return Set(matches.map { $0.circleTaskId })
    }

    private var done: Int {
        completedTaskIds.intersection(Set(circle.tasks.map { $0.id })).count
    }

    private var total: Int { circle.tasks.count }

    private var isQuiet: Bool { done == 0 }

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 7) {
                Text(displayName)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)

                segmentedBar
            }

            Spacer(minLength: 8)

            countLabel
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
        .opacity(isQuiet ? 0.72 : 1)
    }

    @ViewBuilder
    private var avatar: some View {
        if isUser {
            ZStack {
                Circle().fill(Theme.textPrimary)
                Text(initials)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.6
                )
            )
        } else {
            ZStack {
                Circle().fill(accentColor)
                Text(initials)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private var segmentedBar: some View {
        let orderedIds = circle.tasks.map { $0.id }
        let completed = completedTaskIds
        let segments = max(orderedIds.count, 1)

        return HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { idx in
                let id = idx < orderedIds.count ? orderedIds[idx] : nil
                let filled = id.map { completed.contains($0) } ?? false
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(filled ? accentColor : Theme.textPrimary.opacity(0.1))
                    .frame(height: 6)
            }
        }
    }

    private var countLabel: some View {
        Text("\(done) of \(total)")
            .font(.sans(12, weight: .medium))
            .foregroundStyle(done == total && total > 0
                ? Theme.alertGreen
                : Theme.textPrimary.opacity(isQuiet ? 0.4 : 0.7))
            .monospacedDigit()
    }
}

#Preview {
    let store = Store()
    return ScrollView {
        if let parallel = store.circles.first(where: { $0.type == .parallel }) {
            CircleMemberProgressSection(circle: parallel, scope: .today)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 24)
        }
    }
    .background(Theme.warmWheat)
    .environment(store)
}
