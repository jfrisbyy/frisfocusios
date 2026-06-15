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
    @State private var locationService = LocationService()
    @State private var activeZone: HomeZone = .sun
    @State private var zoneFrames: [HomeZone: CGRect] = [:]
    /// Whether the Sun zone's season detail is unfolded inline. Owned
    /// here so collapsing can scroll the zone back to the top of the
    /// screen. Never persisted — the home always launches compact.
    @State private var seasonExpanded: Bool = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    @State private var topSafeInset: CGFloat = 0

    // Continuous scrub support: bind the scroll view's position so the
    // rail can drive it to an arbitrary offset, and track content vs.
    // viewport height to map a 0...1 rail fraction onto a real y offset.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    // Sundial / sheet state
    @State private var sundialActive: SundialDestination = .home
    @State private var sundialPreCapture: SundialDestination = .home
    @State private var showCaptureSheet: Bool = false
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

    private let scrollSpace = "frisFocusScroll"

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
            haptic.prepare()
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
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { contentHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, h in contentHeight = h }
                        }
                    )
                }
                .scrollClipDisabled(false)
                .scrollPosition($scrollPosition)
                .coordinateSpace(.named(scrollSpace))
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { viewportHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, h in viewportHeight = h }
                    }
                )
                .background(Theme.warmWheat)
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ZoneFramesPreferenceKey.self) { frames in
                    zoneFrames = frames
                    updateActiveZone()
                }
                .overlay(alignment: .trailing) {
                    SideRailView(
                        activeZone: activeZone,
                        progress: progressInActiveZone,
                        tint: railTint,
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
                    active: sundialActive,
                    onCaptureTap: {
                        sundialPreCapture = sundialActive
                        withAnimation { sundialActive = .capture }
                        showCaptureSheet = true
                    },
                    onHomeTap: {
                        withAnimation { sundialActive = .home }
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
            .sheet(isPresented: $showCaptureSheet, onDismiss: {
                withAnimation { sundialActive = sundialPreCapture }
            }) {
                CaptureSheetView()
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
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
                    value: [zone: proxy.frame(in: .named(scrollSpace))]
                )
        }
    }

    /// Active zone = the latest one we've started scrolling into
    /// (progress ≥ 0). Fires a light haptic on change.
    private func updateActiveZone() {
        var newActive: HomeZone = .sun
        for zone in HomeZone.allCases {
            guard let frame = zoneFrames[zone], frame.height > 0 else { continue }
            // Top of viewport is y == 0 in scroll-space; as user scrolls
            // down, each zone's minY decreases below 0.
            let progress = -frame.minY / frame.height
            if progress >= 0 {
                newActive = zone
            }
        }

        guard newActive != activeZone else { return }
        haptic.impactOccurred()
        haptic.prepare()
        activeZone = newActive
    }

    private var progressInActiveZone: Double {
        guard let frame = zoneFrames[activeZone], frame.height > 0 else { return 0 }
        let raw = -frame.minY / frame.height
        return max(0.0, min(1.0, Double(raw)))
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

    private var railTint: Color {
        activeZone.prefersDarkRail ? Theme.textPrimary : Theme.textCream
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
        let maxOffset = max(0, contentHeight - viewportHeight)
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
