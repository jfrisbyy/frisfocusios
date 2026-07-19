//
//  MyProfileView.swift
//  FrisFocus
//
//  The user's own profile — the mirror. A full-bleed identity header
//  with the sun-ring avatar (its ring is today's sun), the merged
//  status slot, the day block (sun + qualitative line + seven-sun
//  horizon), the checked-first category boxes, and the record below.
//  Self and friend views share this exact layout; only the action row
//  differs (Edit profile + customize here).
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
    @State private var showMoodEditor: Bool = false
    @State private var moodDraft: String = ""
    @State private var dayRef: DayRef?

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

    /// Redline: header photo is 38% of screen height.
    private var headerHeight: CGFloat { UIScreen.main.bounds.height * 0.38 }

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
                    header

                    // Row center ≈ header bottom edge (44pt pill → -22).
                    actionRow
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .offset(y: -22)
                        .padding(.bottom, -22)
                        .zIndex(1)

                    bodyContent
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 16)

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

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            MirrorHeaderBackground(
                headerURL: headerPhotoURL,
                accent: accent,
                strength: 0.15 + 0.85 * min(1, todayRatio)
            )

            // 14pt avatar→name gap keeps the name block clear of the
            // halo (name starts at x = 22 + 86 + 14 = 122).
            HStack(alignment: .center, spacing: 14) {
                avatarButton
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.serif(26, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 1)
                    MirrorHandleLine(handle: handle, daysShownUp: daysShownUp)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 54)
        }
        .frame(height: headerHeight)
        .clipped()
        .overlay(alignment: .top) {
            topControls
                .padding(.top, 58)
                .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }

    private var topControls: some View {
        HStack {
            MirrorGlassControl(icon: "xmark", label: "Close your profile") {
                dismiss()
            }
            Spacer()
            MirrorGlassControl(icon: "sun.max.fill", label: "Account and settings") {
                showAccount = true
            }
        }
    }

    private var avatarButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if hasStories { showMyStories = true } else { showEditProfile = true }
        } label: {
            SunRingAvatar(
                ratio: ringRatio,
                diameter: 86,
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

    // MARK: - Action row (self)

    private var actionRow: some View {
        HStack(spacing: 9) {
            MirrorPrimaryPill(title: "Edit profile") {
                showEditProfile = true
            }
            MirrorActionCircle(icon: "paintbrush.fill", label: "Design your header") {
                showHeaderStudio = true
            }
        }
    }

    // MARK: - Body content

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            statusSlot

            if previewTier != .quiet {
                MirrorDayBlock(
                    ratio: ringRatio,
                    weekday: weekday,
                    seasonName: seasonName,
                    horizonRatios: horizonRatios,
                    accent: accent,
                    onTapDay: openDay
                )

                categoriesBlock
            } else {
                quietNote
            }

            recordBelow
        }
    }

    // MARK: Status + season + seen-as

    private var statusSlot: some View {
        VStack(alignment: .leading, spacing: 11) {
            MirrorStatusLine(text: statusText, editable: true) {
                moodDraft = store.currentSeason.moodLine ?? ""
                showMoodEditor = true
            }
            HStack(spacing: 7) {
                MirrorSeasonPill(seasonName: seasonName, dayNumber: store.currentSeasonDay, accent: accent)
                SeenAsChip(tier: $previewTier)
                Spacer(minLength: 0)
            }
        }
    }

    private var quietNote: some View {
        Text("At the Quiet level, friends see only your season and this line — nothing about your day.")
            .font(.serifItalic(14, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    // MARK: Categories

    private var categoriesBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(categorySections, id: \.0) { pair in
                MirrorCategorySection(
                    category: pair.0,
                    rows: pair.1,
                    showsBox: previewTier == .full
                )
            }
        }
    }

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
        VStack(alignment: .leading, spacing: 0) {
            if previewTier == .full {
                JournalHairline().padding(.vertical, 18)
                pointsPrivacyRow
            }

            if previewTier != .quiet, !store.mySeasonCard.milestones.isEmpty {
                JournalHairline().padding(.vertical, 18)
                destinationsSection
            }

            JournalHairline().padding(.vertical, 18)
            cheersRow

            if store.appMode == .demo {
                JournalHairline().padding(.vertical, 18)
                exitDemoRow
            }
        }
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

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalSectionHeader(label: "THE SEASON’S DESTINATIONS")
            DestinationsTimeline(
                milestones: store.mySeasonCard.milestones,
                accent: accent,
                seasonStart: store.currentSeason.startDate
            )
        }
    }

    private var cheersRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCheers = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hands.clap.fill")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cheers")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Every word that found you")
                        .font(.serifItalic(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View all cheers you’ve received and sent")
    }

    private var exitDemoRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
            store.exitDemo()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.cadenceLavenderDark)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exit demo")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Clear the sample data and start your own season")
                        .font(.sans(12.5, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cadenceLavenderWash)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cadenceLavender.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
