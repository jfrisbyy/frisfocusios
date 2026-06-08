//
//  CirclesView.swift
//  FrisFocus
//
//  The "looking outward at night" room. Reached by tapping the
//  sundial's Circles destination. C3a built the static shell (hero,
//  rail, sundial); C3b + C3c filled the body with Friends and Circles
//  sections; C3d turns the static layout into a fully interactive page:
//
//   • Collapsible Friends / Your circles headers (animated chevrons,
//     light haptic on toggle, the rest of the page slides up to fill).
//   • "View N more friends" expands the friend list inline.
//   • Illumination-based tap routing — a friend with a fresh story
//     opens the story viewer first; a plain or quiet friend opens the
//     friend detail directly. Stubs today; real destinations land in
//     C6 / C9.
//   • Circle taps route to detail / group story / creation stubs.
//   • Side rail snaps between sections via a `ScrollViewReader`, and
//     tracks which section is currently in view so the active mark
//     follows the user as they scroll.
//
//  The palette is deliberately the inverse of the homepage: deep
//  indigo/violet sky with a soft cream moon, faint scattered stars,
//  and the page body painted in warm wheat below the hero. The Sundial
//  paints `.circles` active here.
//

import SwiftUI
import UIKit

struct CirclesView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    // MARK: - Section + rail state

    @State private var friendsExpanded: Bool = true
    @State private var circlesExpanded: Bool = true
    @State private var activeRail: CirclesRailSection = .friends
    @State private var sectionTops: [CirclesRailSection: CGFloat] = [:]

    // MARK: - Sheet + navigation state

    @State private var showCaptureSheet: Bool = false
    @State private var showProfileSheet: Bool = false
    @State private var showStartTogether: Bool = false
    @State private var pendingCreate: CreateKind? = nil
    @State private var activeCreate: CreateKind? = nil
    @State private var showStoryCapture: Bool = false
    @State private var showMyStory: Bool = false
    @State private var showDirect: Bool = false
    @State private var route: CirclesRoute?

    /// The real messaging backend — drives the paper-plane's unread dot.
    /// The inbox itself owns the live realtime instance; this lightweight
    /// one just keeps the count fresh on the page.
    @State private var messageGraph = MessageGraphService()

    /// Anchor ids for the section headers; the rail scrolls to these.
    private let friendsAnchor = "circles.friends"
    private let circlesAnchor = "circles.circles"
    private let scrollSpace = "circlesScroll"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        moonlitHero

                        CirclesFriendsSection(
                            isExpanded: $friendsExpanded,
                            directUnreadCount: directUnread,
                            onHeaderTap: { toggleFriends() },
                            onFriendTap: { friend, isFresh in
                                handleFriendTap(friend: friend, isFresh: isFresh)
                            },
                            onYouTap: { handleYouTap() },
                            onYouAddTap: { handleYouAddTap() },
                            onDirectTap: { handleDirectTap() },
                            onMessageTap: { friend in handleMessageTap(friend) }
                        )
                        .id(friendsAnchor)
                        .background(sectionTopTracker(.friends))

                        CirclesGroupsSection(
                            isExpanded: $circlesExpanded,
                            onHeaderTap: { toggleCircles() },
                            onCircleTap: { circle in handleCircleTap(circle) },
                            onStoryStripTap: { circle in handleCircleStoryTap(circle) },
                            onStartJoinTap: { handleStartJoinTap() },
                            onPactTap: { pact in handlePactTap(pact) }
                        )
                        .id(circlesAnchor)
                        .background(sectionTopTracker(.circles))

                        // Tail so future content can scroll above the sundial.
                        Color.clear.frame(height: 140)
                    }
                }
                .coordinateSpace(.named(scrollSpace))
                .background(Theme.warmWheat)
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(CirclesSectionTopsPreferenceKey.self) { tops in
                    sectionTops = tops
                    updateActiveRailFromScroll()
                }
                .overlay(alignment: .trailing) {
                    CirclesSideRailView(
                        active: activeRail,
                        onTap: { section in handleRailTap(section, proxy: proxy) },
                        onScrub: { section in handleRailScrub(section, proxy: proxy) }
                    )
                    .padding(.trailing, 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: -10)
                }

                SundialNavView(
                    active: .circles,
                    onCaptureTap: { showCaptureSheet = true },
                    onHomeTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    },
                    onCirclesTap: {
                        // Already here — light tap, no-op.
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCaptureSheet) {
                CaptureSheetView()
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileSheetView()
            }
            .fullScreenCover(isPresented: $showStoryCapture) {
                CaptureView(mode: .generalPost)
            }
            .fullScreenCover(isPresented: $showMyStory) {
                StoryPlayerView(mode: .mine)
                    .environment(store)
            }
            .sheet(isPresented: $showDirect, onDismiss: {
                // Refresh the unread dot the moment the inbox closes.
                Task { await loadMessages() }
            }) {
                ProofsInboxView()
                    .environment(store)
                    .environment(auth)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStartTogether, onDismiss: {
                // Present the chosen flow only after the chooser has
                // fully dismissed, so the full-screen cover doesn't
                // fight the sheet's dismissal animation.
                if let kind = pendingCreate {
                    pendingCreate = nil
                    activeCreate = kind
                }
            }) {
                StartTogetherView(
                    onMakePact: {
                        pendingCreate = .pact
                        showStartTogether = false
                    },
                    onStartCircle: {
                        pendingCreate = .circle
                        showStartTogether = false
                    }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $activeCreate) { kind in
                switch kind {
                case .pact:
                    ProposePactView()
                        .environment(store)
                case .circle:
                    CreateCircleView(onCreated: { created in
                        // Drop the user straight into the new circle
                        // once the create cover has closed.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            route = .circleDetail(created.id)
                        }
                    })
                    .environment(store)
                }
            }
            .navigationDestination(item: $route) { route in
                destination(for: route)
            }
            .task { await loadMessages() }
        }
    }

    // MARK: - Live messaging (unread dot)

    /// A lightweight load for the paper-plane's unread dot. The inbox
    /// owns the live realtime subscription; here we just refresh on
    /// appear and whenever the inbox closes, so the dot stays accurate
    /// without a second channel on the same topic.
    private func loadMessages() async {
        guard let myId = auth.user?.id else { return }
        await messageGraph.load(myUserId: myId)
    }

    /// Total unread proofs/notes across every real conversation — drives
    /// the paper-plane dot on the Friends section.
    private var directUnread: Int {
        guard let myId = auth.user?.id else { return 0 }
        return messageGraph.conversations(myUserId: myId).reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Section toggling

    private func toggleFriends() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.28)) {
            friendsExpanded.toggle()
        }
    }

    private func toggleCircles() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.28)) {
            circlesExpanded.toggle()
        }
    }

    // MARK: - Tap routing

    private func handleFriendTap(friend: Friend, isFresh: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Illumination-based routing: a fresh story opens the story
        // viewer first (C9); plain / quiet goes straight to the
        // friend detail (C6).
        route = isFresh ? .friendStory(friend.id) : .friendDetail(friend.id)
    }

    private func handleYouTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // If the user has at least one unexpired general post, the
        // primary tap watches their own tape. The small `+` badge on
        // the avatar is the explicit "add new" affordance.
        if store.hasActiveMyStories {
            showMyStory = true
        } else {
            showStoryCapture = true
        }
    }

    /// Tap target for the small `+` badge on the You avatar — always
    /// opens the capture flow, even when stories already exist.
    private func handleYouAddTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showStoryCapture = true
    }

    private func handleDirectTap() {
        showDirect = true
    }

    /// The seeded "Friends today" people are a visual demo; their
    /// message buttons lead into the one real inbox so there's a single,
    /// coherent messaging system.
    private func handleMessageTap(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showDirect = true
    }

    private func handlePactTap(_ pact: Pact) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = .pactDetail(pact.id)
    }

    private func handleCircleTap(_ circle: FFCircle) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = .circleDetail(circle.id)
    }

    private func handleCircleStoryTap(_ circle: FFCircle) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = .circleStory(circle.id)
    }

    private func handleStartJoinTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showStartTogether = true
    }

    @ViewBuilder
    private func destination(for route: CirclesRoute) -> some View {
        let _ = route
        switch route {
        case .friendDetail(let id):
            if let friend = store.friend(by: id) {
                FriendDetailView(friend: friend)
            } else {
                CirclesPlaceholderView(
                    title: "Friend",
                    subtitle: "This friend is no longer available.",
                    eyebrow: "FRIEND"
                )
            }
        case .friendStory(let id):
            if let friend = store.friend(by: id) {
                StoryPlayerView(mode: .friend(friend), onShowFriendProfile: { tapped in
                    // Pop the player, then push the friend's full
                    // profile onto the same nav stack so back lands
                    // on the Circles page rather than the closed
                    // story.
                    self.route = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.route = .friendDetail(tapped.id)
                    }
                })
                    .environment(store)
            } else {
                CirclesPlaceholderView(
                    title: "Friend",
                    subtitle: "This friend is no longer available.",
                    eyebrow: "STORY"
                )
            }
        case .circleDetail(let id):
            if let circle = store.circle(by: id) {
                CircleDetailView(circle: circle)
            } else {
                CirclesPlaceholderView(
                    title: "Circle",
                    subtitle: "This circle is no longer available.",
                    eyebrow: "CIRCLE"
                )
            }
        case .circleStory(let id):
            if let circle = store.circle(by: id) {
                StoryPlayerView(mode: .circle(circle))
                    .environment(store)
            } else {
                CirclesPlaceholderView(
                    title: "Circle",
                    subtitle: "This circle is no longer available.",
                    eyebrow: "GROUP STORY"
                )
            }
        case .pactDetail(let id):
            if let pact = store.pact(by: id) {
                PactDetailView(pact: pact)
                    .environment(store)
            } else {
                CirclesPlaceholderView(
                    title: "Pact",
                    subtitle: "This pact is no longer available.",
                    eyebrow: "PACT"
                )
            }
        }
    }

    // MARK: - Rail snap-scroll

    /// Continuous scrub variant of `handleRailTap` — no haptic
    /// (the rail's own boundary haptic already fires), shorter
    /// animation so the page actively chases the finger.
    private func handleRailScrub(_ section: CirclesRailSection, proxy: ScrollViewProxy) {
        activeRail = section
        switch section {
        case .friends:
            if !friendsExpanded {
                withAnimation(.easeInOut(duration: 0.28)) { friendsExpanded = true }
            }
        case .circles:
            if !circlesExpanded {
                withAnimation(.easeInOut(duration: 0.28)) { circlesExpanded = true }
            }
        }
        let anchor = section == .friends ? friendsAnchor : circlesAnchor
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func handleRailTap(_ section: CirclesRailSection, proxy: ScrollViewProxy) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeRail = section

        // Ensure the target section is expanded before we scroll there
        // so the user always lands on visible content.
        switch section {
        case .friends:
            if !friendsExpanded {
                withAnimation(.easeInOut(duration: 0.28)) { friendsExpanded = true }
            }
        case .circles:
            if !circlesExpanded {
                withAnimation(.easeInOut(duration: 0.28)) { circlesExpanded = true }
            }
        }

        let anchor = section == .friends ? friendsAnchor : circlesAnchor
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// The active rail mark follows whichever section header most
    /// recently crossed the top of the viewport. Falls back to friends
    /// when both sections sit below the fold (e.g. at the very top of
    /// the page).
    private func updateActiveRailFromScroll() {
        // A small offset below the status bar so the active mark flips
        // as soon as a section header is roughly at the top of the
        // visible content, not right at the screen edge.
        let threshold: CGFloat = 80

        let friendsTop = sectionTops[.friends] ?? .greatestFiniteMagnitude
        let circlesTop = sectionTops[.circles] ?? .greatestFiniteMagnitude

        let newActive: CirclesRailSection
        if circlesTop <= threshold {
            newActive = .circles
        } else if friendsTop <= threshold {
            newActive = .friends
        } else {
            newActive = .friends
        }

        guard newActive != activeRail else { return }
        activeRail = newActive
    }

    private func sectionTopTracker(_ section: CirclesRailSection) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CirclesSectionTopsPreferenceKey.self,
                value: [section: geo.frame(in: .named(scrollSpace)).minY]
            )
        }
    }

    // MARK: - Moonlit hero

    @ViewBuilder
    private var moonlitHero: some View {
        ZStack(alignment: .bottomLeading) {
            // Night-sky gradient.
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    Color(hex: 0x5A4868)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft moon glow in the upper-right.
            GeometryReader { proxy in
                let glowRadius: CGFloat = 110
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.textCream.opacity(0.42),
                                Theme.textCream.opacity(0.18),
                                Theme.textCream.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: glowRadius
                        )
                    )
                    .frame(width: glowRadius * 2, height: glowRadius * 2)
                    .position(
                        x: proxy.size.width - 30,
                        y: 70
                    )
                    .blur(radius: 6)
                    .allowsHitTesting(false)
            }

            // Stars — faint, scattered.
            starsLayer
                .allowsHitTesting(false)

            // Title block — bottom-left.
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR PEOPLE")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.75))

                Text("Circles")
                    .font(.serif(28, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.bottom, 22)

            // Avatar — top-right, clear of the status bar.
            VStack {
                HStack {
                    Spacer()
                    ProfileAvatarButton(
                        initials: auth.user?.initials ?? "",
                        photoURL: auth.user?.photoURL
                    ) {
                        showProfileSheet = true
                    }
                }
                .padding(.top, 56)
                .padding(.trailing, Theme.pageHorizontalPadding)
                Spacer()
            }
        }
        .frame(height: 200)
        .clipped()
    }

    /// A handful of star dots scattered across the hero. Positions
    /// are deterministic so the field doesn't shuffle on every
    /// re-render.
    @ViewBuilder
    private var starsLayer: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                star(at: CGPoint(x: w * 0.08, y: h * 0.30), size: 1.6, opacity: 0.55)
                star(at: CGPoint(x: w * 0.18, y: h * 0.62), size: 1.2, opacity: 0.40)
                star(at: CGPoint(x: w * 0.30, y: h * 0.18), size: 2.0, opacity: 0.70)
                star(at: CGPoint(x: w * 0.44, y: h * 0.42), size: 1.0, opacity: 0.35)
                star(at: CGPoint(x: w * 0.58, y: h * 0.25), size: 1.4, opacity: 0.50)
                star(at: CGPoint(x: w * 0.66, y: h * 0.58), size: 1.0, opacity: 0.32)
                star(at: CGPoint(x: w * 0.78, y: h * 0.36), size: 1.8, opacity: 0.60)
                star(at: CGPoint(x: w * 0.86, y: h * 0.72), size: 1.2, opacity: 0.42)
                star(at: CGPoint(x: w * 0.92, y: h * 0.22), size: 1.0, opacity: 0.36)
            }
        }
    }

    private func star(at point: CGPoint, size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(Theme.textCream.opacity(opacity))
            .frame(width: size, height: size)
            .position(point)
    }
}

// MARK: - Routes

/// Navigation destinations reachable from the Circles page. Each case
/// stores the UUID of the underlying record so the destination can
/// re-fetch the live model on render rather than capturing stale data.
enum CirclesRoute: Hashable {
    case friendDetail(UUID)
    case friendStory(UUID)
    case circleDetail(UUID)
    case circleStory(UUID)
    case pactDetail(UUID)
}

/// Which "start something together" flow to present after the chooser
/// sheet dismisses. A pact is a circle of two, so both live behind the
/// same start/join entry point.
private enum CreateKind: Int, Identifiable {
    case pact, circle
    var id: Int { rawValue }
}

// MARK: - Preference key for section header tracking

struct CirclesSectionTopsPreferenceKey: PreferenceKey {
    static let defaultValue: [CirclesRailSection: CGFloat] = [:]

    static func reduce(
        value: inout [CirclesRailSection: CGFloat],
        nextValue: () -> [CirclesRailSection: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

#Preview {
    NavigationStack {
        CirclesView()
            .environment(Store())
            .environment(AuthManager())
    }
}
