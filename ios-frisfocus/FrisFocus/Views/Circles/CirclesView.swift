//
//  CirclesView.swift
//  FrisFocus
//
//  The "Friends" page — the social room reached from the sundial.
//  ("Circles" refers exclusively to the groups feature inside it.)
//
//  Structure, top to bottom:
//   • Slim header — "Friends" in the serif face, send icon + the
//     user's gold-ringed avatar at right. No hero block.
//   • Story row — previews fill the ring (thumbnail discs, bright
//     season ring unwatched / thin grey watched / ring-less plain).
//   • Hairline divider.
//   • "TODAY" — every friend as a hairline row: goal-ratio ring
//     avatar, templated privacy-safe status, inline proof/message
//     pill actions.
//   • "Your circles" — the groups feature, unchanged mechanics.
//
//  The page sits on warm parchment with a whisper of a vertical
//  gradient (lighter at top). The side rail snaps between FRIENDS and
//  CIRCLES; the Sundial paints `.circles` active here.
//

import SwiftUI
import UIKit

struct CirclesView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Section + rail state

    @State private var circlesExpanded: Bool = true
    @State private var activeRail: CirclesRailSection = .friends
    @State private var sectionTops: [CirclesRailSection: CGFloat] = [:]

    // MARK: - Sheet + navigation state

    @State private var showCaptureSheet: Bool = false
    @State private var showProfileSheet: Bool = false
    @State private var showStartTogether: Bool = false
    @State private var pendingCreate: CreateKind? = nil
    @State private var activeCreate: CreateKind? = nil
    /// Set while the start/join chooser dismisses so Discover pushes
    /// only after the sheet has fully closed.
    @State private var pendingDiscover: Bool = false
    @State private var showStoryCapture: Bool = false
    @State private var showMyStory: Bool = false
    @State private var showDirect: Bool = false
    @State private var showAddFriends: Bool = false
    @State private var showInvite: Bool = false
    @State private var threadFriend: Friend?
    @State private var route: CirclesRoute?

    /// The app-wide messaging backend — drives the paper-plane's unread
    /// dot and the sundial badge. Realtime is owned at the app root, so
    /// the count here is always live.
    @Environment(MessageGraphService.self) private var messageGraph

    /// The app-wide friend graph — its unseen-request state paints the
    /// red dot on the header avatar.
    @Environment(FriendGraphService.self) private var friendGraph

    /// Golden Hour: the orb's tap target. The banner itself only exists
    /// while a moment is live or its wall is still draining.
    @Environment(GoldenHourService.self) private var goldenHour
    @State private var goldenTarget: GoldenHourTarget?

    /// Zoom-transition namespace: story players grow out of the exact
    /// avatar / strip that opened them and shrink back into it.
    @Namespace private var storyZoom

    /// Anchor ids for the section headers; the rail scrolls to these.
    /// The friends anchor sits on the page header so FRIENDS jumps all
    /// the way to the very top (header + stories), not just the list.
    private let friendsAnchor = "friends.top"
    private let circlesAnchor = "friends.circles"
    private let scrollSpace = "friendsScroll"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                pageBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 8)
                            .id(friendsAnchor)
                            .background(sectionTopTracker(.friends))

                        PeopleStoryRow(
                            userInitials: profileStore.myProfile?.initials ?? auth.user?.initials ?? "",
                            userPhotoURL: profileStore.myProfile?.photoURL ?? auth.user?.photoURL,
                            zoomNamespace: storyZoom,
                            onFriendTap: { friend, hasStories in
                                handleStoryTap(friend: friend, hasStories: hasStories)
                            },
                            onYouTap: { handleYouTap() },
                            onYouAddTap: { handleYouAddTap() },
                            onAddFriendTap: { handleAddFriendTap() }
                        )
                        .padding(.top, 18)

                        hairline
                            .padding(.top, 16)

                        // With zero friends there is no "Today" to list —
                        // a warm welcome block with real people to add
                        // takes its place until the first friend lands.
                        if store.friends.isEmpty {
                            friendsWelcomeBlock
                        } else {
                            PeopleTodayList(
                                onRowTap: { friend in handleRowTap(friend) },
                                onActionTap: { friend in handleActionTap(friend) }
                            )
                        }

                        CirclesGroupsSection(
                            isExpanded: $circlesExpanded,
                            zoomNamespace: storyZoom,
                            onHeaderTap: { toggleCircles() },
                            onCircleTap: { circle in handleCircleTap(circle) },
                            onStoryStripTap: { circle in handleCircleStoryTap(circle) },
                            onStartJoinTap: { handleStartJoinTap() },
                            onPactTap: { pact in handlePactTap(pact) },
                            onDiscoverTap: { handleDiscoverTap() }
                        )
                        .id(circlesAnchor)
                        .background(sectionTopTracker(.circles))

                        // Tail so content can scroll above the sundial.
                        Color.clear.frame(height: 140)
                    }
                }
                .refreshable { await loadMessages() }
                .coordinateSpace(.named(scrollSpace))
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
                    },
                    circlesBadgeCount: directUnread
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                GoldenHourBanner { circleId in
                    goldenTarget = GoldenHourTarget(circleId: circleId)
                }
                .padding(.top, 6)
            }
            .fullScreenCover(item: $goldenTarget) { target in
                GoldenHourHostView(circleId: target.circleId)
                    .environment(goldenHour)
                    .environment(auth)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            // The Friends room is a root page — the left edge opens the
            // proof camera, same as the homepage. Going home stays one
            // tap on the sundial's home button.
            .edgeSwipeCamera()
            .sheet(isPresented: $showCaptureSheet) {
                CaptureSheetView()
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .fullScreenCover(isPresented: $showStoryCapture) {
                CaptureView(mode: .generalPost)
            }
            .fullScreenCover(isPresented: $showMyStory) {
                StoryPlayerView(mode: .mine)
                    .navigationTransition(.zoom(sourceID: "mystory", in: storyZoom))
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
            .sheet(item: $threadFriend) { friend in
                DirectThreadView(friend: friend)
                    .environment(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showInvite) {
                NavigationStack {
                    InviteFriendsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showInvite = false }
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                }
            }
            .sheet(isPresented: $showAddFriends) {
                NavigationStack {
                    FriendsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showAddFriends = false }
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                }
            }
            .sheet(isPresented: $showStartTogether, onDismiss: {
                // Present the chosen flow only after the chooser has
                // fully dismissed, so the full-screen cover doesn't
                // fight the sheet's dismissal animation.
                if let kind = pendingCreate {
                    pendingCreate = nil
                    activeCreate = kind
                } else if pendingDiscover {
                    pendingDiscover = false
                    route = .discoverCircles
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
                    },
                    onDiscover: {
                        pendingDiscover = true
                        showStartTogether = false
                    }
                )
                .presentationDetents([.height(440)])
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
            .profileQuickCard(isPresented: $showProfileSheet)
            .task { await loadMessages() }
        }
    }

    // MARK: - Header

    /// One airy line: "Friends" in the serif face, send icon + the
    /// user's avatar at right. No hero, no eyebrow.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Friends")
                .font(.serif(30, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            sendButton

            ProfileAvatarButton(
                initials: profileStore.myProfile?.initials ?? auth.user?.initials ?? "",
                photoURL: profileStore.myProfile?.photoURL ?? auth.user?.photoURL,
                showDot: friendGraph.hasUnseenRequests
            ) {
                showProfileSheet = true
            }
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
    }

    /// Paper-plane entry to the proofs/messages inbox, with a quiet dot
    /// when something is waiting.
    private var sendButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showDirect = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "paperplane")
                    .font(.sans(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .frame(width: 38, height: 38)

                if directUnread > 0 {
                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.5))
                        .offset(x: -4, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(directUnread > 0 ? "Messages, \(directUnread) new" : "Messages")
    }

    /// Warm parchment with a very subtle vertical gradient — slightly
    /// lighter at the top so the page breathes.
    private var pageBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: 0xFDF8EB),
                Theme.warmWheat,
                Theme.warmWheat
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, Theme.pageHorizontalPadding)
    }

    // MARK: - Zero-friend welcome

    /// What lives under "Your story" before the first friend: a short
    /// line about what this page becomes, real people to add right
    /// here, and the invite doorway.
    private var friendsWelcomeBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("It's just you so far.")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("This page becomes your people — their stories up top, their days below. Add a friend or two and it comes alive.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PeopleSuggestionsCard(palette: .parchment, maxCount: 4)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showInvite = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.sans(13, weight: .semibold))
                    Text("Invite friends")
                        .font(.sans(14, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.textPrimary)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Invite friends")
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Live messaging (unread dot)

    /// Refresh of the shared messaging window — realtime keeps it live;
    /// this is the explicit pull-to-refresh / on-appear catch-up.
    private func loadMessages() async {
        guard let myId = auth.user?.id else { return }
        await messageGraph.load(myUserId: myId)
    }

    /// Total unread proofs/notes across every real conversation — drives
    /// the paper-plane dot and the sundial badge.
    private var directUnread: Int {
        guard let myId = auth.user?.id else { return 0 }
        return messageGraph.totalUnread(myUserId: myId)
    }

    // MARK: - Section toggling

    private func toggleCircles() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.28)) {
            circlesExpanded.toggle()
        }
    }

    // MARK: - Tap routing

    /// Story bubbles: any active story (watched or not) opens the
    /// viewer; a story-less bubble opens the friend's detail.
    private func handleStoryTap(friend: Friend, hasStories: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = hasStories ? .friendStory(friend.id) : .friendDetail(friend.id)
    }

    /// Friend rows always open the friend detail — story viewing lives
    /// in the story row, the detail is the relationship hub.
    private func handleRowTap(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = .friendDetail(friend.id)
    }

    /// The inline pill / quiet glyph — straight into the 1:1 thread.
    /// Opening the thread marks it read, which reverts the pill to the
    /// quiet glyph.
    private func handleActionTap(_ friend: Friend) {
        threadFriend = friend
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

    private func handleAddFriendTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showAddFriends = true
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

    private func handleDiscoverTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        route = .discoverCircles
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
                    // on the Friends page rather than the closed
                    // story.
                    self.route = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.route = .friendDetail(tapped.id)
                    }
                })
                    .navigationTransition(.zoom(sourceID: "story-\(id.uuidString)", in: storyZoom))
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
                    .navigationTransition(.zoom(sourceID: "circlestory-\(id.uuidString)", in: storyZoom))
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
        case .discoverCircles:
            DiscoverCirclesView()
                .environment(auth)
        }
    }

    // MARK: - Rail snap-scroll

    /// Continuous scrub variant of `handleRailTap` — no haptic
    /// (the rail's own boundary haptic already fires), shorter
    /// animation so the page actively chases the finger.
    private func handleRailScrub(_ section: CirclesRailSection, proxy: ScrollViewProxy) {
        activeRail = section
        if section == .circles, !circlesExpanded {
            withAnimation(.easeInOut(duration: 0.28)) { circlesExpanded = true }
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
        if section == .circles, !circlesExpanded {
            withAnimation(.easeInOut(duration: 0.28)) { circlesExpanded = true }
        }

        let anchor = section == .friends ? friendsAnchor : circlesAnchor
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// The active rail mark follows whichever section header most
    /// recently crossed the top of the viewport. Falls back to TODAY
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
}

// MARK: - Routes

/// Navigation destinations reachable from the Friends page. Each case
/// stores the UUID of the underlying record so the destination can
/// re-fetch the live model on render rather than capturing stale data.
enum CirclesRoute: Hashable {
    case friendDetail(UUID)
    case friendStory(UUID)
    case circleDetail(UUID)
    case circleStory(UUID)
    case pactDetail(UUID)
    case discoverCircles
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
            .environment(MessageGraphService())
    }
}
