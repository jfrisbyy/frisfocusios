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
    private var storyPreviewURL: URL? {
        let media = store.storyThumbMedia(forFriendId: friend.id)
        return media?.resolvedThumbnailURL ?? media?.resolvedLocalURL
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
    private var daysShownUp: Int { publishedCard?.lifetimeDays ?? 0 }
    private var weekday: String { Date().formatted(.dateTime.weekday(.wide)) }
    private var headerHeight: CGFloat { max(360, UIScreen.main.bounds.height * 0.42) }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    actionRow
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .offset(y: -25)
                        .padding(.bottom, -25)
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

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            MirrorHeaderBackground(
                headerURL: headerPhotoURL,
                accent: accent,
                strength: tier == .quiet ? 0.5 : (0.15 + 0.85 * min(1, ringRatio))
            )

            HStack(alignment: .center, spacing: 15) {
                avatarButton
                VStack(alignment: .leading, spacing: 5) {
                    Text(friend.displayName)
                        .font(.serif(28, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    MirrorHandleLine(handle: handle, daysShownUp: daysShownUp)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 40)
        }
        .frame(height: headerHeight)
        .clipped()
        .overlay(alignment: .top) {
            topControls
                .padding(.top, 54)
                .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }

    private var topControls: some View {
        HStack {
            MirrorGlassControl(icon: "chevron.left", label: "Back to Friends") {
                dismiss()
            }
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
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 40, height: 40)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            Circle().fill(Color.black.opacity(0.22))
                        }
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
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
                diameter: 92,
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

    // MARK: - Action row (friend)

    private var actionRow: some View {
        HStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 18) {
            statusSlot

            if tier != .quiet {
                MirrorDayBlock(
                    ratio: ringRatio,
                    weekday: weekday,
                    seasonName: shortSeasonName ?? "This season",
                    horizonRatios: horizonRatios,
                    accent: accent,
                    onTapDay: openDay
                )

                categoriesBlock

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

    // MARK: Status + season

    private var statusSlot: some View {
        VStack(alignment: .leading, spacing: 12) {
            MirrorStatusLine(text: statusText)
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
    }

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

    private var categoriesBlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(categorySections, id: \.0) { pair in
                MirrorCategorySection(
                    category: pair.0,
                    rows: pair.1,
                    showsBox: tier == .full
                )
            }
        }
        .padding(.top, 4)
    }

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
        VStack(alignment: .leading, spacing: 0) {
            if tier != .quiet {
                JournalHairline().padding(.vertical, 18)
                exactPointsRow
            }

            if let witness = witnessLine {
                JournalHairline().padding(.vertical, 18)
                WitnessLineView(text: witness, accent: accent)
            }

            if tier != .quiet, let milestones = publishedCard?.milestones, !milestones.isEmpty {
                JournalHairline().padding(.vertical, 18)
                destinationsSection(milestones)
            }

            if let past = publishedCard?.pastSeasons, !past.isEmpty {
                JournalHairline().padding(.vertical, 18)
                seasonsBeforeSection(past)
            }

            JournalHairline().padding(.vertical, 18)
            togetherSection

            JournalHairline().padding(.vertical, 18)
            sinceConnectedSection
        }
    }

    private var witnessLine: String? {
        guard tier != .quiet else { return nil }
        return makeWitnessLine(day: day, card: publishedCard)
    }

    // MARK: Points — privacy as a feature

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
                Text("Points are private — friends ask, you approve each one.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.requestExactPoints(friendId: friend.id)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Ask")
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
