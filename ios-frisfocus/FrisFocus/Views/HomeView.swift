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
    @Environment(ProfileStore.self) private var profileStore
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
    /// Inline journal composer state. Home owns it so a user-driven
    /// scroll can dismiss the keyboard and settle the note zone closed.
    @State private var isQuickNoteOpen: Bool = false
    @State private var editingNoteID: UUID?
    @State private var topSafeInset: CGFloat = 0
    /// Invitation card: observation kinds the person has quieted for this
    /// season (loaded once, updated on dismiss). Drives the pull-not-push
    /// nudge into the deeper season conversation.
    @State private var invitationDismissed: Set<SeasonInvitationKind> = []
    /// True while the warm-started season conversation is presented from
    /// the invitation card (opened with the FULL season envelope).
    @State private var showSeasonConversation: Bool = false
    /// The scoped "talk it through" — one task or milestone, not a new
    /// season. Set by the invitation card's neglect/momentum kinds.
    @State private var talkSubject: TaskTalkSubject?

    // Continuous scrub support: bind the scroll view's position so the
    // rail can drive it to an arbitrary offset. Content vs. viewport
    // heights (for the 0...1 rail fraction → y offset map) come from the
    // scroll tracker, fed by `onScrollGeometryChange`.
    @State private var scrollPosition = ScrollPosition(edge: .top)

    // Nav / sheet state
    @Binding var showProfileSheet: Bool
    @State private var showCircles: Bool = false
    /// The circle whose Golden Hour surface the golden orb opens.
    @State private var goldenTarget: GoldenHourTarget?
    /// A tapped friend-request banner opens the Friends page here.
    @State private var showFriendsFromBanner: Bool = false
    /// The circle event opened from the homescreen "Upcoming" glance.
    @State private var homeEventTarget: HomeEventTarget?
    /// Brief confirmation text after a shake-to-undo. Nil when hidden.
    @State private var undoMessage: String?
    /// The Recent Activity sheet (likes, comments, cheers on me).
    @State private var showActivity: Bool = false
    /// Story tap captured inside the Activity sheet — held while the
    /// sheet dismisses, then presented, so the player never stacks on
    /// top of the sheet.
    @State private var pendingActivityStory: ActivityStoryTarget?
    /// The story player opened from an activity row.
    @State private var activityStory: ActivityStoryTarget?
    /// True while the software keyboard is up — hides the sundial nav
    /// so it never covers what the person is typing.
    @State private var keyboardVisible: Bool = false
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
                CirclesView(showProfileSheet: $showProfileSheet)
            }
            .navigationDestination(isPresented: $showFriendsFromBanner) {
                // Pushed in place — the system back button and edge
                // swipe return home; no sheet-with-Done stacking.
                FriendsView()
            }
        }
        .onAppear {
            locationService.requestPermissionIfNeeded()
            scrollTracker.prepareHaptics()
            refreshTopSafeInset()
        }
        // The imperative inset read can race the key window (it returns 0
        // until one exists, and "once at onAppear" never asked again).
        // With 0, the sun zone's header row is laid out inside the
        // status-bar band, where the system swallows every tap — the
        // avatar, camera, and library buttons all go quietly dead. Retry
        // briefly until a real value lands.
        .task {
            for _ in 0..<12 where topSafeInset <= 0 {
                try? await Task.sleep(for: .milliseconds(150))
                refreshTopSafeInset()
            }
            if topSafeInset <= 0 {
                Log.app.error("layout: top safe inset unresolved; forcing floor")
                topSafeInset = 24
            }
        }
        // Second, declarative source for the same number: the stack itself
        // respects the safe area, so its reported inset is trustworthy even
        // in hosting shells where the key-window walk finds nothing.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            if inset > topSafeInset {
                Log.app.debug("layout: topSafeInset ← geometry \(inset)")
                topSafeInset = inset
            }
        }
        .fullScreenCover(item: $notifications.pendingRoute) { route in
            NotificationRouteHost(route: route, myUserId: auth.user?.id ?? "")
        }
        .fullScreenCover(item: $goldenTarget) { target in
            GoldenHourHostView(circleId: target.circleId)
                .environment(goldenHour)
                .environment(auth)
        }
        .sheet(item: $homeEventTarget) { target in
            CircleEventDetailView(eventId: target.eventId)
                .environment(store)
        }
        .sheet(isPresented: $showActivity, onDismiss: {
            // The sheet has fully closed — now land on the story the
            // person tapped: one clean motion instead of a stacked
            // pop-up.
            if let pending = pendingActivityStory {
                pendingActivityStory = nil
                activityStory = pending
            }
        }) {
            RecentActivityView(onOpenStory: { mode, postId in
                pendingActivityStory = ActivityStoryTarget(id: postId, mode: mode)
                showActivity = false
            })
            .environment(store)
        }
        .fullScreenCover(item: $activityStory) { target in
            StoryPlayerView(mode: target.mode, initialPostId: target.id)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showSeasonConversation) {
            SeasonSetupFlowView(coldStartContext: store.makeSeasonSetupContext())
                .environment(store)
        }
        .sheet(item: $talkSubject) { subject in
            TaskTalkSheet(subject: subject)
                .environment(store)
        }
        .onAppear {
            store.refreshRecurringEvents()
            invitationDismissed = SeasonInvitationStore.dismissedKinds(for: store.currentSeason.id)
            maybeFireRolloverLesson()
        }
    }

    /// Unread direct messages — live from the app-wide messaging
    /// service, so the badge is accurate without ever opening Circles.
    private var unreadMessages: Int {
        guard let myId = auth.user?.id else { return 0 }
        return messageGraph.totalUnread(myUserId: myId)
    }

    /// How far the sun zone's header row (library + camera + profile
    /// avatar) reaches below the safe-area top: the avatar's real 44pt
    /// tap frame, its 12pt bottom padding, and 6pt of breathing room.
    /// Anything layered over the home offsets by this so it sits UNDER
    /// the avatar rather than on top of it.
    ///
    /// This was 50, written when the row was 38pt tall. The avatar was
    /// then grown to a 44pt tap target (Apple's minimum) and nothing
    /// updated this number — leaving the activity chip's top edge
    /// sitting 2pt inside the avatar's bottom edge. A 2pt strip is
    /// enough: the chip is drawn later, so it wins the hit test, and
    /// thumbs arriving at the top-right corner land low on the disc.
    /// Reported (again) as "I can't open my profile".
    ///
    /// Kept as one named number because the two are laid out by
    /// different views — SunZoneView positions the avatar, HomeView and
    /// ContentView position what floats over it — and nothing else would
    /// catch them drifting back into each other.
    static let sunHeaderBandHeight: CGFloat = 62

    @ViewBuilder
    private var home: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        SunZoneView(
                            topSafeInset: topSafeInset,
                            onProfileTap: {
                                Log.app.debug("profile: quick card requested from home")
                                showProfileSheet = true
                            },
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

                        NoteZoneView(
                            isQuickNoteOpen: $isQuickNoteOpen,
                            editingNoteID: $editingNoteID,
                            onComposerTyping: {
                                // Keep the line being written visible
                                // above the keyboard as the note grows.
                                withAnimation(.easeOut(duration: 0.22)) {
                                    scrollProxy.scrollTo(
                                        NoteZoneView.quickNoteAnchorID,
                                        anchor: .center
                                    )
                                }
                            }
                        )
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
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .interacting, isQuickNoteOpen || editingNoteID != nil else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isQuickNoteOpen = false
                        editingNoteID = nil
                    }
                }
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

                if !keyboardVisible {
                    SundialNavView(
                        active: .home,
                        onHomeTap: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                scrollProxy.scrollTo(HomeZone.sun.anchorID, anchor: .top)
                            }
                        },
                        onCirclesTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Log.app.debug("navigation: social tap")
                            showCircles = true
                        },
                        circlesBadgeCount: unreadMessages,
                        onProfileTap: {
                            Log.app.debug("profile: quick card requested from sundial")
                            showProfileSheet = true
                        },
                        profileInitials: profileStore.myProfile?.initials ?? auth.user?.initials ?? "",
                        profilePhotoURL: profileStore.myProfile?.photoURL ?? auth.user?.photoURL,
                        profileDot: friendGraph.hasUnseenRequests
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .observeKeyboard($keyboardVisible)
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
            // Mechanics tour: bring the right zone into view on each
            // step so the real cards are there to act on — the sunset
            // close returns to the sun it's talking about.
            .onChange(of: walkthrough.tourStep) { _, step in
                guard let step else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    if step == .sunset {
                        scrollProxy.scrollTo(HomeZone.sun.anchorID, anchor: .top)
                    } else {
                        scrollProxy.scrollTo(HomeZone.work.anchorID, anchor: .top)
                    }
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
            .walkthroughLessonSheet($homeLesson) { walkthrough.markSeen($0); walkthrough.release($0) }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    // A rejected session never fails silently — the way
                    // back in lives right here.
                    SessionExpiredBanner()

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

                    // Engagement entry — always reachable. Warm counted
                    // pill while unseen likes / comments / cheers wait;
                    // a quiet bell otherwise. Tap opens Recent Activity.
                    if store.viewingDay == nil {
                        HStack {
                            // The "?" used to sit here; help now lives on
                            // the profile quick card with the rest of the
                            // me-shaped surfaces, so the sky keeps one
                            // control per corner.
                            Spacer()
                            ActivityGlanceChip(count: store.unseenActivityCount) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showActivity = true
                            }
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        // Clear the sun zone's header row. This overlay is
                        // layered ABOVE the sun zone, and the activity chip
                        // is trailing-aligned at the same x as the profile
                        // avatar (both ~24pt from the right edge) — so at
                        // the same y the chip silently swallows every tap
                        // meant for the avatar, and the profile card can
                        // never open.
                        //
                        // This row used to be gated on
                        // `unseenActivityCount > 0`, which made the
                        // collision rare enough to look like a flake.
                        // Making activity always accessible made it
                        // permanent: the profile button was simply dead.
                        .transition(.opacity.combined(with: .move(edge: .top)))
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

                    // Invitation into the deeper season conversation —
                    // only when local logic has something specific to say,
                    // and never during the mechanics tour.
                    if !walkthrough.tourActive,
                       store.viewingDay == nil,
                       let invitation = store.seasonInvitation(excluding: invitationDismissed) {
                        SeasonInvitationCard(
                            invitation: invitation,
                            onTap: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                switch invitation.target {
                                case .season:
                                    showSeasonConversation = true
                                case .task(let id):
                                    talkSubject = .task(id)
                                case .milestone(let id):
                                    talkSubject = .milestone(id)
                                }
                            },
                            onDismiss: { dismissInvitation(invitation) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, max(topSafeInset, 12) + Self.sunHeaderBandHeight + 6)
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
        if inset > topSafeInset {
            Log.app.debug("layout: topSafeInset ← key window \(inset)")
            topSafeInset = inset
        }
    }

    // MARK: - Mechanics tour + contextual lessons

    /// The check-off lesson advances on the user's real first check: the
    /// page glides up to reveal the sun that just rose (the hero moment),
    /// holds a beat, then moves on to the swipe lesson.
    ///
    /// The quantity lesson deliberately does NOT ride this signal: the
    /// done-count rises on any completion, so a flat check-off would
    /// satisfy the one lesson that is about entering an amount. It
    /// watches the real logged amount instead, in MechanicsTourOverlay.
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
        default:
            break
        }
    }

    /// The rollover, on the first open of the second day.
    ///
    /// `currentSeasonDay` is derived from the season's start date, which
    /// the Store already normalises to start-of-day — so a value of 2 or
    /// more means a day of this season has genuinely closed behind the
    /// person. That is the honest signal, and it needs no new stored
    /// state: the rollover housekeeping itself
    /// (`performDayRolloverIfNeeded`) leaves no observable "a day just
    /// turned" flag, and adding one would be writing to the Store to
    /// learn something the season's own dates already say.
    ///
    /// Nothing here is scoped to "first open" beyond `claim`, which is
    /// once-per-lifetime — so the sentence lands on the first home this
    /// person sees on day two, and never again on its own.
    private func maybeFireRolloverLesson() {
        guard homeLesson == nil,
              store.currentSeasonDay >= 2,
              walkthrough.claim(.tomorrowStartsNew) else { return }
        homeLesson = .tomorrowStartsNew
    }

    /// Fire the home concept lessons just-in-time: the day-shape lesson a
    /// few tasks in, the full-day note when the day is complete.
    ///
    /// Both go through `claim`, which is what keeps this to one voice:
    /// it refuses during the tour, once this session's teaching is spent,
    /// and while any other surface holds the floor. The two branches are
    /// mutually exclusive by their done-counts, so a refused full day
    /// never falls through into claiming the day shape.
    private func maybeFireHomeLessons(done: Int) {
        guard homeLesson == nil else { return }
        let total = store.coldStartProgress.total
        guard total > 0 else { return }
        if done >= total, walkthrough.claim(.fullDay) {
            homeLesson = .fullDay
        } else if done >= 2, done < total, walkthrough.claim(.dayShape) {
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

    // MARK: - Season invitation

    /// Quiet this observation for good and remember it, so the card only
    /// ever returns with a different, sharper one (or retires).
    private func dismissInvitation(_ invitation: SeasonInvitation) {
        SeasonInvitationStore.dismiss(invitation.kind, for: store.currentSeason.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            invitationDismissed.insert(invitation.kind)
        }
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

// MARK: - Activity glance chip

/// Trailing control on the sun zone — the way into Recent Activity.
/// At rest it's a quiet bell in a compact circle; the moment unseen
/// likes / comments / cheers wait, it expands into a warm counted
/// "N new for you" pill, animating between the two states.
private struct ActivityGlanceChip: View {
    let count: Int
    let onTap: () -> Void

    private var hasNew: Bool { count > 0 }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: hasNew ? "heart.fill" : "bell")
                    .font(.system(size: hasNew ? 11 : 13, weight: .semibold))
                    .foregroundStyle(hasNew ? Theme.sunWarm : Theme.textPrimary.opacity(0.5))
                if hasNew {
                    Text(label)
                        .font(.sans(12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, hasNew ? 13 : 0)
            .padding(.vertical, hasNew ? 8 : 0)
            .frame(minWidth: 34, minHeight: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        hasNew ? Theme.sunWarm.opacity(0.45) : Theme.textPrimary.opacity(0.14),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(hasNew ? 0.12 : 0.06), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasNew)
        .accessibilityLabel(
            hasNew
                ? "\(count) new likes, comments, or cheers. Tap to view."
                : "Recent activity. Tap to view."
        )
    }

    private var label: String {
        count == 1 ? "1 new for you" : "\(count) new for you"
    }
}

// MARK: - Preference key

/// Identifiable wrapper so the homescreen glance can drive an event
/// detail sheet without a global UUID-Identifiable extension.
private struct HomeEventTarget: Identifiable {
    let eventId: UUID
    var id: UUID { eventId }
}

/// The story an activity row pointed at — which tape to open and the
/// exact post to land on.
private struct ActivityStoryTarget: Identifiable {
    let id: UUID
    let mode: StoryPlayerMode
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
    HomeView(showProfileSheet: .constant(false))
}
