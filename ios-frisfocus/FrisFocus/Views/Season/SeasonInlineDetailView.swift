//
//  SeasonInlineDetailView.swift
//  FrisFocus
//
//  The season detail, unfolded INLINE inside the Sun zone (replacing
//  the old pushed SeasonExpandedView page). It renders beneath the
//  compact sky band and continues the same palette downward — a
//  deepened sky gradient with stars and grain — so the categories,
//  tasks, filters, and season footer read as part of the landscape.
//
//  Content order: Tasks · Season tab switcher → the active tab's
//  content → full-width minimize button. The Tasks tab keeps the
//  title strip, category pills, mode filters, per-category sections,
//  and Cadence earned; the Season tab holds the dashboard and the
//  season options grid (open by default) with the next-season action.
//  Sections reveal with a gentle stagger when the zone expands, and
//  tab flips crossfade with a small slide. Always opens on Tasks.
//

import SwiftUI
import UIKit

struct SeasonInlineDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.sunSky) private var sky

    /// Folds the detail back into the compact sun zone. The parent
    /// owns the expansion state and the collapse animation.
    var onMinimize: () -> Void = {}

    /// The two faces of the expanded area — today's work vs. the
    /// season itself.
    private enum DetailTab: String, CaseIterable {
        case tasks = "Tasks"
        case season = "Season"
    }

    @State private var activeTab: DetailTab = .tasks
    @State private var selectedCategory: Category? = nil
    @State private var showOpenOnly: Bool = false
    @State private var showHighValueOnly: Bool = false
    @State private var showNewTaskForm: Bool = false
    @State private var showAvoidanceManager: Bool = false
    @State private var showHabitTrains: Bool = false
    @State private var showBoosters: Bool = false
    @State private var showMilestones: Bool = false
    @State private var showSettings: Bool = false
    @State private var showWeekShare: Bool = false
    @State private var showSeasonSetup: Bool = false
    @State private var showNextSeasonDialog: Bool = false
    @State private var showWeekStats: Bool = false
    /// Drives the staggered entrance of each content band.
    @State private var revealed: Bool = false

    // Glass-on-sky tokens — translucent whites over the deep gradient.
    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    var body: some View {
        VStack(spacing: 0) {
            staggered(0) { tabSwitcher }

            Group {
                switch activeTab {
                case .tasks:
                    tasksTab
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: -24)),
                                removal: .opacity
                            )
                        )
                case .season:
                    seasonTab
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 24)),
                                removal: .opacity
                            )
                        )
                }
            }

            staggered(4) { minimizeButton }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: activeTab)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { backdrop }
        .onAppear { revealed = true }
        .onDisappear { revealed = false }
        .sheet(isPresented: $showNewTaskForm) {
            NewTaskFormView { showNewTaskForm = false }
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
        .fullScreenCover(isPresented: $showWeekShare) {
            ShareCameraView(context: store.weekShareContext())
        }
        .fullScreenCover(isPresented: $showWeekStats) {
            WeekStatsView()
        }
        .fullScreenCover(isPresented: $showSeasonSetup) {
            SeasonSetupFlowView()
        }
        .confirmationDialog(
            "Next season",
            isPresented: $showNextSeasonDialog,
            titleVisibility: .visible
        ) {
            Button("Start guided setup") {
                showSeasonSetup = true
            }
            Button("Carry this season's setup forward") {
                store.startNewSeasonFromCurrent(name: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Guided setup builds a fresh rubric in conversation. Carrying forward keeps your categories and targets — the day count restarts and milestones reset.")
        }
    }

    // MARK: - Backdrop

    /// Continues the compact band's sky downward, deepened so cream
    /// text stays readable, with a quiet star scatter and film grain
    /// so the atmosphere never breaks.
    private var backdrop: some View {
        let palette = sky.palette
        let top = palette.skyStops.last ?? Theme.skyLow
        let deep = Color.lerpHSL(top, Color(hex: 0x05080A), t: 0.45)

        return ZStack(alignment: .top) {
            LinearGradient(
                colors: [top, deep, deep],
                startPoint: .top,
                endPoint: .bottom
            )

            StarFieldView()
                .frame(height: 420)
                .opacity(0.3)

            FilmGrainView(strength: 0.16)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Stagger

    /// Wraps one content band so it fades + rises in with a small
    /// per-band delay when the zone expands.
    @ViewBuilder
    private func staggered<Content: View>(
        _ index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 18)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(0.05 + 0.06 * Double(index)),
                value: revealed
            )
    }

    // MARK: - Tab switcher

    /// The Tasks · Season pill row at the top of the unfolded detail.
    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    guard tab != activeTab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    activeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.sans(13, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundStyle(
                            activeTab == tab ? Theme.textPrimary : Theme.textCream.opacity(0.8)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(activeTab == tab ? Theme.textCream : Color.clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .tasks ? "Today's tasks" : "Season details")
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(glassFill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(glassStroke, lineWidth: 0.5))
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    // MARK: - Tabs

    /// Today's work — title strip, filters, and the task sections.
    private var tasksTab: some View {
        VStack(spacing: 0) {
            staggered(1) { titleStrip }
            staggered(1) { categoryPills }
            staggered(2) { modeFilterPills }

            staggered(2) {
                VStack(spacing: 0) {
                    ForEach(orderedVisibleCategories, id: \.self) { category in
                        CategorySectionView(
                            category: category,
                            tasks: tasksForCategory(category),
                            seasonCategory: seasonCategory(for: category)
                        )
                    }

                    // Passive Cadence outcomes — absent unless linked.
                    CadenceEarnedSection()
                }
            }
        }
    }

    /// The season itself — dashboard cards and the options grid.
    private var seasonTab: some View {
        VStack(spacing: 0) {
            staggered(1) { seasonDashboard }
            staggered(2) { seasonOptionsSection }
        }
    }

    // MARK: - Title strip

    private var titleStrip: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today's tasks")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textCream)

            Spacer()

            Text(titleStripStatus)
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.6))
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
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
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textCream.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.textCream : glassFill)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : glassStroke,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
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
            .foregroundStyle(Theme.textCream.opacity(isSelected ? 0.98 : 0.7))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.white.opacity(isSelected ? 0.45 : 0.22),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Season dashboard

    /// The season's numbers as a 2×2 glass dashboard — today, week,
    /// season progress, and milestones — each with a slim glowing
    /// progress bar that moves live as tasks are completed.
    private var seasonDashboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(store.currentSeason.name)
                .padding(.bottom, 12)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                dashboardCard(
                    label: "Today",
                    value: "\(store.todayScore)",
                    denominator: " / \(store.currentSeason.dailyGoal)",
                    detail: goalDetail(
                        score: store.todayScore,
                        goal: store.currentSeason.dailyGoal
                    ),
                    progress: ratio(store.todayScore, store.currentSeason.dailyGoal)
                )

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showWeekStats = true
                } label: {
                    dashboardCard(
                        label: "This week",
                        value: "\(store.weekScore)",
                        denominator: " / \(store.currentSeason.weeklyGoal)",
                        detail: goalDetail(
                            score: store.weekScore,
                            goal: store.currentSeason.weeklyGoal
                        ),
                        progress: ratio(store.weekScore, store.currentSeason.weeklyGoal)
                    )
                }
                .buttonStyle(PressableTileStyle())
                .accessibilityLabel("This week")
                .accessibilityHint("Opens week stats with your full history")
                .overlay(alignment: .topTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showWeekShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textCream.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share your week")
                    .accessibilityHint("Opens the share camera with seven small suns for the week")
                }

                dashboardCard(
                    label: "Season",
                    value: "day \(store.currentSeasonDay)",
                    denominator: " / \(store.currentSeason.lengthDays)",
                    detail: "\(daysLeft) days left",
                    progress: ratio(store.currentSeasonDay, store.currentSeason.lengthDays)
                )

                dashboardCard(
                    label: "Milestones",
                    value: "\(milestonesDone)",
                    denominator: " / \(store.currentSeason.milestones.count)",
                    detail: milestonesDetail,
                    progress: ratio(milestonesDone, store.currentSeason.milestones.count)
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private var daysLeft: Int {
        max(0, store.currentSeason.lengthDays - store.currentSeasonDay + 1)
    }

    private var milestonesDone: Int {
        store.currentSeason.milestones.filter { $0.isCompleted }.count
    }

    private var milestonesDetail: String {
        guard !store.currentSeason.milestones.isEmpty else { return "none added yet" }
        let earned = store.currentSeason.milestones
            .filter { $0.isCompleted }
            .map(\.pointValue)
            .reduce(0, +)
        return earned > 0 ? "+\(earned) pts earned" : "0 pts earned"
    }

    /// "N to go" while under the goal, "goal reached" once it's met.
    private func goalDetail(score: Int, goal: Int) -> String {
        score >= goal ? "goal reached" : "\(goal - score) to go"
    }

    /// Safe 0–1 progress fraction.
    private func ratio(_ value: Int, _ total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textCream.opacity(0.6))
    }

    @ViewBuilder
    private func dashboardCard(
        label: String,
        value: String,
        denominator: String,
        detail: String,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.6))

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .contentTransition(.numericText())
                Text(denominator)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }
            .animation(.easeOut(duration: 0.5), value: value)

            progressTrack(progress)

            Text(detail)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.5))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: detail)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    /// Slim glowing progress bar — warm sun gradient over a quiet track.
    @ViewBuilder
    private func progressTrack(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                if progress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.sunShadow, Theme.sunWarm],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, proxy.size.width * progress))
                        .shadow(color: Theme.sunOuter.opacity(0.55), radius: 3)
                }
            }
            .animation(.easeOut(duration: 0.6), value: progress)
        }
        .frame(height: 4)
        .padding(.top, 2)
    }

    // MARK: - Season options

    /// The full two-column grid of season controls, always open on the
    /// Season tab, with the next-season action beneath.
    private var seasonOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Season options")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(seasonOptions.enumerated()), id: \.offset) { _, option in
                    optionTile(
                        label: option.label,
                        hint: option.hint,
                        iconName: option.iconName,
                        haptic: option.haptic,
                        action: option.action
                    )
                }
            }

            nextSeasonTile
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
    }

    /// The seven season-level controls, in display order.
    private var seasonOptions: [SeasonOptionItem] {
        [
            SeasonOptionItem(
                label: "New task",
                hint: "Add a task to today",
                iconName: "plus",
                haptic: .medium
            ) { showNewTaskForm = true },
            SeasonOptionItem(
                label: "Reduce",
                hint: "Things you're cutting back",
                iconName: "arrow.down.right"
            ) { showAvoidanceManager = true },
            SeasonOptionItem(
                label: "Trains",
                hint: "Linked habit streaks",
                iconName: "circle.hexagongrid"
            ) { showHabitTrains = true },
            SeasonOptionItem(
                label: "Boosters",
                hint: "Bonus point multipliers",
                iconName: "sparkles"
            ) { showBoosters = true },
            SeasonOptionItem(
                label: "Milestones",
                hint: "The season's big wins",
                iconName: "flag"
            ) { showMilestones = true },
            SeasonOptionItem(
                label: "Scoring",
                hint: "Reminders, categories, colors",
                iconName: "slider.horizontal.3"
            ) { showSettings = true }
        ]
    }

    @ViewBuilder
    private func optionTile(
        label: String,
        hint: String,
        iconName: String,
        haptic: UIImpactFeedbackGenerator.FeedbackStyle = .light,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: haptic).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                    .frame(height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                    Text(hint)
                        .font(.sans(10, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(13)
            .background(glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    /// Full-width tile — starting (or carrying forward) the next season
    /// is the season's biggest action, so it gets the whole row.
    private var nextSeasonTile: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showNextSeasonDialog = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.sunWarm)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Next season")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                    Text("Start the guided setup or carry this one forward")
                        .font(.sans(10, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textCream.opacity(0.45))
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel("Next season")
        .accessibilityHint("Start the guided setup or carry this season's setup forward")
    }

    // MARK: - Minimize button

    /// Full-width frosted close control at the very bottom — replacing
    /// the old "scroll · the work" breadcrumb. The parent folds the
    /// detail with the same spring + scroll-home as the score-band tap.
    private var minimizeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMinimize()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                Text("Minimize")
                    .font(.sans(12, weight: .medium))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.textCream.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(glassFill)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(glassStroke, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableTileStyle())
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .accessibilityLabel("Minimize season details")
        .accessibilityHint("Folds the season detail back into the sun zone")
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
    /// dropped so the zone doesn't fill with hollow headers).
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
    /// `·N` suffix on category pills.
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
}

/// One entry in the season options grid.
private struct SeasonOptionItem {
    let label: String
    let hint: String
    let iconName: String
    var haptic: UIImpactFeedbackGenerator.FeedbackStyle = .light
    let action: () -> Void
}

/// Soft press feedback for the glass tiles — a gentle shrink + dim.
private struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        SeasonInlineDetailView()
    }
    .background(Theme.skyDeep)
    .environment(\.sunSky, .make(now: .now, coordinate: nil))
    .environment(Store())
}
