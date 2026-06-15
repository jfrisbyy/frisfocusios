//
//  SunZoneView.swift
//  FrisFocus
//
//  Zone 1 — the full-bleed editorial landscape. The score is no longer
//  inside the sun; it lives as a top-centre magazine headline. The
//  sun roams across the sky based on the current time of day, and the
//  whole landscape (sky, sun, ridges) shifts colour through four
//  time-of-day keyframes carried by the `SunSky` environment value.
//
//  Atmosphere stack, back → front:
//    1. Sky gradient (palette-driven)
//    2. Stars (thinned)
//    3. Crescent moon (editorial balance)
//    4. Cloud wisps (palette-tinted)
//    5. Bird flock (5 in V-formation)
//    6. Horizon glow (palette-driven)
//    7. Sun (positioned by time of day)
//    8. Film grain (subtle, overlay)
//    9. Foreground content (meta + score headline + forward sentence
//       + scroll hint)
//
//  Tapping the score band toggles `isExpanded`: the season detail
//  (`SeasonInlineDetailView`) unfolds INLINE beneath the compact band
//  with one spring — the sky continues downward and the sun + score
//  stay visible at the top while tasks are completed. The parent
//  (HomeView) owns the binding so collapsing can scroll the zone back
//  to the top of the screen.
//

import SwiftUI
import UIKit

struct SunZoneView: View {
    /// Top safe-area inset captured by the parent (HomeView) before it
    /// applies `.ignoresSafeArea(edges: .top)` to the scroll view. The
    /// foreground meta row uses this to clear the notch / Dynamic Island
    /// while the sky beneath stays full-bleed.
    var topSafeInset: CGFloat = 0
    /// Called when the user taps the top-right profile avatar. The
    /// parent (HomeView) opens the profile sheet.
    var onProfileTap: () -> Void = {}
    /// Called after the week peek unfolds the season detail on its
    /// Stats face — the parent (HomeView) glides the page down so the
    /// stats are actually in view.
    var onStatsOpened: () -> Void = {}
    /// Whether the season detail is unfolded beneath the sky band.
    /// Owned by HomeView so it can scroll home on collapse. Never
    /// persisted — the zone always starts compact on launch.
    @Binding var isExpanded: Bool

    @Environment(\.sunSky) private var sky
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FriendGraphService.self) private var friendGraph

    @State private var showDaySheet: Bool = false
    @State private var daySheetDate: Date = Date()
    @State private var showShareCamera: Bool = false
    /// Which face of the expanded season detail is showing. The score
    /// band always opens Tasks; the header week score opens Stats.
    @State private var seasonDetailTab: SeasonDetailTab = .tasks

    private var zoneHeight: CGFloat { 580 + topSafeInset }

    var body: some View {
        let palette = sky.palette

        VStack(spacing: 0) {
            compactBand(palette: palette)

            if isExpanded {
                SeasonInlineDetailView(onMinimize: collapse, activeTab: $seasonDetailTab)
                    .transition(.opacity)
                    .id(SunZoneView.statsAnchorID)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showDaySheet) {
            DayDetailSheet(selectedDate: daySheetDate)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showShareCamera) {
            ShareCameraView(context: store.dayShareContext())
        }
    }

    // MARK: - Compact sky band

    @ViewBuilder
    private func compactBand(palette: SkyPalette) -> some View {
        ZStack(alignment: .top) {
            // 1. Sky gradient
            LinearGradient(
                stops: skyStops(for: palette),
                startPoint: .top,
                endPoint: .bottom
            )

            // 2. Stars
            StarFieldView()

            // 3. Crescent moon — tucked into upper-left, editorial balance
            CrescentMoonView()
                .padding(.leading, 40)
                .padding(.top, 108)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(moonOpacity(for: sky.dayProgress))

            // 4. Cloud wisps — palette-tinted
            CloudWispsView(tint: palette.halo)

            // 5. Bird flock
            BirdFlockView(tint: palette.halo)

            // 6. Horizon glow — uses palette warmth. Faded out while
            //    the season detail is unfolded beneath (the horizon is
            //    no longer at this band's bottom edge).
            HorizonGlowView(palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(isExpanded ? 0 : 1)
                .animation(.easeInOut(duration: 0.35), value: isExpanded)

            // 7. Sun — positioned by time of day, brightness + scale
            //    driven by today's score against the season's goal.
            GeometryReader { proxy in
                let position = sky.sunPosition(in: proxy.size)
                SunView(
                    score: store.todayScore,
                    goal: store.currentSeason.dailyGoal,
                    palette: palette
                )
                .position(position)
            }

            // 8. Film grain
            FilmGrainView(strength: 0.25)

            // 9. Foreground content
            //
            //    The meta row (with the avatar) and the scroll hint stay
            //    outside the score button so the avatar tap and the
            //    visual scroll affordance stay independent. Everything
            //    in between — the score headline, the breathing space
            //    around it, the forward sentence, and the "tap for
            //    season details" hint — is one big tappable surface
            //    that unfolds the season detail in place.
            VStack(spacing: 0) {
                meta(palette: palette)

                Button {
                    toggleExpanded()
                } label: {
                    VStack(spacing: 0) {
                        // At midday the sun rides higher in the sky and
                        // sits closer to the score; push the headline
                        // down by up to 70pt so the disc stays clear of
                        // the points and both read cleanly.
                        Spacer(minLength: 22 + CGFloat(sky.middayProximity) * 70)

                        ScoreHeadlineView(
                            score: store.todayScore,
                            goal: store.currentSeason.dailyGoal
                        )

                        Spacer(minLength: 0)

                        // Cheers landing today float just above the
                        // forward sentence as a frosted glass card so
                        // they read as part of the sky rather than a
                        // feed row dropped over it. Hidden entirely
                        // when nobody has cheered the user on today.
                        let inboundCheers = store.activeCheersToday
                        if !inboundCheers.isEmpty {
                            SeasonCheerCard(cheers: inboundCheers)
                                .padding(.bottom, 14)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        // The forward sentence sits low in the sky,
                        // just above the ridges. The new dynamic copy
                        // is keyed to the current time of day + the
                        // remaining score.
                        let sentence = ForwardSentence.sentence(
                            score: store.todayScore,
                            goal: store.currentSeason.dailyGoal,
                            dayProgress: sky.dayProgress
                        )
                        Text(sentence)
                            .font(.serifItalic(18, weight: .medium))
                            .foregroundStyle(Theme.textCream.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.bottom, 14)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: sentence)

                        // Subtle affordance — the whole band above is
                        // tappable; this is the breadcrumb. Swaps to
                        // "tap to close" while the detail is open.
                        HStack(spacing: 5) {
                            Text(isExpanded ? "tap to close" : "tap for season details")
                                .font(.sans(9, weight: .medium))
                                .tracking(1.6)
                                .textCase(.uppercase)
                            Image(systemName: isExpanded ? "chevron.up" : "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textCream.opacity(0.55))
                        .padding(.bottom, 18)
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Close season details" : "Open season details")
                .accessibilityHint(
                    isExpanded
                        ? "Folds the season detail back into the sun zone"
                        : "Unfolds today's tasks grouped by category beneath the sun"
                )

                // Scroll hint — quiet affordance toward the work zone.
                // Lives outside the score button so tapping it doesn't
                // toggle; it's a visual hint, not a target. While the
                // detail is open the hint moves below the season content
                // (rendered by SeasonInlineDetailView), so this one
                // fades — keeping its layout slot so the band never
                // jumps.
                VStack(spacing: 6) {
                    Text("scroll · the work")
                        .font(.sans(9, weight: .medium))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textCream.opacity(0.5))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.5))
                }
                .padding(.bottom, 14)
                .opacity(isExpanded ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: zoneHeight)
        .clipped()
    }

    // MARK: - Expand / collapse

    private func toggleExpanded() {
        UIImpactFeedbackGenerator(style: isExpanded ? .light : .medium).impactOccurred()
        if !isExpanded { seasonDetailTab = .tasks }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    /// Scroll anchor for the unfolded season detail — HomeView scrolls
    /// here when the week peek opens the Stats face.
    static let statsAnchorID = "season.detail.anchor"

    /// Opens (or refocuses) the expanded season detail directly on its
    /// inline Stats tab — the header week score's destination — then
    /// asks the parent to glide the stats into view.
    private func openStats() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            seasonDetailTab = .stats
            isExpanded = true
        }
        onStatsOpened()
    }

    private func collapse() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            isExpanded = false
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func meta(palette: SkyPalette) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    daySheetDate = store.displayedDay
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showDaySheet = true
                } label: {
                    HStack(spacing: 6) {
                        EyebrowText(
                            text: todayDateLine,
                            opacity: 0.85,
                            color: Theme.textCream
                        )
                        .tracking(1.5)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.textCream.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open day picker")
                .accessibilityHint("View past days or plan a future day")

                Text(store.currentSeason.name)
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.95))

                Text(store.seasonDayText)
                    .font(.sans(9, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(Theme.textCream.opacity(0.65))
            }

            Spacer()

            // Right column starts with the share button + profile avatar
            // at the top corner, then drops into the week peek below.
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 10) {
                    shareButton

                    ProfileAvatarButton(
                        initials: profileStore.myProfile?.initials ?? auth.user?.initials ?? "",
                        photoURL: profileStore.myProfile?.photoURL ?? auth.user?.photoURL,
                        showDot: friendGraph.hasUnseenRequests,
                        action: onProfileTap
                    )
                }
                .padding(.bottom, 12)

                // The whole week peek — label, score, stripe — is one
                // button that unfolds the season detail on its inline
                // Stats tab.
                Button {
                    openStats()
                } label: {
                    VStack(alignment: .trailing, spacing: 0) {
                        EyebrowText(
                            text: "Week",
                            opacity: 0.75,
                            color: Theme.textCream
                        )
                        .tracking(2)
                        .padding(.bottom, 6)

                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(store.weekScore)")
                                .font(.serif(15, weight: .medium))
                                .foregroundStyle(Theme.textCream)
                                .contentTransition(.numericText(value: Double(store.weekScore)))
                                .animation(.easeOut(duration: 0.5), value: store.weekScore)
                            Text(" / \(store.currentSeason.weeklyGoal)")
                                .font(.serif(15, weight: .medium))
                                .foregroundStyle(Theme.textCream.opacity(0.55))
                        }
                        .padding(.bottom, 6)

                        WeekStripeView(dayOpacities: weekStripeOpacities)
                            .padding(.top, 2)
                            .animation(.easeOut(duration: 0.5), value: weekStripeOpacities)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Week score \(store.weekScore) of \(store.currentSeason.weeklyGoal)")
                .accessibilityHint("Unfolds the season detail on its week, month, and season stats")
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.top, max(topSafeInset, 14))
    }

    /// The discreet share entry — always the same place, never a popup.
    /// When the day is FULL (goal reached) it gains a soft amber glow
    /// ring: an invitation, not an interruption.
    private var shareButton: some View {
        let dayIsFull = store.currentSeason.dailyGoal > 0
            && store.todayScore >= store.currentSeason.dailyGoal

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showShareCamera = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(
                    Circle().strokeBorder(
                        dayIsFull
                            ? Theme.sunWarm.opacity(0.9)
                            : Theme.textCream.opacity(0.35),
                        lineWidth: dayIsFull ? 1.5 : 1
                    )
                )
                .shadow(
                    color: dayIsFull ? Theme.sunOuter.opacity(0.65) : .clear,
                    radius: dayIsFull ? 9 : 0
                )
                .animation(.easeInOut(duration: 0.6), value: dayIsFull)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share your day")
        .accessibilityHint("Opens the share camera with your day's sun on the viewfinder")
    }

    // MARK: - Helpers

    /// Locale-friendly "EEE · MMM d" string for the displayed day —
    /// today on the live home, the travelled day in the time machine.
    private var todayDateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: store.displayedDay)
    }

    /// Translate the Store's 7-day score series into the opacities the
    /// stripe expects. Today (index 6) renders at a fixed 0.9 so it always
    /// reads as "in progress". Past days scale from a 0.15 floor to 0.9
    /// based on how close they came to the daily goal.
    private var weekStripeOpacities: [Double] {
        let goal = max(1, store.currentSeason.dailyGoal)
        return store.weekStripeData.enumerated().map { index, score in
            if index == 6 { return 0.9 }
            let progress = Double(score) / Double(goal)
            return 0.15 + min(progress, 1.0) * 0.75
        }
    }

    private func skyStops(for palette: SkyPalette) -> [Gradient.Stop] {
        guard palette.skyStops.count > 1 else { return [] }
        let last = Double(palette.skyStops.count - 1)
        return palette.skyStops.enumerated().map { index, color in
            Gradient.Stop(color: color, location: Double(index) / last)
        }
    }

    /// The moon should be visible at dawn / dusk and quiet through the
    /// brightest part of the day.
    private func moonOpacity(for dayProgress: Double) -> Double {
        // Bell curve peaked at the day's edges
        if dayProgress < 0.25 {
            return 1.0 - dayProgress / 0.25 * 0.6
        }
        if dayProgress > 0.75 {
            return 0.4 + (dayProgress - 0.75) / 0.25 * 0.6
        }
        return 0.4
    }
}

#Preview {
    ScrollView {
        SunZoneView(topSafeInset: 47, isExpanded: .constant(false))
    }
    .environment(\.sunSky, .make(now: .now, coordinate: nil))
    .environment(Store())
    .environment(AuthManager())
}
