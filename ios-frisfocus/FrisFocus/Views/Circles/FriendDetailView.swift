//
//  FriendDetailView.swift
//  FrisFocus
//
//  The friend profile — the mirror. Same layout as your own page; only
//  the action row differs (Friends/Add + chat here). A full-bleed
//  identity header with the sun-ring avatar (ring = their day's sun),
//  the merged status slot, the day block (sun + qualitative line +
//  seven-sun horizon), the checked-first category boxes, and the record
//  below (points ask, destinations, seasons before, together, since
//  you connected).
//
//  Visibility is always the friend's dial; the page never exposes more
//  than they chose. Hard rule: NO denominators, fractions, or point
//  values render anywhere.
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
    @State private var detailCircle: FFCircle?
    @State private var detailPact: Pact?
    @State private var dayRef: DayRef?

    // Friend controls + profile texture
    @State private var reportTarget: ReportTarget?
    @State private var showBlockConfirm: Bool = false
    @State private var showUnfriendConfirm: Bool = false
    @State private var showMuteConfirm: Bool = false
    @State private var showMutualsList: Bool = false
    @State private var isRelationshipWorking: Bool = false
    @State private var mutuals: [RemoteProfile] = []
    @State private var joinedDate: Date?

    /// Zoom-transition namespace — the story player grows out of the
    /// avatar and shrinks back into it on dismiss.
    @Namespace private var storyZoom

    // MARK: - Derived

    private var tier: VisibilityTier { friend.sharesWithMe.tier }
    private var day: FriendDay { store.friendDay(for: friend) }

    private var liveFriend: Friend { store.friend(by: friend.id) ?? friend }
    private var texture: ConnectionTexture { store.connectionTexture(for: friend) }
    private var accent: Color { Color(hex: friend.accentColorHex) }

    private var sharedCircles: [FFCircle] { store.sharedCircles(withFriendId: friend.id) }
    private var sharedPacts: [Pact] { store.sharedPacts(withFriendId: friend.id) }
    private var togetherCount: Int { sharedCircles.count + sharedPacts.count }

    private var myUserId: String? { auth.user?.id }

    private var remoteProfile: RemoteProfile? { socialSync.profile(forLocal: friend.id) }
    private var publishedCard: SeasonCard? { liveFriend.seasonCard ?? remoteProfile?.card }

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

    private var friendStoryPosts: [StoryPost] {
        store.activeFriendStories.filter { $0.authorId == friend.id }
    }
    private var storyUnitCount: Int { friendStoryPosts.count }
    private var viewedStoryUnitCount: Int {
        friendStoryPosts.filter { store.viewedStoryPostIds.contains($0.id) }.count
    }
    /// The latest story frame, falling back through every available
    /// copy — thumbnail, saved file, then the uploaded cloud copy — so
    /// the avatar preview reliably appears while a story is live.
    private var storyPreviewURL: URL? {
        let media = store.storyThumbMedia(forFriendId: friend.id)
        return media?.resolvedThumbnailURL ?? media?.resolvedLocalURL ?? media?.remoteURL
    }

    private var headerPhotoURL: URL? {
        liveFriend.headerURL ?? remoteProfile?.headerURL
    }

    private var shortSeasonName: String? {
        let raw = publishedCard?.seasonName ?? friend.currentSeasonName
        guard let full = raw else { return nil }
        let trimmed = full.replacingOccurrences(of: " Season", with: "")
        return trimmed.isEmpty ? full : trimmed
    }

    /// The sun-ring ratio — their day, resolved to the tier they share.
    private var ringRatio: Double {
        switch tier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    private var horizonRatios: [Double] { Array(day.rhythmBars.suffix(7)) }

    private var statusText: String {
        if let mood = publishedCard?.moodLine, !mood.isEmpty { return mood }
        return makeWitnessLine(day: day, card: publishedCard) ?? "A quieter stretch."
    }

    private var handle: String? { remoteProfile?.handle }
    /// The friend's all-time counter — omitted entirely when it's
    /// unavailable at their tier or would read "0 days shown up".
    private var daysShownUp: Int? {
        guard let days = publishedCard?.lifetimeDays, days > 0 else { return nil }
        return days
    }
    private var weekday: String { Date().formatted(.dateTime.weekday(.wide)) }
    /// Redline: hero photo is 34% of screen height; the identity card
    /// overlaps its bottom edge by `heroOverlap`.
    private var headerHeight: CGFloat { UIScreen.main.bounds.height * 0.34 }
    private let heroOverlap: CGFloat = 58

    /// Live scroll offset — drives the collapsing top bar.
    @State private var scrollOffset: CGFloat = 0

    /// 0 over the photo → 1 once the card's name slides under the bar.
    private var collapseProgress: Double {
        let start = headerHeight - 170
        return Double(min(1, max(0, (scrollOffset - start) / 70)))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    MirrorHeroHeader(
                        headerURL: headerPhotoURL,
                        accent: accent,
                        strength: tier == .quiet ? 0.5 : (0.15 + 0.85 * min(1, ringRatio)),
                        height: headerHeight
                    )

                    identityCard
                        .padding(.horizontal, 16)
                        .offset(y: -heroOverlap)
                        .padding(.bottom, -heroOverlap)
                        .zIndex(1)

                    journalBody
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 20)

                    Color.clear.frame(height: 130)
                }
                .containerRelativeFrame(.horizontal)
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, offset in
                scrollOffset = offset
            }

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
        .overlay(alignment: .top) { topBar }
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
        .sheet(item: $dayRef) { ref in
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    PastDaySnapshotView(date: ref.date, showsScoreCard: false)
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.vertical, 16)
                        .environment(store)
                }
                .background(Theme.warmWheat)
                .navigationTitle(ref.date.formatted(.dateTime.weekday(.wide).month().day()))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.warmWheat, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dayRef = nil }.foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .presentationDetents([.large])
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
            "Mute \(friend.displayName)?",
            isPresented: $showMuteConfirm,
            titleVisibility: .visible
        ) {
            Button("Mute") {
                Task { await muteFriend() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Their stories leave your feed and their notifications stop arriving. You stay friends, this page stays open to you, and they are never told.")
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
            if let remote = remoteProfile, let myId = myUserId {
                ProofThreadView(friend: remote, message: messageGraph, myUserId: myId)
                    .environment(store)
                    .environment(auth)
                    .environment(moderation)
                    .environment(socialSync)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                // Never a local-only composer — a message that can't be
                // delivered is worse than a clear "sign in first".
                ThreadUnavailableView(friendName: friend.displayName)
                    .environment(auth)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showStories) {
            StoryPlayerView(mode: .friend(friend))
                .navigationTransition(.zoom(sourceID: "frienddetail-story", in: storyZoom))
                .environment(store)
        }
        .fullScreenCover(isPresented: $showSendProof) {
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
                // A proof that can't reach its person shouldn't pretend
                // to send — surface the sign-in doorway instead.
                ThreadUnavailableView(friendName: friend.displayName)
                    .environment(auth)
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
        .task { await loadProfileTexture() }
    }

    // MARK: - Friend-control actions

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

    /// Quiet this person. Unlike block and unfriend, nothing here is
    /// severed and the page stays open — so we deliberately do NOT
    /// dismiss. The only visible change is that their moments stop
    /// arriving uninvited.
    private func muteFriend() async {
        guard let remote = remoteProfile, let myId = myUserId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await moderation.mute(remote.id, myUserId: myId)
    }

    private func unmuteFriend() async {
        guard let remote = remoteProfile, let myId = myUserId else { return }
        await moderation.unmute(remote.id, myUserId: myId)
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

    // MARK: - Top bar

    private var topBar: some View {
        MirrorTopBar(title: friend.displayName, progress: collapseProgress) {
            MirrorGlassControl(icon: "chevron.left", label: "Back to Friends") {
                dismiss()
            }
        } trailing: {
            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSharingSettings = true
                } label: {
                    Label("What \(friend.displayName) sees", systemImage: "eye")
                }
                if let remote = remoteProfile {
                    Divider()
                    // The gentle option first: quieting someone should be
                    // easier to reach than severing them.
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if moderation.isMuted(remote.id) {
                            Task { await unmuteFriend() }
                        } else {
                            showMuteConfirm = true
                        }
                    } label: {
                        Label(
                            moderation.isMuted(remote.id)
                                ? "Unmute \(friend.displayName)"
                                : "Mute \(friend.displayName)",
                            systemImage: moderation.isMuted(remote.id) ? "bell" : "bell.slash"
                        )
                    }
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
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            Circle().fill(Color.black.opacity(0.30))
                        }
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                    .contentShape(Circle())
            }
            .accessibilityLabel("More options")
        }
    }

    private var avatarButton: some View {
        Button {
            guard hasAnyStories else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showStories = true
        } label: {
            SunRingAvatar(
                ratio: ringRatio,
                diameter: 78,
                photoURL: friend.avatarURL,
                initials: friend.initials,
                fillColor: accent,
                storyUnitCount: storyUnitCount,
                viewedUnitCount: viewedStoryUnitCount,
                storyPreviewURL: storyPreviewURL,
                reduceMotion: reduceMotion,
                shimmer: hasUnviewedStories
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "frienddetail-story", in: storyZoom)
        .accessibilityLabel(hasUnviewedStories ? "\(friend.displayName), new story" : friend.displayName)
    }

    // MARK: - Identity card (friend)

    private var identityCard: some View {
        MirrorIdentityCard(
            name: friend.displayName,
            handle: handle,
            daysShownUp: daysShownUp,
            statusText: statusText,
            avatar: { avatarButton },
            meta: {
                VStack(alignment: .leading, spacing: 9) {
                    if let name = shortSeasonName {
                        MirrorSeasonPill(
                            seasonName: name,
                            dayNumber: publishedCard?.currentDay ?? friend.currentSeasonDay,
                            accent: accent
                        )
                    }
                    if !mutuals.isEmpty {
                        mutualsButton
                    }
                }
            },
            actions: { actionRow }
        )
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            friendPill
            MirrorActionCircle(
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

    @ViewBuilder
    private var friendPill: some View {
        switch relationship {
        case .friends, .isMe:
            MirrorPrimaryPill(title: "Friends", icon: "checkmark", isWorking: isRelationshipWorking) {
                showUnfriendConfirm = true
            }
        case .none:
            MirrorPrimaryPill(title: "Add friend", icon: "person.badge.plus", isWorking: isRelationshipWorking) {
                guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
                isRelationshipWorking = true
                Task {
                    await friendGraph.sendRequest(to: remote, myUserId: myId)
                    isRelationshipWorking = false
                }
            }
        case .requestSent:
            MirrorPrimaryPill(title: "Requested", icon: "hourglass", filled: false) { }
                .allowsHitTesting(false)
        case .requestReceived:
            MirrorPrimaryPill(title: "Accept request", icon: "checkmark.circle", isWorking: isRelationshipWorking) {
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

    // MARK: - Journal body

    private var journalBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            if tier != .quiet {
                MirrorDayBlock(
                    ratio: ringRatio,
                    weekday: weekday,
                    seasonName: shortSeasonName ?? "This season",
                    horizonRatios: horizonRatios,
                    accent: accent,
                    onTapDay: openDay
                )

                if !categorySections.isEmpty {
                    MirrorTodayBoard(sections: categorySections, showsRows: tier == .full)
                }

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
            } else {
                quietNote
            }

            recordBelow
        }
    }

    // MARK: Quiet tier

    private var quietNote: some View {
        Text("\(friend.displayName) shares a little with you — their season and this line, nothing about their day.")
            .font(.serifItalic(14, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

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
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.5))
    }

    private func mutualInitials(_ profile: RemoteProfile) -> some View {
        ZStack {
            Color(hex: RemoteIDMapper.accentHex(forRemoteId: profile.id))
            Text(profile.initials)
                .font(.sans(9, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    // MARK: Categories

    /// The friend's board grouped by category, resolved to their tier.
    /// Full shows real task rows; Open shows count-only headers (task
    /// names stay private), driven by completion counts.
    private var categorySections: [(Category, [MirrorTaskRow])] {
        if tier == .full {
            var order: [Category] = []
            var byCat: [Category: [MirrorTaskRow]] = [:]
            for task in day.tasks {
                if byCat[task.category] == nil { order.append(task.category) }
                byCat[task.category, default: []].append(MirrorTaskRow(title: task.title, isDone: task.isDone))
            }
            return order.map { cat in
                let rows = (byCat[cat] ?? []).sorted { $0.isDone && !$1.isDone }
                return (cat, rows)
            }
        } else {
            return day.categoryBreakdown.map { entry in
                let done = Array(repeating: MirrorTaskRow(title: "", isDone: true), count: entry.done)
                let open = Array(repeating: MirrorTaskRow(title: "", isDone: false), count: max(0, entry.total - entry.done))
                return (entry.category, done + open)
            }
        }
    }

    // MARK: Record below

    private var recordBelow: some View {
        VStack(alignment: .leading, spacing: 22) {
            if tier != .quiet {
                pointsPrivateRow
            }

            if let witness = witnessLine {
                WitnessLineView(text: witness, accent: accent)
            }

            if tier != .quiet, let milestones = publishedCard?.milestones, !milestones.isEmpty {
                destinationsSection(milestones)
            }

            if let past = publishedCard?.pastSeasons, !past.isEmpty {
                seasonsBeforeSection(past)
            }

            togetherSection

            sinceConnectedSection
        }
        .padding(.top, 2)
    }

    private var witnessLine: String? {
        guard tier != .quiet else { return nil }
        return makeWitnessLine(day: day, card: publishedCard)
    }

    // MARK: Points — privacy as a feature

    /// One honest line: points never leave their owner. Friends see the
    /// shape of a day — never the numbers. No ask flow, no exceptions.
    private var pointsPrivateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text("Points stay private — you see the shape of \(friend.displayName)'s day, never the numbers.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("\(friend.displayName)'s points are private")
    }

    // MARK: Destinations

    private func destinationsSection(_ milestones: [SeasonCardMilestone]) -> some View {
        MirrorSectionCard(label: "THE SEASON’S DESTINATIONS") {
            DestinationsTimeline(
                milestones: milestones,
                accent: accent,
                seasonStart: publishedCard?.seasonStartDate
            )
        }
    }

    // MARK: Seasons before

    private func seasonsBeforeSection(_ past: [PastSeasonSummary]) -> some View {
        MirrorSectionCard(label: "SEASONS BEFORE") {
            SeasonsBeforeRow(chapters: past, showsMilestones: tier != .quiet)
        }
    }

    // MARK: Together

    private var togetherSection: some View {
        MirrorSectionCard(label: togetherCount > 0 ? "TOGETHER · \(togetherCount) SHARED" : "TOGETHER") {
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
        MirrorSectionCard(
            label: "SINCE YOU CONNECTED · \(store.connectedDescription(friend).uppercased().replacingOccurrences(of: "CONNECTED ", with: ""))"
        ) {
            VStack(alignment: .leading, spacing: 14) {
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

    private func openDay(daysAgo: Int) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        dayRef = DayRef(date: Calendar.current.startOfDay(for: date))
    }

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
        if youToday && themToday { return "You both showed up today" }
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
