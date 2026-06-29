//
//  HomeView.swift
//  FrisFocus
//
//  The four zones stitched into a single vertical scroll, with the
//  interactive side rail and the custom sundial nav layered on top.
//
//  This view owns:
//   • The current time → SunSky (refreshed every 60 s)
//   • The LocationService that backs sunrise / sunset
//   • The currently active zone, progress through it, and rail tint
//   • Light haptic feedback at every zone boundary crossing
//   • The sundial's active destination + capture and profile sheets
//

import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(NotificationManager.self) private var notifications
    @Environment(MessageGraphService.self) private var messageGraph
    @Environment(GoldenHourService.self) private var goldenHour
    @Environment(FriendGraphService.self) private var friendGraph
    @Environment(WalkthroughManager.self) private var walkthrough
    @State private var locationService = LocationService()
    /// The contextual concept lesson currently presented on home
    /// (day-shape, full day). One at a time, each fires once.
    @State private var homeLesson: WalkthroughLesson?
    /// All scroll/zone bookkeeping lives here so updating the rail's
    /// active zone + progress never invalidates the heavy page content.
    @State private var scrollTracker = HomeScrollTracker()
    /// Whether the Sun zone's season detail is unfolded inline. Owned
    /// here so collapsing can scroll the zone back to the top of the
    /// screen. Never persisted — the home always launches compact.
    @State private var seasonExpanded: Bool = false
    @State private var topSafeInset: CGFloat = 0

    // Continuous scrub support: bind the scroll view's position so the
    // rail can drive it to an arbitrary offset. Content vs. viewport
    // heights (for the 0...1 rail fraction → y offset map) come from the
    // scroll tracker, fed by `onScrollGeometryChange`.
    @State private var scrollPosition = ScrollPosition(edge: .top)

    // Nav / sheet state
    @State private var showProfileSheet: Bool = false
    @State private var showCircles: Bool = false
    /// The circle whose Golden Hour surface the golden orb opens.
    @State private var goldenTarget: GoldenHourTarget?
    /// A tapped friend-request banner opens the Friends page here.
    @State private var showFriendsFromBanner: Bool = false
    /// The circle event opened from the homescreen "Upcoming" glance.
    @State private var homeEventTarget: HomeEventTarget?
    /// Brief confirmation text after a shake-to-undo. Nil when hidden.
    @State private var undoMessage: String?
    /// Auto-dismiss timer for the undo banner.
    @State private var undoDismissTask: Task<Void, Never>?

    /// Coordinate space anchored to the scrolling content, so each
    /// zone's measured top/height stays stable while the page scrolls
    /// (the rail tracking reads these once rather than every frame).
    private let contentSpace = "frisFocusContent"

    var body: some View {
        @Bindable var notifications = notifications

        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let sky = SunSky.make(now: context.date, coordinate: locationService.coordinate)
                home
                    .environment(\.sunSky, sky)
                    .onChange(of: context.date) { _, _ in
                        // Keep nudging CoreLocation if we still don't
                        // have a fix — on device the first permission
                        // prompt can land after onAppear has already
                        // fired, so the initial requestLocation can
                        // miss. Cheap to call when authorized; no-ops
                        // if denied.
                        if locationService.coordinate == nil {
                            locationService.requestPermissionIfNeeded()
                        }
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showCircles) {
                CirclesView()
            }
        }
        .onAppear {
            locationService.requestPermissionIfNeeded()
            scrollTracker.prepareHaptics()
            refreshTopSafeInset()
        }
        .fullScreenCover(item: $notifications.pendingRoute) { route in
            NotificationRouteHost(route: route, myUserId: auth.user?.id ?? "")
        }
        .fullScreenCover(item: $goldenTarget) { target in
            GoldenHourHostView(circleId: target.circleId)
                .environment(goldenHour)
                .environment(auth)
        }
        .profileQuickCard(isPresented: $showProfileSheet)
        .sheet(isPresented: $showFriendsFromBanner) {
            NavigationStack {
                FriendsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFriendsFromBanner = false }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
        .sheet(item: $homeEventTarget) { target in
            CircleEventDetailView(eventId: target.eventId)
                .environment(store)
        }
        .onAppear { store.refreshRecurringEvents() }
    }

    /// Unread direct messages — live from the app-wide messaging
    /// service, so the badge is accurate without ever opening Circles.
    private var unreadMessages: Int {
        guard let myId = auth.user?.id else { return 0 }
        return messageGraph.totalUnread(myUserId: myId)
    }

    @ViewBuilder
    private var home: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        SunZoneView(
                            topSafeInset: topSafeInset,
                            onProfileTap: { showProfileSheet = true },
                            onStatsOpened: {
                                // Let the detail unfold first, then glide
                                // the page down so the stats (with the
                                // docked week chip) are actually in view.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        scrollProxy.scrollTo(SunZoneView.statsAnchorID, anchor: .top)
                                    }
                                }
                            },
                            isExpanded: $seasonExpanded
                        )
                            .id(HomeZone.sun.anchorID)
                            .background(zoneTracker(.sun))

                        RidgeSeamView()

                        WorkZoneView()
                            .id(HomeZone.work.anchorID)
                            .background(zoneTracker(.work))

                        // Work → Note
                        GradientSeam(
                            topColor: Theme.warmWheat,
                            bottomColor: Theme.paperCream,
                            height: 30
                        )

                        NoteZoneView()
                            .id(HomeZone.note.anchorID)
                            .background(zoneTracker(.note))

                        MilestoneZoneView()
                            .id(HomeZone.milestone.anchorID)
                            .background(zoneTracker(.milestone))

                        // Tail so the last content can scroll above the sundial
                        Theme.paperCream
                            .frame(height: 150)
                    }
                    .containerRelativeFrame(.horizontal)
                    .coordinateSpace(.named(contentSpace))
                }
                .scrollClipDisabled(false)
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                    ScrollMetrics(
                        offsetY: geo.contentOffset.y,
                        contentHeight: geo.contentSize.height,
                        viewportHeight: geo.containerSize.height
                    )
                } action: { _, metrics in
                    scrollTracker.updateScroll(
                        offsetY: metrics.offsetY,
                        contentHeight: metrics.contentHeight,
                        viewportHeight: metrics.viewportHeight
                    )
                }
                .background(Theme.warmWheat)
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ZoneFramesPreferenceKey.self) { frames in
                    for (zone, frame) in frames {
                        scrollTracker.updateZoneFrame(zone, top: frame.minY, height: frame.height)
                    }
                }
                .overlay(alignment: .trailing) {
                    HomeRailContainer(
                        tracker: scrollTracker,
                        onTap: { zone in
                            handleRailTap(zone: zone, proxy: scrollProxy)
                        },
                        onScrub: { fraction in
                            scrubTo(fraction: fraction)
                        }
                    )
                    .padding(.trailing, 4)
                }

                SundialNavView(
                    active: .home,
                    onHomeTap: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            scrollProxy.scrollTo(HomeZone.sun.anchorID, anchor: .top)
                        }
                    },
                    onCirclesTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showCircles = true
                    },
                    circlesBadgeCount: unreadMessages
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .background(Theme.warmWheat)
            // Root page — nothing to go back to, so a left-edge swipe
            // opens the proof camera instead.
            .edgeSwipeCamera()
            // Shake to undo the last reversible plan action.
            .onShake { handleShakeUndo() }
            // Folding the season detail closed gently scrolls the sun
            // zone back to the top so the user is never stranded
            // mid-page where the detail used to be.
            .onChange(of: seasonExpanded) { _, expanded in
                if !expanded {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        scrollProxy.scrollTo(HomeZone.sun.anchorID, anchor: .top)
                    }
                }
            }
            // Mechanics tour: bring the Today plan into view on each
            // gesture step so the real cards are there to act on.
            .onChange(of: walkthrough.tourStep) { _, step in
                guard step != nil else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    scrollProxy.scrollTo(HomeZone.work.anchorID, anchor: .top)
                }
            }
            // The check-off lesson advances on the real check; the
            // home lessons fire as the day's shape becomes meaningful.
            .onChange(of: store.coldStartProgress.done) { old, new in
                handleTourCheck(old: old, new: new, proxy: scrollProxy)
                maybeFireHomeLessons(done: new)
            }
            // Retiring the tour clears the parallel first-check banner.
            .onChange(of: walkthrough.tourActive) { _, active in
                if !active { store.coldStartCoaching = false }
            }
            .overlay { MechanicsTourOverlay() }
            .walkthroughLessonSheet($homeLesson) { walkthrough.markSeen($0) }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    // Time machine — the real home has transformed to a
                    // past day; this pill is the marker + the way back.
                    if let day = store.viewingDay {
                        PastDayBanner(day: day) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                store.viewingDay = nil
                            }
                        }
                    }

                    // First-check coaching, only in the session right
                    // after the cold-start board lands here. Suppressed
                    // while the interactive mechanics tour is running so
                    // the two never coach at once.
                    if !walkthrough.tourActive {
                        ColdStartCoachBanner()
                    }

                    // Live friend-graph moments — a request just arrived,
                    // or someone accepted yours. Tap opens Friends.
                    FriendRequestBanner {
                        showFriendsFromBanner = true
                    }

                    // The next circle event you're in on — one glance away.
                    UpcomingEventsGlance { event in
                        homeEventTarget = HomeEventTarget(eventId: event.id)
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)

                    // Golden Hour orb — exists only while a moment is live
                    // (pulsing banner) or its wall is still open (draining
                    // chip). Gone the rest of the day.
                    GoldenHourBanner { circleId in
                        goldenTarget = GoldenHourTarget(circleId: circleId)
                    }

                    BoosterAwardToast(
                        award: store.pendingBoosterAward,
                        onDismiss: { store.clearPendingBoosterAward() }
                    )
                    .allowsHitTesting(store.pendingBoosterAward != nil)

                    HabitTrainAwardToast(
                        award: store.pendingTrainAward,
                        onDismiss: { store.clearPendingTrainAward() }
                    )
                    .allowsHitTesting(store.pendingTrainAward != nil)

                    if let message = undoMessage {
                        UndoBanner(text: message)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, max(topSafeInset, 12) + 6)
            }
        }
    }

    // MARK: - Zone tracking

    private func zoneTracker(_ zone: HomeZone) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ZoneFramesPreferenceKey.self,
                    value: [zone: proxy.frame(in: .named(contentSpace))]
                )
        }
    }

    /// Reads the actual key window's top safe-area inset. We do this
    /// imperatively (rather than via a GeometryReader-in-background with
    /// `.ignoresSafeArea()`) because that pattern reports a zeroed inset
    /// on this view hierarchy, which was leaving the Sun zone meta row
    /// tucked behind the Dynamic Island.
    private func refreshTopSafeInset() {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 0
        if inset > 0 {
            topSafeInset = inset
        }
    }

    // MARK: - Mechanics tour + contextual lessons

    /// The check-off lesson advances on the user's real first check: the
    /// page glides up to reveal the sun that just rose (the hero moment),
    /// holds a beat, then moves on to the swipe lesson. The quantity
    /// lesson advances on the next logged amount.
    private func handleTourCheck(old: Int, new: Int, proxy: ScrollViewProxy) {
        guard walkthrough.tourActive, new > old else { return }
        switch walkthrough.tourStep {
        case .checkOff:
            withAnimation(.easeInOut(duration: 0.55)) {
                proxy.scrollTo(HomeZone.sun.anchorID, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                walkthrough.advanceTour()
            }
        case .quantity:
            walkthrough.advanceTour()
        default:
            break
        }
    }

    /// Fire the home concept lessons just-in-time: the day-shape lesson a
    /// few tasks in, the full-day note when the day is complete. Never
    /// during the tour, and only one at a time.
    private func maybeFireHomeLessons(done: Int) {
        guard !walkthrough.tourActive, homeLesson == nil else { return }
        let total = store.coldStartProgress.total
        guard total > 0 else { return }
        if done >= total, walkthrough.shouldFire(.fullDay) {
            homeLesson = .fullDay
        } else if done >= 2, done < total, walkthrough.shouldFire(.dayShape) {
            homeLesson = .dayShape
        }
    }

    // MARK: - Tap handling

    private func handleRailTap(zone: HomeZone, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(zone.anchorID, anchor: .top)
        }
    }

    /// Drives the scroll view to an arbitrary offset as the user drags
    /// the rail. `fraction` is 0 (top of the page) ... 1 (bottom). We
    /// map it onto the real scrollable range so the finger tracks the
    /// page like a scrollbar thumb — set directly (no animation) so it
    /// follows the finger frame-for-frame across the full page.
    private func scrubTo(fraction: Double) {
        let maxOffset = max(0, scrollTracker.contentHeight - scrollTracker.viewportHeight)
        let targetY = CGFloat(max(0, min(1, fraction))) * maxOffset
        scrollPosition.scrollTo(y: targetY)
    }

    // MARK: - Shake to undo

    /// Roll back the last reversible plan action and flash a confirming
    /// banner. Ignored when there's nothing left on the undo stack.
    private func handleShakeUndo() {
        guard store.canUndo, let label = store.undoLastAction() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            undoMessage = label
        }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    undoMessage = nil
                }
            }
        }
    }
}

// MARK: - Scroll metrics

/// The slice of scroll geometry the rail tracker needs. Equatable so
/// `onScrollGeometryChange` only fires the action when it actually moves.
private struct ScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

// MARK: - Rail container

/// Thin wrapper that reads the scroll tracker's active zone + progress
/// so ONLY the rail re-renders as you scroll — the heavy page content
/// never sees these changes.
private struct HomeRailContainer: View {
    let tracker: HomeScrollTracker
    let onTap: (HomeZone) -> Void
    let onScrub: (Double) -> Void

    var body: some View {
        SideRailView(
            activeZone: tracker.activeZone,
            progress: tracker.progress,
            tint: tracker.activeZone.prefersDarkRail ? Theme.textPrimary : Theme.textCream,
            onTap: onTap,
            onScrub: onScrub
        )
    }
}

// MARK: - Undo banner

/// Small pill that confirms what a shake just undid, then fades out.
private struct UndoBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
            Text("Undone — \(text)")
                .font(.sans(13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.textCream)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Theme.textPrimary.opacity(0.92))
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

// MARK: - Preference key

/// Identifiable wrapper so the homescreen glance can drive an event
/// detail sheet without a global UUID-Identifiable extension.
private struct HomeEventTarget: Identifiable {
    let eventId: UUID
    var id: UUID { eventId }
}

// MARK: - Preference key

struct ZoneFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [HomeZone: CGRect] = [:]

    static func reduce(
        value: inout [HomeZone: CGRect],
        nextValue: () -> [HomeZone: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

#Preview {
    HomeView()
}
