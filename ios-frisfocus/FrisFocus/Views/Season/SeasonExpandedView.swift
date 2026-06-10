//
//  SeasonExpandedView.swift
//  FrisFocus
//
//  The page reached by tapping the score on the Sun zone. Task-only —
//  To-dos never appear here. The hero is a condensed 320 pt band that
//  reuses the live `SunSky` palette so the colour temperature matches
//  the homepage at the moment of navigation. Below the hero the page
//  is a single scroll: title strip → category pills → mode filter pills
//  → per-category sections (in season tier order, empties hidden) →
//  library actions → season footer (week + days-left + milestones).
//
//  The page is self-contained: it carries its own `TimelineView` so
//  the hero palette continues to shift through the day even while the
//  user is reading the page.
//

import SwiftUI
import UIKit

struct SeasonExpandedView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: Category? = nil
    @State private var showOpenOnly: Bool = false
    @State private var showHighValueOnly: Bool = false
    @State private var showNewTaskForm: Bool = false
    @State private var showCaptureSheet: Bool = false
    @State private var showAvoidanceManager: Bool = false
    @State private var showHabitTrains: Bool = false
    @State private var showBoosters: Bool = false
    @State private var showMilestones: Bool = false
    @State private var showSettings: Bool = false
    @State private var topSafeInset: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sky = SunSky.make(now: context.date, coordinate: nil)
            ZStack(alignment: .top) {
                Theme.warmWheat.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer the height of the fixed hero so scroll
                        // content starts below it.
                        Color.clear.frame(height: heroHeight)

                        titleStrip
                        categoryPills
                        modeFilterPills

                        ForEach(orderedVisibleCategories, id: \.self) { category in
                            CategorySectionView(
                                category: category,
                                tasks: tasksForCategory(category),
                                seasonCategory: seasonCategory(for: category)
                            )
                        }

                        // Passive Cadence outcomes (sleep / focus /
                        // wind-down) that fill themselves from verified
                        // events. Absent unless Cadence is linked.
                        CadenceEarnedSection()

                        libraryActionRow

                        seasonFooter

                        // Tail so the last content can scroll above the sundial.
                        Color.clear.frame(height: 110)
                    }
                }
                .ignoresSafeArea(edges: .top)

                // Fixed hero — stays anchored at the top while the
                // scroll view moves underneath it.
                hero(palette: sky.palette)
                    .ignoresSafeArea(edges: .top)

                // Sundial chrome persists on the sub-page. Hand is
                // hidden via `.subPage` so the user knows they're off
                // the main rotation. Home dismisses back; Circles also
                // dismisses (returning to homepage where the user can
                // navigate further).
                SundialNavView(
                    active: .subPage,
                    onCaptureTap: { showCaptureSheet = true },
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
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { refreshTopSafeInset() }
        .sheet(isPresented: $showNewTaskForm) {
            NewTaskFormView { showNewTaskForm = false }
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAvoidanceManager) {
            AvoidanceManagerView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showHabitTrains) {
            HabitTrainsManagerView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBoosters) {
            BoosterManagerView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showMilestones) {
            MilestonesView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            ScoringSettingsView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(palette: SkyPalette) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: skyStops(for: palette),
                startPoint: .top,
                endPoint: .bottom
            )

            // Decorative sun blob, fixed in the upper-right. Size +
            // brightness respond to today's score against the season's
            // daily goal — same linear mapping as the home sun, so the
            // user can watch it grow from either screen.
            GeometryReader { geo in
                let raw = Double(store.todayScore) / max(1.0, Double(store.currentSeason.dailyGoal))
                let progress = max(0.0, min(1.0, raw))
                let heroScale: CGFloat = CGFloat(0.35 + progress * 0.65)
                let bodyOpacity: Double = 0.42 + progress * 0.58

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [palette.halo.opacity(0.55), palette.halo.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 130
                            )
                        )
                        .frame(width: 260 * heroScale, height: 260 * heroScale)
                        .blur(radius: 2)
                        .opacity(0.7 * progress)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [palette.sunCore, palette.sunWarm, palette.sunOuter.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 55
                            )
                        )
                        .frame(width: 110 * heroScale, height: 110 * heroScale)
                        .opacity(bodyOpacity)
                }
                .position(x: geo.size.width - 60, y: 90)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.6), value: progress)
            }
            .frame(height: 320)

            // Foreground content
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: heroTopInset)

                navRow

                Spacer().frame(height: 12)

                scoreBlock

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .frame(height: heroHeight, alignment: .top)
        }
        .frame(height: heroHeight)
        .clipped()
    }

    /// Top safe-area clearance (notch / Dynamic Island), floored at 14 so
    /// the "Home" back button clears the status bar even before the inset
    /// is measured on first layout. Matches `SunZoneView`'s convention.
    private var heroTopInset: CGFloat { max(topSafeInset, 14) }

    /// Fixed height of the hero header: the safe-area clearance plus a
    /// constant 180 pt content region (nav row + score block + padding).
    /// Grows with the device inset so the score block never clips.
    private var heroHeight: CGFloat { heroTopInset + 180 }

    /// Reads the key window's top safe-area inset imperatively. The
    /// GeometryReader-in-background pattern reports a zeroed inset on this
    /// hierarchy (same as HomeView), which left the hero's "Home" button
    /// tucked behind the Dynamic Island.
    private func refreshTopSafeInset() {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 0
        if inset > 0 {
            topSafeInset = inset
        }
    }

    private var navRow: some View {
        HStack {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Home")
                        .font(.sans(15, weight: .regular))
                }
                .foregroundStyle(Theme.textCream.opacity(0.92))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 18) {
                Image(systemName: "calendar")
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Theme.textCream.opacity(0.85))
        }
    }

    private var scoreBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(store.currentSeason.name.uppercased()) · DAY \(store.currentSeasonDay) OF \(store.currentSeason.lengthDays)")
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textCream.opacity(0.7))

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(store.todayScore)")
                    .font(.serif(56, weight: .medium))
                    .tracking(-2)
                    .foregroundStyle(Theme.textCream)
                    .contentTransition(.numericText(value: Double(store.todayScore)))
                    .animation(.easeOut(duration: 0.5), value: store.todayScore)

                Text("of \(store.currentSeason.dailyGoal) today")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.7))
            }

            Text(store.forwardSentence)
                .font(.serifItalic(16, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.94))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: store.forwardSentence)
                .padding(.top, 2)
        }
    }

    // MARK: - Title strip

    private var titleStrip: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today's tasks")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text(titleStripStatus)
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    private var titleStripStatus: String {
        let pinned = store.tasks.filter { $0.isPinnedToday }
        let done = pinned.filter { store.hasLogEntryToday(forTaskId: $0.id) }.count
        let open = pinned.count - done

        var parts: [String] = []
        if done > 0 { parts.append("\(done) done") }
        if open > 0 { parts.append("\(open) open") }
        if parts.isEmpty { return "no tasks pinned" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Category pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pillView(
                    label: "All",
                    accentColor: nil,
                    isSelected: selectedCategory == nil,
                    pointsToday: nil
                ) {
                    selectedCategory = nil
                }

                ForEach(seasonCategoriesInTierOrder, id: \.self) { cat in
                    pillView(
                        label: store.categoryDisplayName(cat),
                        accentColor: cat,
                        isSelected: selectedCategory == cat,
                        pointsToday: pointsToday(for: cat)
                    ) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
        }
        .padding(.top, 14)
        .animation(.easeInOut(duration: 0.2), value: selectedCategory)
    }

    @ViewBuilder
    private func pillView(
        label: String,
        accentColor: Category?,
        isSelected: Bool,
        pointsToday: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let cat = accentColor, !isSelected {
                    Circle()
                        .fill(Color(hex: store.categoryColorHex(cat)))
                        .frame(width: 5, height: 5)
                }
                Text(label)
                    .font(.sans(12, weight: isSelected ? .medium : .regular))
                if let pts = pointsToday, pts > 0 {
                    Text("·\(pts)")
                        .font(.sans(11, weight: .regular))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(pillTextColor(category: accentColor, isSelected: isSelected))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(pillBackground(category: accentColor, isSelected: isSelected))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pillTextColor(category: Category?, isSelected: Bool) -> Color {
        if isSelected {
            return Theme.textCream
        }
        guard let category else { return Theme.textPrimary }
        return category.darkColor
    }

    private func pillBackground(category: Category?, isSelected: Bool) -> Color {
        if isSelected {
            return category?.darkColor ?? Theme.textPrimary
        }
        guard let category else { return Theme.textPrimary.opacity(0.08) }
        return category.color.opacity(0.15)
    }

    // MARK: - Mode filter pills

    private var modeFilterPills: some View {
        HStack(spacing: 6) {
            modeFilterPill(
                label: "Open only",
                iconName: "eye",
                isSelected: showOpenOnly
            ) {
                showOpenOnly.toggle()
            }

            modeFilterPill(
                label: "High-value",
                iconName: "flame",
                isSelected: showHighValueOnly
            ) {
                showHighValueOnly.toggle()
            }

            Spacer()

            modeFilterPill(
                label: "Scoring",
                iconName: "slider.horizontal.3",
                isSelected: false
            ) {
                showSettings = true
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func modeFilterPill(
        label: String,
        iconName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .regular))
                Text(label)
                    .font(.sans(12, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary.opacity(isSelected ? 0.95 : 0.7))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(
                        Theme.textPrimary.opacity(isSelected ? 0.45 : 0.22),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Library actions

    private var libraryActionRow: some View {
        HStack(spacing: 8) {
            // Task library — TODO: navigate to the library view in a future prompt.
            libraryButton(label: "Task library", iconName: "list.bullet") {
                // Intentionally inert until the library view ships.
            }

            libraryButton(label: "New task", iconName: "plus") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showNewTaskForm = true
            }

            libraryButton(label: "Reduce", iconName: "arrow.down.right") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAvoidanceManager = true
            }

            libraryButton(label: "Trains", iconName: "circle.hexagongrid") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showHabitTrains = true
            }

            libraryButton(label: "Boosters", iconName: "sparkles") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showBoosters = true
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    @ViewBuilder
    private func libraryButton(label: String, iconName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .regular))
                Text(label)
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Season footer

    private var seasonFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.1))
                .frame(height: 0.5)
                .padding(.bottom, 16)

            Text(store.currentSeason.name.uppercased())
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.bottom, 14)

            HStack(spacing: 10) {
                statCard(
                    label: "This week",
                    value: "\(store.weekScore)",
                    denominator: " / \(store.currentSeason.weeklyGoal)"
                )

                statCard(
                    label: "Days left",
                    value: "\(daysLeft)",
                    denominator: " / \(store.currentSeason.lengthDays)"
                )
            }
            .padding(.bottom, 12)

            milestonesLink
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 40)
    }

    private var daysLeft: Int {
        max(0, store.currentSeason.lengthDays - store.currentSeasonDay + 1)
    }

    @ViewBuilder
    private func statCard(label: String, value: String, denominator: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.serif(23, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(denominator)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var milestonesLink: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMilestones = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Season milestones")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(milestonesSubline)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var milestonesSubline: String {
        let milestones = store.currentSeason.milestones
        guard !milestones.isEmpty else {
            return "Add milestones to map the season"
        }

        let done = milestones.filter { $0.isCompleted }.count
        let earned = milestones.filter { $0.isCompleted }.map(\.pointValue).reduce(0, +)

        var parts: [String] = ["\(done)/\(milestones.count) done"]
        if earned > 0 { parts.append("+\(earned) pts") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data helpers

    /// Ordered list of categories used by the season — Primary → Support
    /// → Quiet. Drives both the pill row and the section order.
    private var seasonCategoriesInTierOrder: [Category] {
        let tierOrder: [CategoryTier] = [.primary, .support, .quiet]
        return tierOrder.flatMap { tier in
            store.currentSeason.categories
                .filter { $0.tier == tier }
                .map(\.category)
        }
    }

    /// Categories to render right now, accounting for the category filter
    /// pill AND for emptiness (categories with no pinned tasks today are
    /// dropped so the page doesn't fill with hollow headers).
    private var orderedVisibleCategories: [Category] {
        let base: [Category]
        if let selected = selectedCategory {
            base = [selected]
        } else {
            base = seasonCategoriesInTierOrder
        }
        return base.filter { !tasksForCategory($0).isEmpty }
    }

    /// Pinned-for-today Tasks in `category`, optionally narrowed by the
    /// active mode filters.
    private func tasksForCategory(_ category: Category) -> [FFTask] {
        store.tasks.filter { task in
            guard task.category == category, task.isPinnedToday else { return false }
            if showOpenOnly, store.hasLogEntryToday(forTaskId: task.id) { return false }
            if showHighValueOnly, task.nominalValue < store.reminderValueThreshold { return false }
            return true
        }
    }

    private func seasonCategory(for category: Category) -> SeasonCategory? {
        store.currentSeason.categories.first { $0.category == category }
    }

    /// Points earned today within a single category — used for the
    /// `·N` suffix on category pills. Counts completed LogEntries that
    /// reference any pinned-for-today Task in `category`.
    private func pointsToday(for category: Category) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let taskIds = Set(
            store.tasks
                .filter { $0.category == category && $0.isPinnedToday }
                .map(\.id)
        )
        return store.logEntries
            .filter { entry in
                guard let taskId = entry.taskId,
                      taskIds.contains(taskId),
                      entry.entryType == .completed,
                      cal.isDate(entry.date, inSameDayAs: today)
                else { return false }
                return true
            }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    private func skyStops(for palette: SkyPalette) -> [Gradient.Stop] {
        guard palette.skyStops.count > 1 else { return [] }
        let last = Double(palette.skyStops.count - 1)
        return palette.skyStops.enumerated().map { index, color in
            Gradient.Stop(color: color, location: Double(index) / last)
        }
    }
}

#Preview {
    NavigationStack {
        SeasonExpandedView()
            .environment(Store())
    }
}
