//
//  CirclesGroupsSection.swift
//  FrisFocus
//
//  The "Your circles" section that sits below the Friends section on
//  the Circles page. Two distinct card treatments — parallel circles
//  show per-task segments and a story strip footer; collective
//  circles show a single wide progress bar against a shared target.
//  A dashed start/join row closes the section.
//
//  Reads `store.circles`, `store.circleTaskCompletions`,
//  `store.circleContributions`, and `store.storyPosts` so cards stay
//  in sync with the underlying graph without hand-rolled caching.
//
//  C3d wired this section's interactions: the parent owns the expand /
//  collapse state and supplies callbacks for the header, each card,
//  the parallel story strip, and the start/join row. The section never
//  decides where a tap goes — it only reports which thing the user
//  reached for.
//

import SwiftUI
import UIKit

struct CirclesGroupsSection: View {
    @Environment(Store.self) private var store

    @Binding var isExpanded: Bool
    /// Namespace for the group-story zoom transition — the player grows
    /// out of the tapped story strip and shrinks back into it.
    var zoomNamespace: Namespace.ID? = nil
    let onHeaderTap: () -> Void
    let onCircleTap: (FFCircle) -> Void
    let onStoryStripTap: (FFCircle) -> Void
    let onStartJoinTap: () -> Void
    /// A pact is a circle of two — surfaced here alongside circles.
    var onPactTap: ((Pact) -> Void)? = nil
    /// Open the public-circles directory.
    var onDiscoverTap: (() -> Void)? = nil

    /// Active + pending pacts the user is in, shown as two-person
    /// circle cards in this same section.
    private var activePacts: [Pact] {
        store.myPacts.filter { $0.status == .active || $0.status == .pending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            divider
                .padding(.top, 22)
                .padding(.horizontal, Theme.pageHorizontalPadding)

            header
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 18)

            if isExpanded {
                content
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    // MARK: - Divider + header

    private var divider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.1))
            .frame(height: 0.5)
    }

    private var header: some View {
        Button(action: onHeaderTap) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text("Your circles")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Image(systemName: "chevron.down")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }

                Spacer()

                Text("\(store.circles.count + activePacts.count) ACTIVE")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your circles, \(store.circles.count + activePacts.count) active")
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.circles.isEmpty && activePacts.isEmpty {
            VStack(spacing: 12) {
                Text("No circles yet — start one with a friend")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                startJoinRow
                discoverRow
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.circles) { circle in
                    Group {
                        switch circle.type {
                        case .witness:
                            WitnessCircleCard(
                                circle: circle,
                                onTap: { onCircleTap(circle) }
                            )
                        case .parallel:
                            ParallelCircleCard(
                                circle: circle,
                                zoomNamespace: zoomNamespace,
                                onTap: { onCircleTap(circle) },
                                onStoryStripTap: { onStoryStripTap(circle) }
                            )
                        case .collective:
                            CollectiveCircleCard(
                                circle: circle,
                                onTap: { onCircleTap(circle) }
                            )
                        case .hybrid:
                            HybridCircleCard(
                                circle: circle,
                                onTap: { onCircleTap(circle) }
                            )
                        }
                    }
                }

                // Pacts — a circle of two, rendered alongside circles.
                ForEach(activePacts) { pact in
                    PactCircleCard(pact: pact, onTap: { onPactTap?(pact) })
                }

                startJoinRow
                    .padding(.top, 4)

                discoverRow
            }
        }
    }

    // MARK: - Start / join

    private var startJoinRow: some View {
        Button(action: onStartJoinTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.sans(13, weight: .semibold))
                Text("Start a circle or join one")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a circle or join one")
    }

    /// Quiet text row into the public directory — deliberately lighter
    /// than the dashed start/join row so it reads as a side door.
    @ViewBuilder
    private var discoverRow: some View {
        if let onDiscoverTap {
            Button(action: onDiscoverTap) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.sans(12, weight: .medium))
                    Text("Discover public circles")
                        .font(.sans(13, weight: .regular))
                    Image(systemName: "chevron.right")
                        .font(.sans(10, weight: .semibold))
                        .opacity(0.6)
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discover public circles")
        }
    }
}

// MARK: - Shared helpers

private enum CirclesSectionHelpers {
    /// Days remaining between now and the time-boxed end date. Negative
    /// values clamp to zero so a just-expired circle reads as "0 days
    /// left" rather than a negative count while data hasn't archived yet.
    static func daysLeft(until endDate: Date, from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfEnd = cal.startOfDay(for: endDate)
        let comps = cal.dateComponents([.day], from: startOfToday, to: startOfEnd)
        return max(0, comps.day ?? 0)
    }

    /// Renders the eyebrow line above each card name. Time-boxed circles
    /// surface the countdown; ongoing circles say so explicitly.
    static func eyebrowText(typeLabel: String, timeframe: CircleTimeframe) -> String {
        switch timeframe {
        case .timeBoxed(let endDate):
            let days = daysLeft(until: endDate)
            let suffix = days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT"
            return "\(typeLabel) · \(suffix)"
        case .ongoing:
            return "\(typeLabel) · ONGOING"
        }
    }
}

// MARK: - Header photo banner

/// A circle's shared header photo as a banner across the top of its
/// list card — a soft bottom gradient keeps whatever sits below it
/// reading cleanly. Only rendered when the circle has a header set.
/// Tall enough (and top-aligned) that the banner shows a faithful
/// window of the framed header instead of a thin over-zoomed slice.
private struct CircleCardHeaderBanner: View {
    let url: URL

    var body: some View {
        Theme.textPrimary.opacity(0.08)
            .frame(height: 124)
            .overlay {
                CachedImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(ProfileHeaderCropView.aspect, contentMode: .fill)
                } placeholder: {
                    Theme.textPrimary.opacity(0.08)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.10), location: 0.7),
                        .init(color: Color.black.opacity(0.22), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Member avatar stack

/// Compact overlapping stack of member discs. The user's avatar gets a
/// gold ring so it reads as "you" in every group. When `memberIds`
/// exceed `maxVisible`, a soft grey "+N" pill closes the stack.
private struct MemberAvatarStack: View {
    @Environment(Store.self) private var store
    let memberIds: [UUID]
    let maxVisible: Int
    var diameter: CGFloat = 24
    var overlap: CGFloat = 7

    /// The member whose profile is open, if any.
    @State private var profileTarget: ProfileTarget?
    /// Drives the "+N" overflow members list.
    @State private var showMembers: Bool = false
    /// Person chosen in the members list, opened once it dismisses so
    /// the profile cover doesn't fight the sheet's animation.
    @State private var pendingTarget: ProfileTarget?

    var body: some View {
        let visible = Array(memberIds.prefix(maxVisible))
        let remainder = max(0, memberIds.count - visible.count)

        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.element) { _, id in
                memberAvatar(for: id)
            }

            if remainder > 0 {
                overflowButton(remainder)
                    .zIndex(Double(visible.count + 1))
            }
        }
        .sheet(isPresented: $showMembers, onDismiss: {
            if let pendingTarget {
                self.pendingTarget = nil
                profileTarget = pendingTarget
            }
        }) {
            MemberListSheet(memberIds: memberIds) { target in
                pendingTarget = target
                showMembers = false
            }
            .environment(store)
        }
        .profileDestination($profileTarget, store: store)
    }

    /// Wraps a member disc in a tap target that opens their profile.
    /// Circle-only members not in the friend graph stay non-interactive.
    @ViewBuilder
    private func memberAvatar(for id: UUID) -> some View {
        if let target = store.profileTarget(forMemberId: id) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                profileTarget = target
            } label: {
                avatar(for: id)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(id == store.currentUserId ? "Open your profile" : "Open \(store.friend(by: id)?.displayName ?? "member")'s profile")
        } else {
            avatar(for: id)
        }
    }

    private func overflowButton(_ count: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMembers = true
        } label: {
            overflowPill(count)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) more members")
    }

    @ViewBuilder
    private func avatar(for id: UUID) -> some View {
        if id == store.currentUserId {
            ZStack {
                Circle().fill(Theme.textPrimary)
                Text("J")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.sunWarm, Theme.sunOuter],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.6
                    )
            )
            .overlay(Circle().strokeBorder(Theme.warmWheat.opacity(0.6), lineWidth: 0.5).padding(0.8))
        } else if let friend = store.friend(by: id) {
            FriendAvatarView(friend: friend, size: diameter)
                .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.2))
        } else {
            ZStack {
                Circle().fill(Theme.textTertiary)
            }
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.2))
        }
    }

    private func overflowPill(_ count: Int) -> some View {
        ZStack {
            Circle().fill(Theme.textPrimary.opacity(0.12))
            Text("+\(count)")
                .font(.sans(10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.2))
    }
}

// MARK: - Parallel circle card

private struct ParallelCircleCard: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    var zoomNamespace: Namespace.ID? = nil
    let onTap: () -> Void
    let onStoryStripTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                VStack(spacing: 0) {
                    if let url = circle.headerURL {
                        CircleCardHeaderBanner(url: url)
                    }
                    mainBlock
                        .padding(.horizontal, 14)
                        .padding(.top, 13)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasStoryToday {
                storyStrip
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var mainBlock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CirclesSectionHelpers.eyebrowText(typeLabel: "PARALLEL", timeframe: circle.timeframe))
                        .font(.sans(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))

                    Text(circle.name)
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer()

                MemberAvatarStack(memberIds: circle.memberIds, maxVisible: 4)
            }

            youTodayRow
        }
    }

    private var youTodayRow: some View {
        let total = max(circle.tasks.count, 1)
        let done = userCompletionsToday
        let segments = circle.tasks.count

        return HStack(spacing: 10) {
            Text("You today")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))

            HStack(spacing: 4) {
                ForEach(0..<max(segments, 1), id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(idx < done ? Theme.alertGreen : Theme.textPrimary.opacity(0.1))
                        .frame(height: 7)
                }
            }
            .frame(maxWidth: .infinity)

            Text("\(done)/\(total)")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .monospacedDigit()
        }
    }

    private var storyStrip: some View {
        Button(action: onStoryStripTap) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.sans(10, weight: .bold))
                    .foregroundStyle(Theme.sunShadow)

                Text(storyStripCopy)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(red: 216.0/255, green: 125.0/255, blue: 68.0/255).opacity(0.08)
            )
            .overlay(
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.06))
                    .frame(height: 0.5),
                alignment: .top
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Theme.cardCornerRadius,
                bottomTrailingRadius: Theme.cardCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .zoomSource(id: "circlestory-\(circle.id.uuidString)", in: zoomNamespace)
    }

    // MARK: - Derived

    /// Distinct members (other than the user) with at least one circle
    /// clip for this circle today. The strip surfaces a count of how
    /// many people "ran today" — the phrasing is generic but the source
    /// of truth is whoever posted a clip.
    private var clipMembersToday: [UUID] {
        let cal = Calendar.current
        let today = Date()
        let ids = store.storyPosts
            .filter { post in
                guard post.circleId == circle.id else { return false }
                return cal.isDate(post.createdAt, inSameDayAs: today)
            }
            .map { $0.authorId }
        return Array(Set(ids))
    }

    private var hasStoryToday: Bool { !clipMembersToday.isEmpty }

    private var storyStripCopy: String {
        let count = clipMembersToday.count
        let verb = count == 1 ? "ran today" : "ran today"
        return "\(count) \(verb) · watch the story"
    }

    private var userCompletionsToday: Int {
        let cal = Calendar.current
        let today = Date()
        return store.circleTaskCompletions.filter { completion in
            completion.circleId == circle.id
                && completion.memberId == store.currentUserId
                && cal.isDate(completion.date, inSameDayAs: today)
        }.count
    }
}

// MARK: - Collective circle card

private struct CollectiveCircleCard: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                if let url = circle.headerURL {
                    CircleCardHeaderBanner(url: url)
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CirclesSectionHelpers.eyebrowText(typeLabel: "COLLECTIVE", timeframe: circle.timeframe))
                                .font(.sans(10, weight: .medium))
                                .tracking(2)
                                .foregroundStyle(Theme.textPrimary.opacity(0.55))

                            Text(circle.name)
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        Spacer()

                        MemberAvatarStack(memberIds: orderedMemberIdsByContribution, maxVisible: 1)
                    }

                    togetherRow
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var togetherRow: some View {
        let progress = circle.collectiveProgress ?? 0
        let target = circle.collectiveTarget ?? 1
        let fraction = max(0, min(1, progress / max(target, 0.0001)))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Together")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))

                Spacer()

                Text(progressLabel)
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.alertGreen)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }

    private var progressLabel: String {
        let progress = circle.collectiveProgress ?? 0
        let target = circle.collectiveTarget ?? 0
        let unitShort = (circle.collectiveUnit ?? "")
            .replacingOccurrences(of: "miles", with: "mi")
        let progressStr = formatted(progress)
        let targetStr = formatted(target)
        if unitShort.isEmpty {
            return "\(progressStr) of \(targetStr)"
        }
        return "\(progressStr) of \(targetStr) \(unitShort)"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// For collective circles we'd like the visible avatar to be the
    /// top contributor today (or all-time) so the stack tells a small
    /// story about who's carrying the group. Falls back to the original
    /// `memberIds` order when nobody has contributed yet.
    private var orderedMemberIdsByContribution: [UUID] {
        let totals: [UUID: Double] = store.circleContributions
            .filter { $0.circleId == circle.id }
            .reduce(into: [:]) { acc, contribution in
                acc[contribution.memberId, default: 0] += contribution.amount
            }
        if totals.isEmpty { return circle.memberIds }
        return circle.memberIds.sorted { lhs, rhs in
            (totals[lhs] ?? 0) > (totals[rhs] ?? 0)
        }
    }
}

// MARK: - Witness circle card

/// A presence-only circle: no goal, no progress bar. Just the people in
/// the room and a calm line. Warm amber/gold cue so it reads as a
/// Witness circle at a glance.
private struct WitnessCircleCard: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let onTap: () -> Void

    private let tint = CircleType.witness.tint
    private let tintDark = CircleType.witness.tintDark

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                if let url = circle.headerURL {
                    CircleCardHeaderBanner(url: url)
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CirclesSectionHelpers.eyebrowText(typeLabel: "WITNESS", timeframe: circle.timeframe))
                                .font(.sans(10, weight: .medium))
                                .tracking(2)
                                .foregroundStyle(tintDark.opacity(0.9))
                            Text(circle.name)
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        MemberAvatarStack(memberIds: circle.memberIds, maxVisible: 4)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(tint)
                        Text("Just present · everyone on their own goals")
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Witness circle: \(circle.name)")
    }
}

// MARK: - Hybrid circle card

/// A two-goal circle: a shared list AND a shared number, shown as two
/// compact rows so it reads clearly as carrying both. Teal cue marks it
/// as a hybrid; the list stays violet and the number stays green within.
private struct HybridCircleCard: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let onTap: () -> Void

    private let tintDark = CircleType.hybrid.tintDark

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                if let url = circle.headerURL {
                    CircleCardHeaderBanner(url: url)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CirclesSectionHelpers.eyebrowText(typeLabel: "HYBRID", timeframe: circle.timeframe))
                                .font(.sans(10, weight: .medium))
                                .tracking(2)
                                .foregroundStyle(tintDark.opacity(0.9))
                            Text(circle.name)
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        MemberAvatarStack(memberIds: circle.memberIds, maxVisible: 4)
                    }
                    listRow
                    numberRow
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(CircleType.hybrid.tint.opacity(0.25), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hybrid circle: \(circle.name)")
    }

    private var listRow: some View {
        let total = max(circle.tasks.count, 1)
        let segments = circle.tasks.count
        let done = userCompletionsToday
        return HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(CircleType.parallel.tintDark)
            HStack(spacing: 4) {
                ForEach(0..<max(segments, 1), id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(idx < done ? CircleType.parallel.tint : Theme.textPrimary.opacity(0.1))
                        .frame(height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            Text("\(done)/\(total)")
                .font(.sans(12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
    }

    private var numberRow: some View {
        let progress = circle.collectiveProgress ?? 0
        let target = circle.collectiveTarget ?? 1
        let fraction = max(0, min(1, progress / max(target, 0.0001)))
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(CircleType.collective.tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.sans(10, weight: .semibold))
                    .foregroundStyle(CircleType.collective.tintDark)
                Text(numberLabel)
                    .font(.sans(11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                Spacer(minLength: 0)
            }
        }
    }

    private var numberLabel: String {
        let p = circle.collectiveProgress ?? 0
        let t = circle.collectiveTarget ?? 0
        let unit = (circle.collectiveUnit ?? "").replacingOccurrences(of: "miles", with: "mi")
        return "\(circleNumber(p)) of \(circleNumber(t)) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    private var userCompletionsToday: Int {
        let cal = Calendar.current
        let today = Date()
        return store.circleTaskCompletions.filter { c in
            c.circleId == circle.id
                && c.memberId == store.currentUserId
                && cal.isDate(c.date, inSameDayAs: today)
        }.count
    }
}

// MARK: - Pact circle card

/// A pact is a circle of two. It mirrors the circle card's shape with a
/// distinct "JUST YOU TWO" framing so it reads as a pact while living in
/// the same section. Taps open the pact's detail.
private struct PactCircleCard: View {
    @Environment(Store.self) private var store
    let pact: Pact
    let onTap: () -> Void

    private var pactTint: Color { Theme.categorySpiritual }

    private var partnerId: UUID {
        pact.proposerId == store.currentUserId ? pact.partnerId : pact.proposerId
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eyebrow)
                            .font(.sans(10, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(pactTint)
                        Text(pact.title)
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    MemberAvatarStack(memberIds: [store.currentUserId, partnerId], maxVisible: 2)
                }
                Text(statusLine)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(pactTint.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pact: \(pact.title)")
    }

    private var eyebrow: String {
        if pact.status == .pending { return "PACT · JUST YOU TWO · PENDING" }
        return "PACT · JUST YOU TWO · DAY \(dayNumber)"
    }

    private var dayNumber: Int {
        guard let start = pact.startDate else { return 1 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: Date())).day ?? 0
        return max(1, days)
    }

    private var statusLine: String {
        if pact.status == .pending { return "Waiting on \(store.friend(by: partnerId)?.displayName ?? "them")" }
        let cal = Calendar.current
        let today = Date()
        let youToday = store.pactCompletions.contains { $0.pactId == pact.id && $0.userId == store.currentUserId && cal.isDate($0.date, inSameDayAs: today) }
        let themToday = store.pactCompletions.contains { $0.pactId == pact.id && $0.userId == partnerId && cal.isDate($0.date, inSameDayAs: today) }
        if youToday && themToday { return "You both showed up today ✓" }
        let kept = max(store.pactDaysKept(pact: pact, userId: store.currentUserId),
                       store.pactDaysKept(pact: pact, userId: partnerId))
        return "\(kept) days kept so far"
    }
}

#Preview {
    ScrollView {
        CirclesGroupsSection(
            isExpanded: .constant(true),
            onHeaderTap: {},
            onCircleTap: { _ in },
            onStoryStripTap: { _ in },
            onStartJoinTap: {},
            onPactTap: { _ in }
        )
        .environment(Store())
    }
    .background(Theme.warmWheat)
}
