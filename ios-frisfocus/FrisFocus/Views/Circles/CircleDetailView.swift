//
//  CircleDetailView.swift
//  FrisFocus
//
//  Detail page for a single FFCircle, reached by tapping a card on the
//  Circles main page. This pass (C4a-1) builds only the shared chrome
//  and the type-tinted night-sky hero — the frame both parallel and
//  collective variants will reuse. The body between the hero and the
//  settings footer is intentionally empty here; C4a-2 / C4a-3 fill the
//  parallel body (task list, member progress) and C4b adds the
//  collective body.
//
//  The hero gradient is a function of `circle.type` so the colour cue
//  alone tells the user which kind of circle they're inside before
//  reading a word — purple night for parallel, green night for
//  collective. The helper is exposed at file scope so the later passes
//  can reuse it without duplicating colour values.
//
//  Navigation: this is a sub-page of the Circles room, so the sundial
//  paints `.subPage` (face stays, hand hides). Home dismisses back to
//  the Circles page, Circles also dismisses (one tap returns the user
//  to the room they came from).
//

import SwiftUI
import UIKit

struct CircleDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let circle: FFCircle

    @State private var showCaptureSheet: Bool = false
    @State private var showSettings: Bool = false
    @State private var linkPickerTarget: LinkPickerTarget?
    @State private var showGroupStory: Bool = false
    /// The lifetime "Our story" chapter lookback (distinct from the
    /// daily clips player above).
    @State private var showOurStory: Bool = false
    @State private var storyCaptureTarget: CircleStoryCaptureTarget?

    /// Which time slice the parallel body renders. Drives both "The
    /// work" (the user's own progress) and "The circle today" (every
    /// member's progress). Collective circles ignore the toggle until
    /// C4b lands their body.
    @State private var scope: CircleScope = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    // The group story rides at the very top — the
                    // first thing inside any circle (parallel or
                    // collective) the moment a member has posted a
                    // clip today. Hidden when there's nothing to watch.
                    if hasStoryToday {
                        CircleStoryStrip(
                            memberCount: clipAuthorCountToday,
                            isWatched: allClipsWatchedToday,
                            onTap: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showGroupStory = true
                            }
                        )
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 18)
                    }

                    // The always-available "Add to story" entry sits
                    // directly beneath the story module so adding a
                    // moment is the first thing the user reaches — in
                    // every circle, whether or not anyone has posted
                    // yet. It auto-tags the user's latest finished task
                    // when there is one, otherwise opens a general
                    // circle moment.
                    addToStoryCTA
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, hasStoryToday ? 12 : 18)

                    // The body renders by whatever layers are active:
                    // a shared list, a shared number, both (hybrid), or
                    // neither (witness presence). Always clearly separated.
                    layeredBody
                }
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)

            SundialNavView(
                active: .subPage,
                onCaptureTap: { showCaptureSheet = true },
                onHomeTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                },
                onCirclesTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .edgeSwipeBack()
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showSettings) {
            CircleSettingsSheet(circleId: circle.id)
                .environment(store)
        }
        .sheet(item: $linkPickerTarget) { target in
            TaskLinkingPickerView(circleId: circle.id, circleTaskId: target.circleTaskId)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $storyCaptureTarget) { target in
            CaptureView(mode: .circleClip(circle: circle, task: target.task))
        }
        .fullScreenCover(isPresented: $showGroupStory) {
            StoryPlayerView(mode: .circle(circle))
                .environment(store)
        }
        .sheet(isPresented: $showOurStory) {
            CircleStoryView(circleId: circle.id)
                .environment(store)
        }
    }

    // MARK: - Layered body

    /// Renders the circle by its active objective layers — the shared
    /// list, the shared number, both (hybrid, clearly separated), or a
    /// pure presence roster for Witness circles.
    @ViewBuilder
    private var layeredBody: some View {
        // Shared-list layer — "The work" + per-member progress.
        if circle.hasSharedList {
            scopeToggle
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 4)

            CircleSharedTasksSection(
                circle: circle,
                scope: scope,
                onLinkTap: { task in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    linkPickerTarget = LinkPickerTarget(circleTaskId: task.id)
                },
                onAddToStory: { task in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    storyCaptureTarget = CircleStoryCaptureTarget(task: task)
                }
            )
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 8)

            CircleMemberProgressSection(circle: circle, scope: scope)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 8)
        }

        // Shared-number layer — one number + contributions. In a hybrid a
        // divider sits above it so the two goals read as separate things.
        if circle.hasSharedNumber {
            if circle.hasSharedList {
                hybridDivider
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 26)
            }
            CircleCollectiveSection(circle: circle)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, circle.hasSharedList ? 16 : 24)
                .padding(.bottom, 8)
        }

        // Witness circles are pure presence — who's showing up today,
        // each at their own sharing. No goal, no progress bar, no ranking.
        if circle.type == .witness {
            CirclePresenceSection(circle: circle)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 8)
        }

        // Tail so content scrolls clear of the sundial.
        Color.clear.frame(height: 160)
    }

    /// A labelled hairline that separates the two goals in a hybrid so
    /// the page never reads as a pile of features.
    private var hybridDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.textPrimary.opacity(0.1)).frame(height: 0.5)
            Text("AND")
                .font(.sans(9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Rectangle().fill(Theme.textPrimary.opacity(0.1)).frame(height: 0.5)
        }
    }

    // MARK: - Scope toggle

    /// A small two-segment pill above "The work". Picks the time slice
    /// that drives every progress display in the parallel body. Light
    /// haptic on change so it feels deliberate.
    private var scopeToggle: some View {
        HStack(spacing: 0) {
            scopeChip(.today, label: "Today")
            scopeChip(.overall, label: "Overall")
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.textPrimary.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Progress scope")
    }

    private func scopeChip(_ value: CircleScope, label: String) -> some View {
        let isSelected = scope == value
        return Button {
            guard scope != value else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                scope = value
            }
        } label: {
            Text(label)
                .font(.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Color.clear)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(label)
    }

    // MARK: - Circle clip capture CTA

    /// The first circle task the current user has completed today, if
    /// any. When present, the always-visible "Add to story" button
    /// auto-tags it as the earned badge ("Add your mile"); otherwise the
    /// button posts a general circle moment with no task attached.
    private var firstCompletedTaskToday: CircleTask? {
        circle.tasks.first { task in
            store.hasUserCompletedCircleTaskToday(circleId: circle.id, circleTaskId: task.id)
        }
    }

    /// Always-available entry into the circle's story, parked right
    /// under the story module. Smart about the day: tags the user's
    /// latest finished task when there is one, otherwise opens a general
    /// circle moment (`task == nil`).
    @ViewBuilder
    private var addToStoryCTA: some View {
        let earned = firstCompletedTaskToday
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            storyCaptureTarget = CircleStoryCaptureTarget(task: earned)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xD87D44).opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "camera.fill")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB25A2C))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(earned == nil ? "Add to story" : "Add your mile to the story")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(earned.map { "Earned \u{201C}\($0.title)\u{201D} today" } ?? "Share a moment from this circle")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color(hex: 0xD87D44).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color(hex: 0xD87D44).opacity(0.28), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(earned == nil ? "Add to story" : "Add your mile to the story")
    }

    // MARK: - Story strip presence

    private var clipAuthorsToday: [UUID] {
        Array(Set(store.circleClipsToday(circleId: circle.id).map { $0.authorId }))
    }

    private var clipAuthorCountToday: Int { clipAuthorsToday.count }
    private var hasStoryToday: Bool { clipAuthorCountToday > 0 }

    /// Every clip today has been played — the strip mutes to its
    /// "watched · replay" state.
    private var allClipsWatchedToday: Bool {
        let clips = store.circleClipsToday(circleId: circle.id)
        guard !clips.isEmpty else { return false }
        return clips.allSatisfy { store.viewedStoryPostIds.contains($0.id) }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                ZStack {
                    CircleDetailHeroGradient(type: circle.type)

                    // The circle's shared header photo, when set — a
                    // soft banner behind the hero with a dark wash so
                    // the name and member stack stay readable.
                    if let url = heroHeaderURL {
                        Color.clear
                            .overlay {
                                CachedImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    CircleDetailHeroGradient(type: circle.type)
                                }
                            }
                            .clipped()
                            .allowsHitTesting(false)

                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.48),
                                Color.black.opacity(0.20),
                                Color.black.opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Circle settings")
            .accessibilityHint("Opens settings for this circle")

            starsLayer
                .allowsHitTesting(false)

            topBar
                .padding(.top, 56)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .frame(maxHeight: .infinity, alignment: .top)

            identityBlock
                .padding(.leading, Theme.pageHorizontalPadding)
                .padding(.trailing, Theme.pageHorizontalPadding)
                .padding(.bottom, 18)
        }
        .frame(height: 220)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if store.circleHasUnwatchedStory(circleId: circle.id) {
                NewStoryBadge(diameter: 12)
                    .padding(.top, 60)
                    .padding(.trailing, Theme.pageHorizontalPadding + 44)
            }
        }
    }

    /// Live header URL — `circle` is captured at navigation time, so a
    /// header set moments ago in settings reads from the Store instead.
    private var heroHeaderURL: URL? {
        (store.circle(by: circle.id) ?? circle).headerURL
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.sans(15, weight: .medium))
                    Text("Friends")
                        .font(.sans(14, weight: .regular))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Friends")

            Spacer()

            HStack(spacing: 8) {
                if pendingCount > 0 {
                    pendingHeaderBadge
                }
                ourStoryButton
            }
        }
    }

    /// A quiet entry into the group's lifetime story, parked in the
    /// header beside the back button.
    private var ourStoryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showOurStory = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "book.closed")
                    .font(.sans(10, weight: .semibold))
                Text("Our story")
                    .font(.sans(12, weight: .medium))
            }
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Theme.textCream.opacity(0.16)))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.textCream.opacity(0.28), lineWidth: 0.5))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Our story")
        .accessibilityHint("A lookback on everything this circle has done together")
    }

    // MARK: - Identity block

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrowText)
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textCream.opacity(0.72))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(circle.name)
                    .font(.serif(25, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(2)
                Image(systemName: "gearshape.fill")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.5))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                CircleDetailMemberStack(memberIds: circle.memberIds, maxVisible: 4)
                Text(membershipCaption)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrowText: String {
        let typeLabel = circle.type.eyebrowLabel
        switch circle.timeframe {
        case .timeBoxed(let endDate):
            let days = CircleDetailHelpers.daysLeft(until: endDate)
            let suffix = days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT"
            return "\(typeLabel) · \(suffix)"
        case .ongoing:
            return "\(typeLabel) · ONGOING"
        }
    }

    /// `you + N others` when the user is a member, otherwise `N members`.
    private var membershipCaption: String {
        let includesUser = circle.memberIds.contains(store.currentUserId)
        let others = max(0, circle.memberIds.count - (includesUser ? 1 : 0))
        if includesUser {
            if others == 0 { return "just you" }
            if others == 1 { return "you + 1 other" }
            return "you + \(others) others"
        }
        return others == 1 ? "1 member" : "\(others) members"
    }

    // MARK: - Stars

    @ViewBuilder
    private var starsLayer: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                star(at: CGPoint(x: w * 0.08, y: h * 0.22), size: 1.4, opacity: 0.55)
                star(at: CGPoint(x: w * 0.22, y: h * 0.10), size: 1.0, opacity: 0.40)
                star(at: CGPoint(x: w * 0.32, y: h * 0.30), size: 1.8, opacity: 0.65)
                star(at: CGPoint(x: w * 0.48, y: h * 0.16), size: 1.2, opacity: 0.50)
                star(at: CGPoint(x: w * 0.60, y: h * 0.08), size: 1.0, opacity: 0.35)
                star(at: CGPoint(x: w * 0.72, y: h * 0.28), size: 1.6, opacity: 0.58)
                star(at: CGPoint(x: w * 0.86, y: h * 0.14), size: 1.0, opacity: 0.40)
                star(at: CGPoint(x: w * 0.94, y: h * 0.34), size: 1.4, opacity: 0.48)
            }
        }
    }

    private func star(at point: CGPoint, size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(Theme.textCream.opacity(opacity))
            .frame(width: size, height: size)
            .position(point)
    }

    // MARK: - Pending review signal

    /// Count of pending join/task requests the current user can act on.
    /// Zero for members without management rights, so the header badge
    /// only lights up for owners/admins who can clear the queue.
    private var pendingCount: Int {
        store.canManageTasks(in: circle)
            ? store.pendingRequestCount(forCircleId: circle.id)
            : 0
    }

    /// The "N PENDING" pill shown in the header's top-right when there's
    /// a review queue. Non-interactive — taps fall through to the hero
    /// button so the whole header still opens settings.
    private var pendingHeaderBadge: some View {
        Text("\(pendingCount) PENDING")
            .font(.sans(10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.alertGreen)
            )
            .allowsHitTesting(false)
            .accessibilityLabel("\(pendingCount) pending requests")
    }
}

// MARK: - Link picker target

/// Identifiable wrapper around the circle-task id that's being linked,
/// so `sheet(item:)` can drive presentation while still passing the id
/// into the picker without holding a stale value-type copy of the task.
private struct LinkPickerTarget: Identifiable, Equatable {
    let circleTaskId: UUID
    var id: UUID { circleTaskId }
}

// MARK: - Circle story capture target

/// Drives the circle-clip capture cover. Wraps an optional task so the
/// always-available "Add to story" button can post a general circle
/// moment (`task == nil`) while a finished or held task rides along as
/// the earned badge. A fresh `id` per launch makes `fullScreenCover(item:)`
/// treat each capture as a new presentation.
private struct CircleStoryCaptureTarget: Identifiable {
    let id = UUID()
    let task: CircleTask?
}

// MARK: - Hero gradient (shared by C4 / C4b)

/// The type-tinted night-sky gradient shared by every circle detail
/// surface. Exposed at file scope so the collective body in C4b can
/// paint matching backgrounds without duplicating colour values.
struct CircleDetailHeroGradient: View {
    let type: CircleType

    var body: some View {
        LinearGradient(
            colors: Self.colors(for: type),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func colors(for type: CircleType) -> [Color] {
        type.heroColors
    }
}

// MARK: - Helpers

enum CircleDetailHelpers {
    /// Days remaining between today and a time-boxed circle's end
    /// date, clamped at zero so a just-expired circle reads as
    /// `0 DAYS LEFT` rather than going negative.
    static func daysLeft(until endDate: Date, from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfEnd = cal.startOfDay(for: endDate)
        let comps = cal.dateComponents([.day], from: startOfToday, to: startOfEnd)
        return max(0, comps.day ?? 0)
    }
}

// MARK: - Member avatar stack

/// Overlapping disc stack used in the hero. Each member's
/// `accentColorHex` paints their disc; the current user gets a gold
/// ring + a thin cream halo so they're unmistakable in any group. When
/// the member count exceeds `maxVisible`, the tail closes with a
/// soft cream `+N` pill.
private struct CircleDetailMemberStack: View {
    @Environment(Store.self) private var store
    let memberIds: [UUID]
    let maxVisible: Int
    var diameter: CGFloat = 26
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
            overflow(count)
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
            .overlay(
                Circle()
                    .strokeBorder(Theme.textCream.opacity(0.4), lineWidth: 0.5)
                    .padding(0.8)
            )
        } else if let friend = store.friend(by: id) {
            FriendAvatarView(friend: friend, size: diameter)
                .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.85), lineWidth: 1.2))
        } else {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.85), lineWidth: 1.2))
        }
    }

    private func overflow(_ count: Int) -> some View {
        ZStack {
            Circle().fill(Theme.textCream.opacity(0.16))
            Text("+\(count)")
                .font(.sans(10, weight: .semibold))
                .foregroundStyle(Theme.textCream.opacity(0.9))
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.5), lineWidth: 0.8))
    }
}

#Preview("Parallel") {
    let store = Store()
    return NavigationStack {
        if let parallel = store.circles.first(where: { $0.type == .parallel }) {
            CircleDetailView(circle: parallel)
        }
    }
    .environment(store)
}

#Preview("Collective") {
    let store = Store()
    return NavigationStack {
        if let collective = store.circles.first(where: { $0.type == .collective }) {
            CircleDetailView(circle: collective)
        }
    }
    .environment(store)
}
