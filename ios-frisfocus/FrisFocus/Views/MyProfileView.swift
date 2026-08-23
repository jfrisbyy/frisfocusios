//
//  MyProfileView.swift
//  FrisFocus
//
//  The user's own profile — the mirror. A stretchy full-bleed hero
//  photo, a floating identity card anchored over its bottom edge (the
//  sun-ring avatar, name, status, season, and actions in ONE block),
//  the day card, the single today board, and the record below as
//  matching cards. A collapsing top bar carries the name once the
//  card scrolls away. Self and friend views share this exact system;
//  only the card's action slot differs (Edit profile + customize here).
//
//  Hard rule: NO denominators, fractions, or point values anywhere on
//  this page — only completions, sun language, and qualitative copy.
//

import SwiftUI
import UIKit

struct MyProfileView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previewTier: VisibilityTier = .full
    @State private var showEditProfile: Bool = false
    @State private var showHeaderStudio: Bool = false
    @State private var showAccount: Bool = false
    @State private var showMyStories: Bool = false
    @State private var showCheers: Bool = false
    @State private var showActivity: Bool = false
    @State private var showMoodEditor: Bool = false
    @State private var moodDraft: String = ""
    @State private var dayRef: DayRef?

    /// Live scroll offset — drives the collapsing top bar.
    @State private var scrollOffset: CGFloat = 0

    /// Zoom-transition namespace — the story player grows out of the
    /// avatar and shrinks back into it on dismiss.
    @Namespace private var storyZoom

    // MARK: - Identity

    private var myId: String? { auth.user?.id }

    private var displayName: String {
        profileStore.myProfile?.displayName ?? auth.user?.name ?? "You"
    }

    private var handle: String? { profileStore.myProfile?.handle }

    private var photoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var headerPhotoURL: URL? { profileStore.myProfile?.headerURL }

    private var initials: String {
        let value = profileStore.myProfile?.initials ?? auth.user?.initials ?? ""
        return value.isEmpty ? "?" : value
    }

    private var accent: Color {
        if let chosen = store.currentSeason.accentHex { return Color(hex: chosen) }
        if let myId { return Color(hex: RemoteIDMapper.accentHex(forRemoteId: myId)) }
        return Theme.textPrimary
    }

    // MARK: - Day / sun

    private var day: FriendDay { store.myDay }

    private var goal: Int { max(1, store.currentSeason.dailyGoal) }

    /// Today's true sun ratio (points ÷ target) — the number that drives
    /// the home sun, and now the avatar ring, day block, and horizon.
    private var todayRatio: Double { Double(day.todayLogged) / Double(goal) }

    /// The sun-ring ratio resolved to the currently previewed tier — a
    /// friend at that tier sees exactly this.
    private var ringRatio: Double {
        switch previewTier {
        case .full: return todayRatio
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    private var horizonRatios: [Double] { Array(day.rhythmBars.suffix(7)) }

    private var hasStories: Bool { store.hasActiveMyStories }
    private var myStoryCount: Int { store.activeMyStories.count }
    private var myViewedStoryCount: Int {
        store.activeMyStories.filter { store.viewedStoryPostIds.contains($0.id) }.count
    }
    /// The latest story frame, falling back through every available
    /// copy — thumbnail, saved file, then the uploaded cloud copy — so
    /// the avatar preview reliably appears while a story is live.
    private var storyPreviewURL: URL? {
        let media = store.myStoryThumbMedia
        return media?.resolvedThumbnailURL ?? media?.resolvedLocalURL ?? media?.remoteURL
    }

    private var seasonName: String {
        store.currentSeason.name.replacingOccurrences(of: " Season", with: "")
    }

    private var statusText: String {
        if let mood = store.currentSeason.moodLine, !mood.isEmpty { return mood }
        return makeWitnessLine(day: day, card: store.mySeasonCard) ?? "A quieter stretch — still here."
    }

    private var weekday: String { Date().formatted(.dateTime.weekday(.wide)) }

    /// Redline: hero photo is 34% of screen height; the identity card
    /// overlaps its bottom edge by `heroOverlap`.
    private var headerHeight: CGFloat { UIScreen.main.bounds.height * 0.34 }
    private let heroOverlap: CGFloat = 58

    /// 0 over the photo → 1 once the card's name slides under the bar.
    private var collapseProgress: Double {
        let start = headerHeight - 170
        return Double(min(1, max(0, (scrollOffset - start) / 70)))
    }

    /// The real all-time counter — omitted entirely when it would
    /// read "0 days shown up".
    private var daysShownUp: Int? {
        let days = store.lifetimeDaysShownUp
        return days > 0 ? days : nil
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    MirrorHeroHeader(
                        headerURL: headerPhotoURL,
                        accent: accent,
                        strength: 0.15 + 0.85 * min(1, todayRatio),
                        height: headerHeight
                    )

                    identityCard
                        .padding(.horizontal, 16)
                        .offset(y: -heroOverlap)
                        .padding(.bottom, -heroOverlap)
                        .zIndex(1)

                    bodyContent
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
        .sheet(isPresented: $showEditProfile) {
            NavigationStack {
                EditProfileView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showEditProfile = false }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
        .sheet(isPresented: $showAccount) { ProfileSheetView() }
        .sheet(isPresented: $showCheers) {
            CheerHistoryView().environment(store)
        }
        .sheet(isPresented: $showActivity) {
            RecentActivityView().environment(store)
        }
        .sheet(item: $dayRef) { ref in
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    PastDaySnapshotView(date: ref.date)
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
        .fullScreenCover(isPresented: $showHeaderStudio) {
            HeaderStudioView()
                .environment(store)
                .environment(profileStore)
                .environment(auth)
        }
        .fullScreenCover(isPresented: $showMyStories) {
            StoryPlayerView(mode: .mine)
                .navigationTransition(.zoom(sourceID: "myprofile-story", in: storyZoom))
                .environment(store)
        }
        .alert("Your status", isPresented: $showMoodEditor) {
            TextField("e.g. rebuilding quietly", text: $moodDraft)
            Button("Save") { store.setMoodLine(moodDraft) }
            Button("Clear", role: .destructive) { store.setMoodLine(nil) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A short line under your name, visible to friends until you change it.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        MirrorTopBar(title: displayName, progress: collapseProgress) {
            MirrorGlassControl(icon: "xmark", label: "Close your profile") {
                dismiss()
            }
        } trailing: {
            HStack(spacing: 8) {
                seenAsMenu
                MirrorGlassControl(icon: "sun.max.fill", label: "Account and settings") {
                    showAccount = true
                }
            }
        }
    }

    /// The tier-preview control — an eye in the glass cluster that
    /// previews the page exactly as Quiet / Open / Full friends see it.
    /// A warm dot marks an active non-full preview.
    private var seenAsMenu: some View {
        Menu {
            Section("See your page as friends do") {
                ForEach(VisibilityTier.allCases, id: \.self) { t in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.25)) { previewTier = t }
                    } label: {
                        Label(tierName(t), systemImage: previewTier == t ? "checkmark" : "eye")
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "eye")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            Circle().fill(Color.black.opacity(0.32))
                        }
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                if previewTier != .full {
                    Circle()
                        .fill(Theme.sunOuter)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                        .offset(x: -1, y: 1)
                }
            }
            .contentShape(Circle())
        }
        .accessibilityLabel("Preview how friends see you. Currently \(tierName(previewTier)).")
    }

    private func tierName(_ t: VisibilityTier) -> String {
        switch t {
        case .quiet: return "Quiet"
        case .open: return "Open"
        case .full: return "Full"
        }
    }

    // MARK: - Identity card (self)

    private var identityCard: some View {
        MirrorIdentityCard(
            name: displayName,
            handle: handle,
            daysShownUp: daysShownUp,
            statusText: statusText,
            statusEditable: true,
            onStatusEdit: {
                moodDraft = store.currentSeason.moodLine ?? ""
                showMoodEditor = true
            },
            avatar: { avatarButton },
            meta: {
                HStack(spacing: 7) {
                    MirrorSeasonPill(seasonName: seasonName, dayNumber: store.currentSeasonDay, accent: accent)
                    Spacer(minLength: 0)
                }
            },
            actions: {
                HStack(spacing: 9) {
                    MirrorPrimaryPill(title: "Edit profile") {
                        showEditProfile = true
                    }
                    MirrorActionCircle(icon: "paintbrush.fill", label: "Design your header") {
                        showHeaderStudio = true
                    }
                }
            }
        )
    }

    private var avatarButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if hasStories { showMyStories = true } else { showEditProfile = true }
        } label: {
            SunRingAvatar(
                ratio: ringRatio,
                diameter: 78,
                photoURL: photoURL,
                initials: initials,
                fillColor: Theme.textPrimary,
                storyUnitCount: myStoryCount,
                viewedUnitCount: myViewedStoryCount,
                storyPreviewURL: storyPreviewURL,
                reduceMotion: reduceMotion,
                shimmer: hasStories && myViewedStoryCount < myStoryCount
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "myprofile-story", in: storyZoom)
        .overlay(alignment: .bottomTrailing) { cameraBadge }
        .accessibilityLabel(hasStories ? "Your story — tap to view" : "Your profile photo — tap to change")
    }

    private var cameraBadge: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showEditProfile = true
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Circle().fill(Color.black.opacity(0.25))
                Image(systemName: "camera.fill")
                    .font(.sans(9, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 1, y: -1)
        .accessibilityLabel("Change your profile photo")
    }

    // MARK: - Body content

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if previewTier != .full {
                previewingNote
            }

            if previewTier != .quiet {
                MirrorDayBlock(
                    ratio: ringRatio,
                    weekday: weekday,
                    seasonName: seasonName,
                    horizonRatios: horizonRatios,
                    accent: accent,
                    onTapDay: openDay
                )

                if !categorySections.isEmpty {
                    MirrorTodayBoard(sections: categorySections, showsRows: previewTier == .full)
                }
            } else {
                quietNote
            }

            recordBelow
        }
    }

    /// The one-line banner while previewing a reduced tier — tap to
    /// return to your full page.
    private var previewingNote: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) { previewTier = .full }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.sans(11, weight: .semibold))
                Text("Previewing the \(tierName(previewTier)) view — what those friends see. Tap to show everything.")
                    .font(.sans(12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.sunShadow)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.sunWarm.opacity(0.18))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Previewing the \(tierName(previewTier)) view. Tap to show your full page.")
    }

    private var quietNote: some View {
        Text("At the Quiet level, friends see only your season and this line — nothing about your day.")
            .font(.serifItalic(14, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    // MARK: Categories

    /// Today's tasks grouped by category, preserving first-appearance
    /// order, rows sorted checked-first.
    private var categorySections: [(Category, [MirrorTaskRow])] {
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
    }

    // MARK: Record below

    private var recordBelow: some View {
        VStack(alignment: .leading, spacing: 22) {
            if previewTier == .full {
                pointsPrivacyRow
            }

            if previewTier != .quiet, !store.mySeasonCard.milestones.isEmpty {
                MirrorSectionCard(label: "THE SEASON’S DESTINATIONS") {
                    DestinationsTimeline(
                        milestones: store.mySeasonCard.milestones,
                        accent: accent,
                        seasonStart: store.currentSeason.startDate
                    )
                }
            }

            HStack(alignment: .top, spacing: 10) {
                MirrorRecordTile(
                    icon: "hands.clap.fill",
                    title: "Cheers",
                    subtitle: "Every word that found you"
                ) {
                    showCheers = true
                }
                MirrorRecordTile(
                    icon: "heart.text.square.fill",
                    title: "Activity",
                    subtitle: "Likes, comments, cheers",
                    badge: store.unseenActivityCount > 0
                ) {
                    showActivity = true
                }
            }
        }
        .padding(.top, 2)
    }

    private var pointsPrivacyRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text("Points are private — friends ask, you approve each one.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func openDay(daysAgo: Int) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        dayRef = DayRef(date: Calendar.current.startOfDay(for: date))
    }
}

/// Identifiable wrapper so a tapped day can drive `.sheet(item:)`.
struct DayRef: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
