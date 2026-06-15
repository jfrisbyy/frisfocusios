//
//  FriendDetailView.swift
//  FrisFocus
//
//  The friend profile — a quiet editorial page, not a stat sheet.
//
//   • Hero: the friend's own header (photo or crafted sky) that
//     breathes with their actual day, with "CURRENTLY IN" and the big
//     serif season name carved in. Back and "…" float as soft discs.
//   • Identity card: a warm white card over the seam — story-ringed
//     avatar, name beside the one number that matters (days shown up,
//     ever), handle + joined + connected, intention quote, their mood
//     line, mutual friends, and the dark Friends/Add pill with a round
//     message button.
//   • Body: hairline sections — TODAY (ring + headline + task chips,
//     tier-gated), points privacy as a feature, one italic witness
//     line, the season's destinations as a timeline, seasons before,
//     then Together and Since-you-connected.
//
//  Visibility is always the friend's dial; the page never exposes more
//  than they chose. Calm, witness-model, never a surveillance sheet.
//

import SwiftUI
import UIKit

struct FriendDetailView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(MessageGraphService.self) private var messageGraph
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(FriendGraphService.self) private var friendGraph
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let friend: Friend

    @State private var showCheerComposer: Bool = false
    @State private var showSharingSettings: Bool = false
    @State private var showStories: Bool = false
    @State private var showSendProof: Bool = false
    @State private var showProposePact: Bool = false
    @State private var showThread: Bool = false
    @State private var showWeekSheet: Bool = false
    @State private var selectedDayId: Int = 0
    @State private var detailCircle: FFCircle?
    @State private var detailPact: Pact?
    @State private var ringPulse: Bool = false
    @State private var ringFill: Double = 0

    // Friend controls + profile texture
    @State private var reportTarget: ReportTarget?
    @State private var showBlockConfirm: Bool = false
    @State private var showUnfriendConfirm: Bool = false
    @State private var showMutualsList: Bool = false
    @State private var isRelationshipWorking: Bool = false
    @State private var mutuals: [RemoteProfile] = []
    @State private var joinedDate: Date?

    /// Zoom-transition namespace — the story player grows out of the
    /// hero avatar and shrinks back into it on dismiss.
    @Namespace private var storyZoom

    // MARK: - Derived

    private var tier: VisibilityTier { friend.sharesWithMe.tier }
    private var day: FriendDay { store.friendDay(for: friend) }

    /// The live friend record — `friend` is captured at navigation time,
    /// so permission state (exact points) reads from the store to stay
    /// current while the page is open.
    private var liveFriend: Friend { store.friend(by: friend.id) ?? friend }
    private var texture: ConnectionTexture { store.connectionTexture(for: friend) }
    private var accent: Color { Color(hex: friend.accentColorHex) }

    private var sharedCircles: [FFCircle] { store.sharedCircles(withFriendId: friend.id) }
    private var sharedPacts: [Pact] { store.sharedPacts(withFriendId: friend.id) }
    private var togetherCount: Int { sharedCircles.count + sharedPacts.count }

    private var myUserId: String? { auth.user?.id }

    /// The friend's real account profile — lets the Proof and Message
    /// actions land in the live synced 1:1 thread instead of the old
    /// local-only pipeline.
    private var remoteProfile: RemoteProfile? { socialSync.profile(forLocal: friend.id) }

    /// The friend's published season card — cover, accent, intention,
    /// season info, lifetime days, mood, milestones, past chapters.
    private var publishedCard: SeasonCard? { liveFriend.seasonCard ?? remoteProfile?.card }

    /// The live connection state — drives the identity pill.
    private var relationship: FriendRelationship {
        guard let remote = remoteProfile, let myId = myUserId else { return .friends }
        return friendGraph.relationship(to: remote.id, myUserId: myId)
    }

    private var unreadFromFriend: Int {
        if let remote = remoteProfile, let myId = myUserId {
            return messageGraph.unreadCount(fromFriendId: remote.id, myUserId: myId)
        }
        return store.unreadCount(fromFriendId: friend.id)
    }
    private var hasUnviewedStories: Bool { store.hasUnviewedStories(forFriendId: friend.id) }
    private var hasAnyStories: Bool { store.hasAnyActiveStories(forFriendId: friend.id) }
    private var unviewedStoryCount: Int {
        store.activeFriendStories.filter {
            $0.authorId == friend.id && !store.viewedStoryPostIds.contains($0.id)
        }.count
    }

    /// The header's living-light strength — their actual day. Quiet
    /// tier reveals nothing, so it rests neutral.
    private var headerStrength: Double {
        switch tier {
        case .full: return 0.15 + 0.85 * day.completionFraction
        case .open: return 0.15 + 0.85 * day.momentum
        case .quiet: return 0.5
        }
    }

    /// The friend's custom header background, when they've set one.
    private var headerPhotoURL: URL? {
        liveFriend.headerURL ?? remoteProfile?.headerURL
    }

    private var shortSeasonName: String? {
        let raw = publishedCard?.seasonName ?? friend.currentSeasonName
        guard let full = raw else { return nil }
        let trimmed = full.replacingOccurrences(of: " Season", with: "")
        return trimmed.isEmpty ? full : trimmed
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    identityCard
                        .padding(.horizontal, Theme.pageHorizontalPadding - 6)
                        .offset(y: -52)
                        .padding(.bottom, -52)
                        .zIndex(1)

                    journalBody
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 26)
                        .padding(.bottom, 24)

                    Color.clear.frame(height: 130)
                }
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)

            SundialNavView(
                active: .subPage,
                onCaptureTap: {},
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
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName
            )
            .environment(auth)
            .environment(moderation)
        }
        .sheet(isPresented: $showMutualsList) {
            MutualFriendsListSheet(name: friend.displayName, mutuals: mutuals)
        }
        .sheet(isPresented: $showWeekSheet) {
            WeekRhythmSheet(name: friend.displayName, bars: day.rhythmBars, accent: accent)
        }
        .alert("Block \(friend.displayName)?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) {
                Task { await blockFriend() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Blocking removes the friendship and stops all messages and requests between you. They aren't notified.")
        }
        .confirmationDialog(
            "Unfriend \(friend.displayName)?",
            isPresented: $showUnfriendConfirm,
            titleVisibility: .visible
        ) {
            Button("Unfriend", role: .destructive) {
                Task { await unfriendNow() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can add them again later. They aren't notified.")
        }
        .sheet(isPresented: $showCheerComposer) {
            CheerComposerView(friend: friend).environment(store)
        }
        .sheet(isPresented: $showSharingSettings) {
            NavigationStack {
                SharingSettingsView(friendId: friend.id).environment(store)
            }
        }
        .sheet(isPresented: $showThread) {
            // The real synced conversation — the same thread the Proofs
            // inbox opens. Falls back to the local view only when this
            // person has no resolved account (previews, offline seeds).
            if let remote = remoteProfile, let myId = myUserId {
                ProofThreadView(friend: remote, message: messageGraph, myUserId: myId)
                    .environment(store)
                    .environment(auth)
                    .environment(moderation)
                    .environment(socialSync)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                DirectThreadView(friend: friend)
                    .environment(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showStories) {
            StoryPlayerView(mode: .friend(friend))
                .navigationTransition(.zoom(sourceID: "frienddetail-story", in: storyZoom))
                .environment(store)
        }
        .fullScreenCover(isPresented: $showSendProof) {
            // Send through the live pipeline: the proof uploads to the
            // private bucket, lands in the real 1:1 thread instantly,
            // and pushes the friend — identical to sending from chat.
            if let remote = remoteProfile, let myId = myUserId {
                CaptureView(
                    mode: .generalPost,
                    liveProofRecipientName: remote.displayName,
                    onSendLiveProof: { data, isVideo, duration, caption in
                        await messageGraph.sendProof(
                            to: remote.id,
                            data: data,
                            mediaKind: isVideo ? .video : .photo,
                            durationSeconds: duration,
                            caption: caption,
                            myUserId: myId
                        )
                    }
                )
                .environment(store)
            } else {
                CaptureView(mode: .generalPost, initialDirectFriendId: friend.id).environment(store)
            }
        }
        .fullScreenCover(isPresented: $showProposePact) {
            ProposePactView(preselectedFriendId: friend.id).environment(store)
        }
        .fullScreenCover(item: $detailCircle) { circle in
            CircleDetailView(circle: circle).environment(store)
        }
        .fullScreenCover(item: $detailPact) { pact in
            PactDetailView(pact: pact).environment(store)
        }
        .onAppear {
            let target = glanceRingFraction
            if reduceMotion {
                ringFill = target
            } else {
                withAnimation(.easeOut(duration: 0.9)) { ringFill = target }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    ringPulse = true
                }
            }
        }
        .task { await loadProfileTexture() }
    }

    // MARK: - Friend-control actions

    /// Mutual friends + join date — the identity card's quiet facts.
    private func loadProfileTexture() async {
        guard let remote = remoteProfile, let myId = myUserId else { return }
        async let mutualsFetch = friendGraph.mutualFriends(with: remote.id, myUserId: myId)
        async let joinedFetch = friendGraph.joinedDate(of: remote.id)
        mutuals = await mutualsFetch
        joinedDate = await joinedFetch
    }

    private func unfriendNow() async {
        guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
        isRelationshipWorking = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        await friendGraph.unfriend(remote, myUserId: myId)
        await socialSync.refreshFriends()
        isRelationshipWorking = false
        dismiss()
    }

    private func blockFriend() async {
        guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
        isRelationshipWorking = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        await moderation.block(remote.id, myUserId: myId)
        await friendGraph.load(myUserId: myId)
        await socialSync.refreshFriends()
        isRelationshipWorking = false
        dismiss()
    }

    // MARK: - Hero

    /// The owner-designed header with the season carved into its lower
    /// left, breathing with their real day.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ProfilePosterBackground(
                coverId: publishedCard?.coverId,
                headerURL: headerPhotoURL,
                accent: accent,
                strength: headerStrength
            )

            VStack(alignment: .leading, spacing: 7) {
                if shortSeasonName != nil {
                    Text("CURRENTLY IN")
                        .font(.sans(9.5, weight: .semibold))
                        .tracking(2.6)
                        .foregroundStyle(Theme.textCream.opacity(0.6))
                }
                if let seasonName = shortSeasonName {
                    Text(seasonName)
                        .font(.serif(33, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                }
                if let dayNumber = publishedCard?.currentDay ?? friend.currentSeasonDay {
                    Text(seasonDayLine(dayNumber))
                        .font(.sans(10, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                }
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 74)
        }
        .frame(height: 330)
        .clipped()
        .overlay(alignment: .top) {
            topBar
                .padding(.top, 54)
                .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }

    private func seasonDayLine(_ dayNumber: Int) -> String {
        if let length = publishedCard?.seasonLengthDays, length > 0 {
            return "DAY \(dayNumber) OF \(length)"
        }
        return "DAY \(dayNumber)"
    }

    /// Back + "…" as soft dark floating discs.
    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Friends")

            Spacer()

            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSharingSettings = true
                } label: {
                    Label("What \(friend.displayName) sees", systemImage: "eye")
                }
                if let remote = remoteProfile {
                    Divider()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        reportTarget = ReportTarget(
                            reportedUserId: remote.id,
                            messageId: nil,
                            subjectName: friend.displayName
                        )
                    } label: {
                        Label("Report \(friend.displayName)", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        showBlockConfirm = true
                    } label: {
                        Label("Block \(friend.displayName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .contentShape(Circle())
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Identity card

    private var identityCard: some View {
        ProfileIdentityCard(
            name: friend.displayName,
            lifetimeDays: publishedCard?.lifetimeDays,
            metaLine: metaLine,
            intention: publishedCard?.intention,
            moodLine: publishedCard?.moodLine
        ) {
            storyRingAvatar
        } extra: {
            if !mutuals.isEmpty {
                mutualsButton
            }
        } pills: {
            HStack(spacing: 10) {
                friendPill
                IdentityRoundButton(
                    icon: "bubble.left.and.bubble.right.fill",
                    badge: unreadFromFriend > 0,
                    label: unreadFromFriend > 0
                        ? "Message \(friend.displayName), \(unreadFromFriend) unread"
                        : "Message \(friend.displayName)"
                ) {
                    showThread = true
                }
            }
        }
    }

    /// Handle · joined · connected — the quiet identity facts.
    private var metaLine: String {
        var parts: [String] = []
        if let handle = remoteProfile?.handle { parts.append(handle) }
        if let joinedDate {
            parts.append("since \(joinedDate.formatted(.dateTime.month(.abbreviated).year()))")
        } else {
            parts.append(store.connectedDescription(friend))
        }
        return parts.joined(separator: " · ")
    }

    /// The honest relationship pill — Friends ✓ (tap to unfriend),
    /// Add friend, Requested, or Accept request.
    @ViewBuilder
    private var friendPill: some View {
        switch relationship {
        case .friends, .isMe:
            IdentityPill(title: "Friends", icon: "checkmark", filled: true, isWorking: isRelationshipWorking) {
                showUnfriendConfirm = true
            }
            .accessibilityLabel("Friends with \(friend.displayName). Tap for options.")
        case .none:
            IdentityPill(title: "Add friend", icon: "person.badge.plus", filled: true, isWorking: isRelationshipWorking) {
                guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
                isRelationshipWorking = true
                Task {
                    await friendGraph.sendRequest(to: remote, myUserId: myId)
                    isRelationshipWorking = false
                }
            }
        case .requestSent:
            IdentityPill(title: "Requested", icon: "hourglass", filled: false, isWorking: false) { }
                .allowsHitTesting(false)
        case .requestReceived:
            IdentityPill(title: "Accept request", icon: "checkmark.circle", filled: true, isWorking: isRelationshipWorking) {
                guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
                guard let request = friendGraph.incoming.first(where: { $0.profile.id == remote.id }) else { return }
                isRelationshipWorking = true
                Task {
                    await friendGraph.accept(request, myUserId: myId)
                    await socialSync.refreshFriends()
                    isRelationshipWorking = false
                }
            }
        }
    }

    /// Overlapping mutual avatars + "N in common" — taps open the list.
    private var mutualsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMutualsList = true
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(Array(mutuals.prefix(3).enumerated()), id: \.element.id) { _, profile in
                        mutualDisc(profile)
                    }
                }
                Text("\(mutuals.count) in common")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mutuals.count) mutual friends. Tap to view.")
    }

    private func mutualDisc(_ profile: RemoteProfile) -> some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    mutualInitials(profile)
                }
            } else {
                mutualInitials(profile)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(hex: 0xFFFBF1), lineWidth: 1.5))
    }

    private func mutualInitials(_ profile: RemoteProfile) -> some View {
        ZStack {
            Color(hex: RemoteIDMapper.accentHex(forRemoteId: profile.id))
            Text(profile.initials)
                .font(.sans(9, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    /// Avatar + story ring. Lit gold (with a slow shimmer) when there
    /// are unviewed stories; muted when all seen; a quiet ring when
    /// they have no active story. Tapping opens their stories.
    private var storyRingAvatar: some View {
        Button {
            guard hasAnyStories else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showStories = true
        } label: {
            ZStack {
                ZStack {
                    if let url = friend.avatarURL {
                        CachedImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            initialsAvatar
                        }
                    } else {
                        initialsAvatar
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .padding(5)
                .background(Circle().fill(Color(hex: 0xFFFBF1)))
                .overlay { ringOverlay }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasAnyStories)
        .matchedTransitionSource(id: "frienddetail-story", in: storyZoom)
        .accessibilityLabel(
            hasUnviewedStories
                ? "\(friend.displayName), \(unviewedStoryCount) new stories"
                : friend.displayName
        )
    }

    /// Initials on the signature color — the fallback when this person
    /// has no profile photo (or while it loads).
    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(accent)
            Text(friend.initials)
                .font(.sans(23, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var ringOverlay: some View {
        if hasUnviewedStories {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter, Theme.sunCore, Theme.sunWarm],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .opacity(reduceMotion ? 1 : (ringPulse ? 1 : 0.6))
        } else if hasAnyStories {
            Circle().strokeBorder(Theme.sunOuter.opacity(0.5), lineWidth: 2)
        } else {
            Circle().strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Journal body

    private var journalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            todaySection

            if tier != .quiet {
                JournalHairline()
                    .padding(.vertical, 18)
                exactPointsRow
            }

            if let witness = witnessLine {
                JournalHairline()
                    .padding(.vertical, 18)
                WitnessLineView(text: witness, accent: accent)
            }

            if tier != .quiet, let milestones = publishedCard?.milestones, !milestones.isEmpty {
                JournalHairline()
                    .padding(.vertical, 18)
                destinationsSection(milestones)
            }

            if let past = publishedCard?.pastSeasons, !past.isEmpty {
                JournalHairline()
                    .padding(.vertical, 18)
                seasonsBeforeSection(past)
            }

            JournalHairline()
                .padding(.vertical, 18)
            togetherSection

            JournalHairline()
                .padding(.vertical, 18)
            sinceConnectedSection
        }
    }

    /// One true sentence about their recent story, when there is one.
    private var witnessLine: String? {
        guard tier != .quiet else { return nil }
        return makeWitnessLine(day: day, card: publishedCard)
    }

    // MARK: TODAY

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalSectionHeader(
                label: "TODAY",
                trailingTitle: tier != .quiet ? Date().formatted(.dateTime.weekday(.abbreviated)) : nil,
                trailingAction: tier != .quiet ? { showWeekSheet = true } : nil
            )

            SunDayCard(days: sunDays, accent: accent, selectedId: $selectedDayId)

            if tier != .quiet {
                DayTaskList(day: selectedSunDay, accent: accent)
            }

            // Quiet contextual actions — proof + cheer live here now,
            // so the identity card stays calm.
            HStack(spacing: 22) {
                QuietActionLink(icon: "camera.fill", title: "Send a proof") {
                    showSendProof = true
                }
                QuietActionLink(icon: "hands.clap.fill", title: "Cheer") {
                    showCheerComposer = true
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// The day currently selected in the card, for the list below.
    private var selectedSunDay: SunDay {
        let days = sunDays
        return days.first { $0.id == selectedDayId } ?? days.last ?? days[0]
    }

    private var todayHeadline: String {
        switch tier {
        case .full:
            return dayHeadline(fraction: day.completionFraction, hasAnything: day.totalCount > 0)
        case .open:
            return dayHeadline(fraction: day.momentum, hasAnything: !day.rhythmBars.isEmpty)
        case .quiet:
            return store.headlineFromFriend(friend)
        }
    }

    private var todaySubline: String? {
        switch tier {
        case .full:
            return daySubline(done: day.doneCount, total: day.totalCount)
        case .open:
            return "the shape of their day — no task names"
        case .quiet:
            if let season = shortSeasonName {
                return friend.currentSeasonDay.map { "\(season) · day \($0)" } ?? season
            }
            return "shares a little with you"
        }
    }

    /// The card's days, oldest first ending today, resolved to this
    /// friend's pairwise sharing tier. Past suns reveal their real
    /// completed tasks at Full, the day's shape at Open, and never
    /// reveal points (those stay behind the locked → asked → shared flow).
    private var sunDays: [SunDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard tier != .quiet else {
            return [SunDay(id: 0, date: today, ratio: 0, headline: todayHeadline,
                           subline: todaySubline, chips: [], scoreText: nil)]
        }
        let bars = day.rhythmBars
        let n = bars.count
        return bars.enumerated().map { idx, ratio in
            let daysAgo = (n - 1) - idx
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            if daysAgo == 0 {
                return SunDay(
                    id: 0, date: date, ratio: ratio,
                    headline: todayHeadline, subline: todaySubline,
                    chips: todayChipItems, scoreText: nil
                )
            }
            return pastSunDay(daysAgo: daysAgo, date: date, ratio: ratio)
        }
    }

    private var todayChipItems: [SunDayChip] {
        switch tier {
        case .full:
            return day.tasks
                .sorted { $0.isDone && !$1.isDone }
                .map { SunDayChip(title: $0.title, isDone: $0.isDone) }
        case .open:
            return day.categoryBreakdown.map {
                SunDayChip(title: "\($0.category.displayName) · \($0.done) of \($0.total)", isDone: $0.done > 0)
            }
        case .quiet:
            return []
        }
    }

    private func pastSunDay(daysAgo: Int, date: Date, ratio: Double) -> SunDay {
        switch tier {
        case .full:
            let tasks = store.friendCompletedTasks(for: friend, on: date)
            return SunDay(
                id: daysAgo, date: date, ratio: ratio,
                headline: dayHeadline(fraction: ratio, hasAnything: ratio > 0 || !tasks.isEmpty),
                subline: tasks.isEmpty ? "a quiet day" : "\(tasks.count) done",
                chips: tasks.map { SunDayChip(title: $0.title, isDone: true) },
                scoreText: nil
            )
        default:
            return SunDay(
                id: daysAgo, date: date, ratio: ratio,
                headline: dayHeadline(fraction: ratio, hasAnything: ratio > 0),
                subline: "the shape of this day",
                chips: [], scoreText: nil
            )
        }
    }

    /// Target fill for the today ring — completion at Full, momentum
    /// at Open, empty at Quiet.
    private var glanceRingFraction: Double {
        switch tier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    // MARK: Points — privacy as a feature

    /// Point values are private calibration — they encode what's
    /// personally hard for someone — so they never surface by default.
    /// This row is the explicit ask: locked → asked → shared.
    @ViewBuilder
    private var exactPointsRow: some View {
        switch liveFriend.pointsAccess {
        case .granted:
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "lock.open")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
                Text("\(day.todayLogged) points today")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                Text("· shared with you")
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                Spacer(minLength: 0)
            }
            .accessibilityLabel("\(friend.displayName) logged \(day.todayLogged) points today")

        case .requested:
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                Text("Asked to see exact points · waiting on \(friend.displayName)")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer(minLength: 0)
            }
            .accessibilityLabel("Waiting on \(friend.displayName) to share exact points")

        case nil:
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "lock")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                Text("Points are private")
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.requestExactPoints(friendId: friend.id)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Ask to see")
                            .font(.sans(13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.sans(9, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask \(friend.displayName) to see exact points")
            }
        }
    }

    // MARK: Destinations

    private func destinationsSection(_ milestones: [SeasonCardMilestone]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalSectionHeader(label: "THE SEASON’S DESTINATIONS")
            DestinationsTimeline(
                milestones: milestones,
                accent: accent,
                seasonStart: publishedCard?.seasonStartDate
            )
        }
    }

    // MARK: Seasons before

    private func seasonsBeforeSection(_ past: [PastSeasonSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalSectionHeader(label: "SEASONS BEFORE")
            SeasonsBeforeRow(chapters: past, showsMilestones: tier != .quiet)
        }
    }

    // MARK: Together

    private var togetherSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalSectionHeader(label: togetherCount > 0 ? "TOGETHER · \(togetherCount) SHARED" : "TOGETHER")
            VStack(spacing: 10) {
                ForEach(sharedCircles) { circle in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailCircle = circle
                    } label: { circleTogetherRow(circle) }
                    .buttonStyle(.plain)
                }
                ForEach(sharedPacts) { pact in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailPact = pact
                    } label: { pactTogetherRow(pact) }
                    .buttonStyle(.plain)
                }
                makePactRow
            }
        }
    }

    /// A calm dashed entry to start a two-person pact with this friend.
    private var makePactRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showProposePact = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.sans(12, weight: .semibold))
                Text(togetherCount > 0 ? "Make another pact with \(friend.displayName)" : "Make a pact with \(friend.displayName)")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a pact with \(friend.displayName)")
    }

    private func circleTogetherRow(_ circle: FFCircle) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(circleEyebrow(circle))
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            Text(circle.name)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            progressBar(fraction: circleFraction(circle), tint: Theme.alertGreen)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func pactTogetherRow(_ pact: Pact) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("PACT · JUST YOU TWO · DAY \(pactDayNumber(pact))")
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            Text(pact.title)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(pactStatusLine(pact))
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Since you connected

    private var sinceConnectedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalSectionHeader(
                label: "SINCE YOU CONNECTED · \(store.connectedDescription(friend).uppercased().replacingOccurrences(of: "CONNECTED ", with: ""))"
            )
            HStack(spacing: 0) {
                textureStat("\(texture.proofsTraded)", "proofs\ntraded")
                textureStat("\(texture.cheersExchanged)", "cheers\nexchanged")
                textureStat("\(texture.milestonesWitnessed)", "milestones\nwitnessed")
            }
            Text(texture.line)
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textureStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.serif(24, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared helpers

    private func progressBar(fraction: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textPrimary.opacity(0.1))
                Capsule().fill(tint).frame(width: proxy.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 8)
    }

    private func circleEyebrow(_ circle: FFCircle) -> String {
        switch circle.timeframe {
        case .timeBoxed(let end):
            let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: end)).day ?? 0)
            return "CIRCLE · \(days) DAY\(days == 1 ? "" : "S") LEFT"
        case .ongoing:
            return "CIRCLE · ONGOING"
        }
    }

    /// A representative completion fraction for the circle today.
    private func circleFraction(_ circle: FFCircle) -> Double {
        if circle.hasSharedList {
            let cal = Calendar.current
            let today = Date()
            let done = store.circleTaskCompletions.filter {
                $0.circleId == circle.id && cal.isDate($0.date, inSameDayAs: today)
            }.count
            let denom = max(1, circle.memberIds.count * max(1, circle.tasks.count))
            return Double(done) / Double(denom)
        }
        if circle.hasSharedNumber {
            let p = circle.collectiveProgress ?? 0
            let t = circle.collectiveTarget ?? 1
            return p / max(t, 0.0001)
        }
        return 0
    }

    private func pactDayNumber(_ pact: Pact) -> Int {
        guard let start = pact.startDate else { return 1 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: Date())).day ?? 0
        return max(1, days)
    }

    private func pactStatusLine(_ pact: Pact) -> String {
        let cal = Calendar.current
        let today = Date()
        let themId = pact.proposerId == store.currentUserId ? pact.partnerId : pact.proposerId
        let youToday = store.pactCompletions.contains { $0.pactId == pact.id && $0.userId == store.currentUserId && cal.isDate($0.date, inSameDayAs: today) }
        let themToday = store.pactCompletions.contains { $0.pactId == pact.id && $0.userId == themId && cal.isDate($0.date, inSameDayAs: today) }
        if youToday && themToday { return "You both showed up today ✓" }
        let kept = max(store.pactDaysKept(pact: pact, userId: store.currentUserId),
                       store.pactDaysKept(pact: pact, userId: themId))
        return "\(kept) days kept so far"
    }
}

// MARK: - Mutual friends sheet

/// The full "friends in common" list — a calm sheet of avatar rows
/// opened from the identity card's mutuals button.
struct MutualFriendsListSheet: View {
    let name: String
    let mutuals: [RemoteProfile]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(mutuals.enumerated()), id: \.element.id) { idx, profile in
                            if idx > 0 {
                                Rectangle()
                                    .fill(Theme.textPrimary.opacity(0.06))
                                    .frame(height: 0.5)
                                    .padding(.leading, 64)
                            }
                            mutualRow(profile)
                        }
                    }
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
                    )
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("In common with \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func mutualRow(_ profile: RemoteProfile) -> some View {
        HStack(spacing: 13) {
            ZStack {
                if let url = profile.photoURL {
                    CachedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        mutualRowInitials(profile)
                    }
                } else {
                    mutualRowInitials(profile)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let handle = profile.handle {
                    Text(handle)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func mutualRowInitials(_ profile: RemoteProfile) -> some View {
        ZStack {
            Color(hex: RemoteIDMapper.accentHex(forRemoteId: profile.id))
            Text(profile.initials)
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }
}

#Preview("Aaron — full") {
    let store = Store()
    return NavigationStack {
        if let aaron = store.friends.first {
            FriendDetailView(friend: aaron)
        }
    }
    .environment(store)
}

#Preview("Devin — open") {
    let store = Store()
    return NavigationStack {
        if store.friends.count >= 3 {
            FriendDetailView(friend: store.friends[2])
        }
    }
    .environment(store)
}

#Preview("Naomi — quiet") {
    let store = Store()
    return NavigationStack {
        if store.friends.count >= 5 {
            FriendDetailView(friend: store.friends[4])
        }
    }
    .environment(store)
}
