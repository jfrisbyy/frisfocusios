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

                        // Tail so the last content can scroll above the sundial
                        Theme.paperCream
                            .frame(height: 150)
                    }
                    .containerRelativeFrame(.horizontal)
                }
                .scrollClipDisabled(false)
                .coordinateSpace(.named(scrollSpace))
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
                        onScrub: { zone in
                            withAnimation(.easeOut(duration: 0.18)) {
                                scrollProxy.scrollTo(zone.anchorID, anchor: .top)
                            }
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
                    // Live friend-graph moments — a request just arrived,
                    // or someone accepted yours. Tap opens Friends.
                    FriendRequestBanner {
                        showFriendsFromBanner = true
                    }

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
