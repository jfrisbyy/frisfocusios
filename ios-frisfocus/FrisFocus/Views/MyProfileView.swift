//
//  MyProfileView.swift
//  FrisFocus
//
//  The user's own profile — a faithful mirror of the editorial page
//  friends see: the living header they designed (photo or crafted
//  sky, breathing with today's real effort), "CURRENTLY IN" + the
//  serif season name carved in, the floating identity card with the
//  one number that matters, and the hairline journal body.
//
//  Edit affordances live right on the page: a quiet "Edit header"
//  chip on the hero opens the full-screen header studio, the camera
//  disc on the avatar and the Edit profile pill open the edit screen,
//  and the mood line is settable in a tap. The Quiet / Open / Full
//  switcher previews exactly what each sharing tier reveals.
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
    @State private var showWeekSheet: Bool = false
    @State private var selectedDayId: Int = 0
    @State private var showMoodEditor: Bool = false
    @State private var moodDraft: String = ""
    @State private var ringFill: Double = 0
    @State private var storyRingPulse: Bool = false

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

    /// My signature color — the chosen season accent when set, else
    /// the auto-assigned account accent, same as friends see it.
    private var accent: Color {
        if let chosen = store.currentSeason.accentHex { return Color(hex: chosen) }
        if let myId { return Color(hex: RemoteIDMapper.accentHex(forRemoteId: myId)) }
        return Theme.textPrimary
    }

    // MARK: - Day

    private var day: FriendDay { store.myDay }

    private var hasStories: Bool { store.hasActiveMyStories }

    /// The header's living light follows my real day.
    private var headerStrength: Double {
        0.15 + 0.85 * day.completionFraction
    }

    private var ringTarget: Double {
        switch previewTier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    private var shortSeasonName: String {
        store.currentSeason.name.replacingOccurrences(of: " Season", with: "")
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
        .sheet(isPresented: $showAccount) {
            ProfileSheetView()
        }
        .sheet(isPresented: $showCheers) {
            CheerHistoryView()
                .environment(store)
        }
        .sheet(isPresented: $showWeekSheet) {
            WeekRhythmSheet(name: "Your", bars: day.rhythmBars, accent: accent)
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
        .alert("Your mood line", isPresented: $showMoodEditor) {
            TextField("e.g. resting this week", text: $moodDraft)
            Button("Save") {
                store.setMoodLine(moodDraft)
            }
            Button("Clear", role: .destructive) {
                store.setMoodLine(nil)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A small status under your intention, visible to friends until you change it.")
        }
        .onAppear {
            animateRing()
            if hasStories && !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    storyRingPulse = true
                }
            }
        }
        .onChange(of: previewTier) { _, _ in animateRing() }
    }

    private func animateRing() {
        if reduceMotion {
            ringFill = ringTarget
        } else {
            withAnimation(.easeOut(duration: 0.9)) { ringFill = ringTarget }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ProfilePosterBackground(
                coverId: store.currentSeason.coverId,
                headerURL: headerPhotoURL,
                accent: accent,
                strength: headerStrength
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("CURRENTLY IN")
                    .font(.sans(9.5, weight: .semibold))
                    .tracking(2.6)
                    .foregroundStyle(Theme.textCream.opacity(0.6))
                Text(shortSeasonName)
                    .font(.serif(33, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                Text("DAY \(store.currentSeasonDay) OF \(store.currentSeason.lengthDays)")
                    .font(.sans(10, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textCream.opacity(0.7))
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
        .overlay(alignment: .bottomTrailing) {
            editHeaderChip
                .padding(.trailing, Theme.pageHorizontalPadding)
                .padding(.bottom, 74)
        }
    }

    /// The quiet edit affordance on the hero — opens the studio.
    private var editHeaderChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showHeaderStudio = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "paintbrush.fill")
                    .font(.sans(10, weight: .semibold))
                Text("Edit header")
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.30)))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(0.3), lineWidth: 0.8)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Design your header")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close your profile")

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAccount = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account and settings")
        }
    }

    // MARK: - Identity card

    private var identityCard: some View {
        ProfileIdentityCard(
            name: displayName,
            lifetimeDays: store.lifetimeDaysShownUp,
            metaLine: handle ?? "This is you",
            intention: store.currentSeason.intention,
            moodLine: store.currentSeason.moodLine,
            onMoodTap: {
                moodDraft = store.currentSeason.moodLine ?? ""
                showMoodEditor = true
            }
        ) {
            avatarBlock
        } extra: {
            if hasStories {
                Text("YOUR STORY · TAP YOUR PHOTO TO VIEW")
                    .font(.sans(9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
        } pills: {
            HStack(spacing: 10) {
                IdentityPill(title: "Edit profile", icon: "square.and.pencil", filled: true) {
                    showEditProfile = true
                }
                IdentityRoundButton(icon: "paintbrush.fill", label: "Design your header") {
                    showHeaderStudio = true
                }
            }
        }
    }

    /// Avatar with the story ring and the small camera edit disc.
    private var avatarBlock: some View {
        Button {
            guard hasStories else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMyStories = true
        } label: {
            ZStack {
                avatarImage
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .padding(5)
                    .background(Circle().fill(Color(hex: 0xFFFBF1)))
                    .overlay { storyRingOverlay }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasStories)
        .matchedTransitionSource(id: "myprofile-story", in: storyZoom)
        .accessibilityLabel(hasStories ? "Your story — tap to view" : "Your profile photo")
        .overlay(alignment: .bottomTrailing) {
            avatarCameraDisc
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let photoURL {
            CachedImage(url: photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text(initials)
                .font(.serif(23, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var storyRingOverlay: some View {
        if hasStories {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter, Theme.sunCore, Theme.sunWarm],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .opacity(reduceMotion ? 1 : (storyRingPulse ? 1 : 0.6))
        } else {
            Circle().strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        }
    }

    /// The small charcoal camera disc on the avatar's corner — the
    /// always-present photo edit affordance.
    private var avatarCameraDisc: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showEditProfile = true
        } label: {
            ZStack {
                Circle().fill(Theme.textPrimary)
                Image(systemName: "camera.fill")
                    .font(.sans(9, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 24, height: 24)
            .overlay(Circle().strokeBorder(Color(hex: 0xFFFBF1), lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 2, y: 2)
        .accessibilityLabel("Change your profile photo")
    }

    // MARK: - Journal body

    private var journalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            tierPreviewBlock

            todaySection
                .padding(.top, 18)

            if previewTier != .quiet {
                JournalHairline()
                    .padding(.vertical, 18)
                pointsPrivacyRow
            }

            if let witness = makeWitnessLine(day: day, card: store.mySeasonCard) {
                JournalHairline()
                    .padding(.vertical, 18)
                WitnessLineView(text: witness, accent: accent)
            }

            if previewTier != .quiet, !store.mySeasonCard.milestones.isEmpty {
                JournalHairline()
                    .padding(.vertical, 18)
                destinationsSection
            }

            if !store.pastSeasons.isEmpty {
                JournalHairline()
                    .padding(.vertical, 18)
                seasonsBeforeSection
            }

            JournalHairline()
                .padding(.vertical, 18)
            cheersRow
        }
    }

    // MARK: Tier preview switcher

    private var tierPreviewBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            JournalSectionHeader(label: "AS A \(previewTier.tag) FRIEND SEES IT")

            HStack(spacing: 8) {
                ForEach(VisibilityTier.allCases, id: \.self) { tier in
                    tierPill(tier)
                }
            }

            Text(previewTier.detail)
                .font(.serifItalic(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierPill(_ tier: VisibilityTier) -> some View {
        let isSelected = previewTier == tier
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) { previewTier = tier }
        } label: {
            Text(tierName(tier))
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(isSelected ? 0 : 0.12), lineWidth: 0.5)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview as a \(tierName(tier)) friend")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tierName(_ tier: VisibilityTier) -> String {
        switch tier {
        case .quiet: return "Quiet"
        case .open: return "Open"
        case .full: return "Full"
        }
    }

    // MARK: TODAY

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalSectionHeader(
                label: "TODAY",
                trailingTitle: previewTier != .quiet ? Date().formatted(.dateTime.weekday(.abbreviated)) : nil,
                trailingAction: previewTier != .quiet ? { showWeekSheet = true } : nil
            )

            SunDayCard(days: sunDays, accent: accent, selectedId: $selectedDayId)
                .animation(.easeInOut(duration: 0.25), value: previewTier)

            if previewTier != .quiet {
                DayTaskList(day: selectedSunDay, accent: accent)
            }
        }
        .onChange(of: sunDays.count) { _, newCount in
            if selectedDayId > newCount - 1 { selectedDayId = 0 }
        }
    }

    /// The day currently selected in the card, for the list below.
    private var selectedSunDay: SunDay {
        let days = sunDays
        return days.first { $0.id == selectedDayId } ?? days.last ?? days[0]
    }

    /// The card's days, oldest first ending today. Each day is built
    /// tier-resolved from my own real records, so tapping a past sun
    /// reveals that day's true score and the tasks I actually finished.
    private var sunDays: [SunDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard previewTier != .quiet else {
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
                    chips: todayChipItems, scoreText: "\(day.todayLogged) points"
                )
            }
            return pastSunDay(daysAgo: daysAgo, date: date, ratio: ratio)
        }
    }

    private var todayChipItems: [SunDayChip] {
        switch previewTier {
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
        let score = store.score(on: date)
        switch previewTier {
        case .full:
            let tasks = store.myCompletedTasks(on: date)
            return SunDay(
                id: daysAgo, date: date, ratio: ratio,
                headline: dayHeadline(fraction: ratio, hasAnything: score > 0 || !tasks.isEmpty),
                subline: tasks.isEmpty ? nil : "\(tasks.count) done",
                chips: tasks.map { SunDayChip(title: $0.title, isDone: true) },
                scoreText: "\(score) points"
            )
        default:
            return SunDay(
                id: daysAgo, date: date, ratio: ratio,
                headline: dayHeadline(fraction: ratio, hasAnything: score > 0),
                subline: "the shape of this day",
                chips: [], scoreText: "\(score) points"
            )
        }
    }

    private var todayHeadline: String {
        switch previewTier {
        case .full:
            return store.forwardSentence
        case .open:
            return dayHeadline(fraction: day.momentum, hasAnything: !day.rhythmBars.isEmpty)
        case .quiet:
            return day.moodLine
        }
    }

    private var todaySubline: String? {
        switch previewTier {
        case .full:
            return daySubline(done: day.doneCount, total: day.totalCount)
                ?? "nothing planned yet — friends would see an open day"
        case .open:
            return "the shape of your day — no task names"
        case .quiet:
            return "\(shortSeasonName) · day \(store.currentSeasonDay)"
        }
    }

    // MARK: Points privacy

    /// Points are private calibration — friends must ask and you
    /// approve each one. Shown here so the preview reads honestly.
    private var pointsPrivacyRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock")
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text("Points are private — friends ask, you approve each one.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Destinations

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

    // MARK: Seasons before

    private var seasonsBeforeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalSectionHeader(label: "SEASONS BEFORE")
            SeasonsBeforeRow(chapters: store.pastSeasons, showsMilestones: true)
        }
    }

    // MARK: Cheers row

    /// Doorway to the full cheer ledger — every word that ever found
    /// you (and the ones you sent), beyond the day they landed.
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
}
