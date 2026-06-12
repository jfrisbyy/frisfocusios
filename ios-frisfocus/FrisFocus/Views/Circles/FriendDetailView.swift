//
//  FriendDetailView.swift
//  FrisFocus
//
//  The friend profile, restructured into a relationship **hub** that
//  flows from *them* → *us*. It is the single home for everything
//  between you and one person.
//
//   • Header (their signature color): avatar carries a story ring —
//     tapping it opens their stories. Name, season, "connected N months."
//   • Action row: Send a proof · Message (link-out) · Cheer.
//   • THEM — the witnessing layer, gated by THEIR visibility tier
//     (quiet / open / full). Full shows the real day: routines, a task
//     checklist (open items grey, never red), focus, milestone, react row.
//   • US — Together (shared circles + pacts), Privately (a link-out to
//     the proof/message thread, never inline), Since you connected
//     (relationship texture), and Sharing & connection settings.
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
    /// season info, past chapters. Prefers the synced Friend record;
    /// falls back to the cached remote profile.
    private var publishedCard: SeasonCard? { liveFriend.seasonCard ?? remoteProfile?.card }

    /// The live connection state — drives the hero pill. People on
    /// this page are friends in practice, but the pill stays honest if
    /// the graph changed underneath (an unfriend elsewhere).
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

    private var moodText: String {
        tier == .full ? day.moodLine : store.headlineFromFriend(friend)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 20) {
                        seasonProgressStrip
                        themLayer
                        chaptersBlock
                        Divider().overlay(Theme.textPrimary.opacity(0.08))
                        usLayer
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 18)
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

    /// Mutual friends + join date — the hero's relationship texture.
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

    /// The poster hero: the friend's season cover (or header photo /
    /// accent band) with their identity, season title, intention, and
    /// the friend pill carved into it.
    @ViewBuilder
    private var hero: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 54)
                .padding(.horizontal, Theme.pageHorizontalPadding)

            VStack(spacing: 6) {
                storyRingAvatar

                if hasUnviewedStories {
                    Text("● \(unviewedStoryCount) NEW \(unviewedStoryCount == 1 ? "STORY" : "STORIES") · TAP TO VIEW")
                        .font(.sans(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.sunCore)
                } else if hasAnyStories {
                    Text("TAP TO VIEW STORY")
                        .font(.sans(10, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                }

                Text(friend.displayName)
                    .font(.serif(27, weight: .medium))
                    .foregroundStyle(Theme.textCream)

                Text(metaLine)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.82))

                seasonTitleBlock
                    .padding(.top, 10)

                friendPillRow
                    .padding(.top, 12)
            }
            .padding(.top, 8)
            .padding(.horizontal, Theme.pageHorizontalPadding)

            actionRow
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            ProfilePosterBackground(
                coverId: publishedCard?.coverId,
                headerURL: headerPhotoURL,
                accent: accent
            )
        )
    }

    /// The friend's custom header background, when they've set one.
    /// Prefers the synced Friend record; falls back to the cached
    /// remote profile for people resolved outside the friend list.
    private var headerPhotoURL: URL? {
        liveFriend.headerURL ?? remoteProfile?.headerURL
    }

    /// Handle · joined · connected — the quiet identity facts.
    private var metaLine: String {
        var parts: [String] = []
        if let handle = remoteProfile?.handle { parts.append(handle) }
        if let joinedDate {
            parts.append("Joined \(joinedDate.formatted(.dateTime.month(.abbreviated).year()))")
        }
        parts.append(store.connectedDescription(friend))
        return parts.joined(separator: " · ")
    }

    /// The season title carved into the poster — big serif name,
    /// "DAY N", and the owner's intention line.
    @ViewBuilder
    private var seasonTitleBlock: some View {
        if let seasonName = shortSeasonName {
            VStack(spacing: 5) {
                Text(seasonName)
                    .font(.serif(32, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)

                if let day = publishedCard?.currentDay ?? friend.currentSeasonDay {
                    Text(seasonDayLine(day))
                        .font(.sans(10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.textCream.opacity(0.85))
                }

                if let intention = publishedCard?.intention, !intention.isEmpty {
                    Text("“\(intention)”")
                        .font(.serifItalic(14, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func seasonDayLine(_ day: Int) -> String {
        if let length = publishedCard?.seasonLengthDays, length > 0 {
            return "DAY \(day) OF \(length)"
        }
        return "DAY \(day)"
    }

    // MARK: Friend pill + mutuals

    private var friendPillRow: some View {
        VStack(spacing: 8) {
            friendPill
            if !mutuals.isEmpty {
                mutualsButton
            }
        }
    }

    /// The honest relationship pill — Friends ✓ (tap to unfriend),
    /// Add friend, Requested, or Accept request.
    @ViewBuilder
    private var friendPill: some View {
        switch relationship {
        case .friends, .isMe:
            heroPillButton(icon: "checkmark", title: "Friends", filled: false) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUnfriendConfirm = true
            }
            .accessibilityLabel("Friends with \(friend.displayName). Tap for options.")
        case .none:
            heroPillButton(icon: "person.badge.plus", title: "Add friend", filled: true) {
                guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isRelationshipWorking = true
                Task {
                    await friendGraph.sendRequest(to: remote, myUserId: myId)
                    isRelationshipWorking = false
                }
            }
        case .requestSent:
            heroPillLabel(icon: "hourglass", title: "Requested")
        case .requestReceived:
            heroPillButton(icon: "checkmark.circle", title: "Accept request", filled: true) {
                guard let remote = remoteProfile, let myId = myUserId, !isRelationshipWorking else { return }
                guard let request = friendGraph.incoming.first(where: { $0.profile.id == remote.id }) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isRelationshipWorking = true
                Task {
                    await friendGraph.accept(request, myUserId: myId)
                    await socialSync.refreshFriends()
                    isRelationshipWorking = false
                }
            }
        }
    }

    private func heroPillButton(icon: String, title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isRelationshipWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(filled ? Theme.textPrimary : Theme.textCream)
                } else {
                    Image(systemName: icon)
                        .font(.sans(12, weight: .bold))
                }
                Text(title)
                    .font(.sans(14, weight: .semibold))
            }
            .foregroundStyle(filled ? Theme.textPrimary : Theme.textCream)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Theme.textCream : Color.white.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(filled ? 0 : 0.45), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRelationshipWorking)
    }

    private func heroPillLabel(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.sans(12, weight: .semibold))
            Text(title)
                .font(.sans(14, weight: .semibold))
        }
        .foregroundStyle(Theme.textCream.opacity(0.8))
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.3), lineWidth: 1)
        )
    }

    /// Overlapping mutual avatars + "N friends in common" — taps open
    /// the full list.
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
                Text("\(mutuals.count) friend\(mutuals.count == 1 ? "" : "s") in common")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.9))
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
        .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.8), lineWidth: 1.2))
    }

    private func mutualInitials(_ profile: RemoteProfile) -> some View {
        ZStack {
            Color(hex: RemoteIDMapper.accentHex(forRemoteId: profile.id))
            Text(profile.initials)
                .font(.sans(9, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    private var shortSeasonName: String? {
        guard let full = friend.currentSeasonName else { return nil }
        let trimmed = full.replacingOccurrences(of: " Season", with: "")
        return trimmed.isEmpty ? full : trimmed
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.sans(15, weight: .medium))
                    Text("Friends").font(.sans(14, weight: .regular))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
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
                    .font(.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
        }
    }

    /// Avatar + story ring. Lit gold (with a slow shimmer) when there
    /// are unviewed stories; muted when all seen; a quiet cream ring
    /// when they have no active story. Tapping opens their stories.
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
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .padding(5)
                .overlay { ringOverlay }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasAnyStories)
        .matchedTransitionSource(id: "frienddetail-story", in: storyZoom)
        .accessibilityLabel(hasUnviewedStories ? "\(friend.displayName), \(unviewedStoryCount) new stories" : friend.displayName)
    }

    /// Initials on the signature color — the fallback when this person
    /// has no profile photo (or while it loads).
    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(accent)
            Text(friend.initials)
                .font(.sans(26, weight: .medium))
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
            Circle().strokeBorder(Theme.textCream.opacity(0.4), lineWidth: 2)
        } else {
            Circle().strokeBorder(Theme.textCream.opacity(0.55), lineWidth: 1)
        }
    }

    // MARK: - Action row (inside the hero)

    /// Compact icon-only circles — camera, chat bubble, clapping hands
    /// — so the hero reads calm. The proof button stays solid cream as
    /// the primary action; each keeps its spoken label.
    private var actionRow: some View {
        HStack(spacing: 18) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSendProof = true
            } label: {
                actionIcon("camera.fill", filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send a proof to \(friend.displayName)")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showThread = true
            } label: {
                actionIcon("bubble.left.and.bubble.right.fill", filled: false, dot: unreadFromFriend > 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unreadFromFriend > 0 ? "Message \(friend.displayName), \(unreadFromFriend) unread" : "Message \(friend.displayName)")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCheerComposer = true
            } label: {
                actionIcon("hands.clap.fill", filled: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cheer \(friend.displayName)")
        }
        .frame(maxWidth: .infinity)
    }

    /// One glassy icon circle on the accent band. The filled (cream)
    /// variant marks the primary action.
    private func actionIcon(_ icon: String, filled: Bool, dot: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: icon)
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(filled ? Theme.textPrimary : Theme.textCream)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(filled ? Theme.textCream : Color.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Theme.textCream.opacity(filled ? 0 : 0.35), lineWidth: 0.8)
                )

            if dot {
                Circle()
                    .fill(Theme.alertRed)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.8))
                    .offset(x: -1, y: 1)
            }
        }
        .contentShape(Circle())
    }

    // MARK: - THEM layer

    @ViewBuilder
    private var themLayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(friend.displayName.uppercased()) TODAY · \(tierShareLabel.uppercased())")
                .font(.sans(10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            if tier == .quiet {
                quietGlance
            } else {
                dayGlanceCard
            }

            if tier == .open {
                effortBreakdownCard
            }

            if tier == .full {
                fullChecklistCard
                routinesCard
                focusMilestoneRow
            }

            if tier != .quiet {
                exactPointsRow
                rhythmFooter
            }
        }
    }

    /// Milestone progress for the current season — the "this season"
    /// strip under the hero. Only when their tier shares goal status
    /// and a card with milestones was published.
    @ViewBuilder
    private var seasonProgressStrip: some View {
        if tier != .quiet,
           let published = publishedCard,
           let total = published.milestonesTotal, total > 0 {
            let done = published.milestonesDone ?? 0
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel("THIS SEASON")
                    Spacer()
                    Text("\(done) of \(total) milestones")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(done == total && total > 0 ? Theme.alertGreen : Theme.textPrimary.opacity(0.65))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.textPrimary.opacity(0.08))
                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * CGFloat(min(1, Double(done) / Double(max(1, total)))))
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glanceBackground)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(done) of \(total) milestones reached this season")
        }
    }

    private var tierShareLabel: String {
        switch tier {
        case .quiet: return "shares a little with you"
        case .open:  return "shares the shape with you"
        case .full:  return "shares their full day with you"
        }
    }

    // MARK: - Day at a glance (the lead)

    /// The warm, task-focused lead for Open / Full: a signature-color
    /// progress ring beside the mood line. At Full the complete grouped
    /// checklist lives in its own card right below, so the glance stays
    /// a glance.
    private var dayGlanceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            dayRing
            VStack(alignment: .leading, spacing: 6) {
                Text(moodText)
                    .font(.serifItalic(18, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                if tier == .open {
                    Text("The shape of their day")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                } else if day.openCount > 0 {
                    Text("\(day.openCount) still open — the day’s not over.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glanceBackground)
    }

    // MARK: Full — the complete checklist, grouped by category

    /// The friend's whole day, the way their own Work zone reads it:
    /// grouped by life category with the category's color dot and a
    /// per-category "done of total". Done items tick green; open items
    /// stay gentle grey — never red, never "failed."
    private var fullChecklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("THEIR LIST · \(day.doneCount) OF \(day.totalCount) DONE")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(day.categoryBreakdown.enumerated()), id: \.element.category) { idx, group in
                    if idx > 0 {
                        Rectangle().fill(Theme.textPrimary.opacity(0.06)).frame(height: 0.5)
                            .padding(.horizontal, 14)
                    }
                    categoryGroup(group.category, done: group.done, total: group.total)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
        }
    }

    private func categoryGroup(_ category: Category, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(category.color).frame(width: 7, height: 7)
                Text(category.displayName.uppercased())
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(category.darkColor)
                Spacer()
                Text("\(done) of \(total)")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(done == total ? Theme.alertGreen : Theme.textPrimary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 4)

            ForEach(tasksInCategory(category)) { task in
                checklistRow(task)
            }
        }
        .padding(.bottom, 9)
    }

    /// Tasks for one category, done items first so the wins lead.
    private func tasksInCategory(_ category: Category) -> [FriendDayTask] {
        day.tasks
            .filter { $0.category == category }
            .sorted { $0.isDone && !$1.isDone }
    }

    private func checklistRow(_ task: FriendDayTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.sans(15, weight: task.isDone ? .semibold : .regular))
                .foregroundStyle(task.isDone ? Theme.alertGreen : Theme.textPrimary.opacity(0.25))
            Text(task.title)
                .font(.sans(14, weight: task.isDone ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(task.isDone ? 0.9 : 0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .accessibilityLabel("\(task.title), \(task.isDone ? "done" : "still open")")
    }

    // MARK: Open — effort by category, no task names

    /// The Open-tier breakdown: where their completed effort went today,
    /// as colored category segments — the shape of the day without a
    /// single task name leaking through.
    @ViewBuilder
    private var effortBreakdownCard: some View {
        let groups = day.categoryBreakdown.filter { $0.done > 0 }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("WHERE THEIR EFFORT WENT")
                VStack(alignment: .leading, spacing: 12) {
                    effortSegmentBar(groups)
                    FlowLayout(spacing: 12, lineSpacing: 8) {
                        ForEach(groups, id: \.category) { group in
                            HStack(spacing: 5) {
                                Circle().fill(group.category.color).frame(width: 7, height: 7)
                                Text("\(group.category.displayName) · \(group.done)")
                                    .font(.sans(12, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                            }
                        }
                    }
                    Text("Counts only — \(friend.displayName) keeps the specifics private.")
                        .font(.serifItalic(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card)
            }
        }
    }

    private func effortSegmentBar(_ groups: [(category: Category, done: Int, total: Int)]) -> some View {
        let totalDone = max(1, groups.reduce(0) { $0 + $1.done })
        return GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(groups, id: \.category) { group in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(group.category.color.opacity(0.85))
                        .frame(width: max(8, (proxy.size.width - CGFloat(groups.count - 1) * 3) * CGFloat(group.done) / CGFloat(totalDone)))
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Effort by category")
    }

    /// Quiet tier: just a warm mood line and their season — calm and
    /// minimal, matching exactly what they chose to reveal.
    private var quietGlance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.sans(16, weight: .regular))
                    .foregroundStyle(accent)
                    .padding(.top, 2)
                Text(moodText)
                    .font(.serifItalic(17, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let season = shortSeasonName {
                HStack(spacing: 7) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(friend.currentSeasonDay.map { "\(season) · day \($0)" } ?? season)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glanceBackground)
    }

    /// The signature-color progress ring. Full reads the real completion
    /// with a "done / total" center; Open shows momentum behind a soft
    /// sun so no specific tasks leak.
    private var dayRing: some View {
        DayProgressRing(fraction: ringFill, tint: accent, lineWidth: 9) {
            Group {
                if tier == .full {
                    VStack(spacing: 0) {
                        Text("\(day.doneCount)")
                            .font(.serif(28, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(day.totalCount)")
                            .font(.sans(10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    }
                } else {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement()
        .accessibilityLabel(tier == .full ? "\(day.doneCount) of \(day.totalCount) done today" : "Showing up")
    }

    /// The warm wash behind the glance card — the person's signature
    /// color at low opacity so the lead feels theirs.
    private var glanceBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(accent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.20), lineWidth: 0.5)
            )
    }

    /// Target fill for the day ring — completion at Full, momentum at
    /// Open, empty at Quiet.
    private var glanceRingFraction: Double {
        switch tier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    // MARK: Full — routines

    private var routinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ROUTINES TODAY")
            VStack(spacing: 0) {
                ForEach(Array(day.routines.enumerated()), id: \.element.id) { idx, routine in
                    if idx > 0 {
                        Rectangle().fill(Theme.textPrimary.opacity(0.07)).frame(height: 0.5)
                    }
                    routineRow(routine)
                }
            }
            .background(card)
        }
    }

    private func routineRow(_ routine: FriendRoutine) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(routine.isComplete ? Theme.alertGreen : Theme.sunWarm.opacity(0.28))
                    .frame(width: 26, height: 26)
                Image(systemName: routine.isComplete ? "checkmark" : "square.fill")
                    .font(.sans(routine.isComplete ? 12 : 9, weight: .bold))
                    .foregroundStyle(routine.isComplete ? Theme.textCream : Theme.sunShadow)
            }
            Text(routine.title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(routine.detail)
                .font(.sans(12, weight: routine.isComplete ? .medium : .regular))
                .foregroundStyle(routine.isComplete ? Theme.alertGreen : Theme.textPrimary.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Exact points (behind explicit permission)

    /// Point values are private calibration — they encode what's
    /// personally hard for someone — so they never surface by default.
    /// This row is the explicit ask: locked → asked → shared.
    @ViewBuilder
    private var exactPointsRow: some View {
        switch liveFriend.pointsAccess {
        case .granted:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(day.todayLogged) points today")
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(friend.displayName) shares exact points with you")
                        .font(.sans(11.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .transition(.opacity)
            .accessibilityLabel("\(friend.displayName) logged \(day.todayLogged) points today")

        case .requested:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                Text("Asked to see exact points · waiting on \(friend.displayName)")
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .transition(.opacity)
            .accessibilityLabel("Waiting on \(friend.displayName) to share exact points")

        case nil:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                Text("Exact points are private")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.requestExactPoints(friendId: friend.id)
                    }
                } label: {
                    Text("Ask to see")
                        .font(.sans(12.5, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask \(friend.displayName) to see exact points")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(card)
        }
    }

    // MARK: - Reframed rhythm footer

    /// The old three big stat cards, collapsed into one quiet line about
    /// showing up with a small sparkline beside it. Present for anyone
    /// who wants it, but it no longer leads or dominates the page.
    private var rhythmFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Showing up \(day.rhythmDays) days · \(day.rhythmSummary)")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                miniSparkline
                Text("LAST 10 DAYS")
                    .font(.sans(8, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card)
    }

    private var miniSparkline: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(day.rhythmBars.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(v < 0.18 ? Theme.textPrimary.opacity(0.14) : accent.opacity(0.5))
                    .frame(width: 5, height: max(5, 26 * v))
            }
        }
        .frame(height: 26)
    }

    // MARK: Full — focus + milestone

    /// Focus + milestone merged into a single card split by a hairline
    /// — two stats, one quiet row, half the chrome.
    private var focusMilestoneRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FOCUS")
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text(day.focusText)
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(day.focusSessions) session\(day.focusSessions == 1 ? "" : "s")")
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Theme.textPrimary.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(day.milestoneTitle.uppercased())
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
                Text(day.milestoneProgress)
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(day.milestoneAddedToday ? "+ today" : "no change")
                    .font(.sans(10, weight: .medium))
                    .foregroundStyle(day.milestoneAddedToday ? Theme.alertGreen : Theme.textPrimary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(card)
    }

    // MARK: - Past chapters

    /// The friend's story season by season — a scrollable rail of
    /// chapter posters built from their published season card. Quiet
    /// friends see names + lengths only; Open / Full also see
    /// milestones reached.
    @ViewBuilder
    private var chaptersBlock: some View {
        let past = publishedCard?.pastSeasons ?? []
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("PAST CHAPTERS · \(past.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(past) { chapter in
                            PastSeasonChapterCard(
                                chapter: chapter,
                                showsMilestones: tier != .quiet
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - US layer

    @ViewBuilder
    private var usLayer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Between you & \(friend.displayName)")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            togetherBlock
            sinceConnectedBlock
        }
    }

    private var togetherBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(togetherCount > 0 ? "TOGETHER · \(togetherCount) SHARED" : "TOGETHER")
            VStack(spacing: 10) {
                ForEach(sharedCircles) { circle in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailCircle = circle
                    } label: { circleTogetherCard(circle) }
                    .buttonStyle(.plain)
                }
                ForEach(sharedPacts) { pact in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailPact = pact
                    } label: { pactTogetherCard(pact) }
                    .buttonStyle(.plain)
                }
                makePactRow
            }
        }
    }

    /// A calm dashed entry to start a two-person pact with this friend —
    /// the relationship-hub sibling of the Circles page's start/join
    /// row. Always available, even when nothing is shared yet.
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

    private func circleTogetherCard(_ circle: FFCircle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func pactTogetherCard(_ pact: Pact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var sinceConnectedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SINCE YOU CONNECTED · \(store.connectedDescription(friend).uppercased().replacingOccurrences(of: "CONNECTED ", with: ""))")
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    textureStat("\(texture.proofsTraded)", "proofs\ntraded")
                    textureStat("\(texture.cheersExchanged)", "cheers\nexchanged")
                    textureStat("\(texture.milestonesWitnessed)", "milestones\nwitnessed")
                }
                Rectangle().fill(Theme.textPrimary.opacity(0.08)).frame(height: 0.5)
                Text(texture.line)
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(card)
        }
    }

    private func textureStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.serif(25, weight: .medium))
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

    private var card: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
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

    /// A representative completion fraction for the circle today. Prefers
    /// the shared list when present (also covers hybrids); falls back to
    /// the shared number; a Witness circle has no goal, so it reads as 0.
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
/// opened from the hero's mutuals button.
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
