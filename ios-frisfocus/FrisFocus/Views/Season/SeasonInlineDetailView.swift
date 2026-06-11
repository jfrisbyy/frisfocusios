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
//  Content order: quiet Tasks · Stats underline switcher → the active
//  tab's content → collapsed "Season options" row → a small centered
//  minimize control. The Tasks tab keeps the title strip, category
//  pills, mode filters, per-category sections, and Cadence earned;
//  the Stats tab renders the full week/month/season stats inline
//  (StatsTabView). Sections reveal with a gentle stagger when the
//  zone expands, and tab flips crossfade with a small slide. The
//  parent owns the active tab so the header week score can land
//  directly on Stats; expanding via the score band defaults to Tasks.
//

import SwiftUI
import UIKit

/// The two faces of the expanded season area — today's work vs. the
/// inline stats. Owned by the parent (SunZoneView) so the header week
/// score can open the area directly on Stats.
enum SeasonDetailTab: String, CaseIterable {
    case tasks = "Tasks"
    case stats = "Stats"
}

struct SeasonInlineDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.sunSky) private var sky

    /// Folds the detail back into the compact sun zone. The parent
    /// owns the expansion state and the collapse animation.
    var onMinimize: () -> Void = {}

    /// Which face is showing — owned by the parent so the header week
    /// score can land directly on Stats.
    @Binding var activeTab: SeasonDetailTab

    @State private var selectedCategory: Category? = nil
    @State private var showOpenOnly: Bool = false
    @State private var showHighValueOnly: Bool = false
    @State private var showNewTaskForm: Bool = false
    @State private var showAvoidanceManager: Bool = false
    @State private var showHabitTrains: Bool = false
    @State private var showBoosters: Bool = false
    @State private var showMilestones: Bool = false
    @State private var showSettings: Bool = false
    @State private var showSeasonSetup: Bool = false
    @State private var showNextSeasonDialog: Bool = false
    /// Whether the season options grid is unfolded. Collapsed by
    /// default — the row stays quiet until asked.
    @State private var optionsExpanded: Bool = false
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
                case .stats:
                    statsTab
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 24)),
                                removal: .opacity
                            )
                        )
                }
            }

            staggered(3) { seasonOptionsSection }
            staggered(4) { minimizeControl }
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
            MilestonesBoardView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            ScoringSettingsView()
                .presentationDetents([.large])
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

    /// Quiet Tasks · Stats labels with a thin sliding underline — no
    /// capsule, no fill.
    private var tabSwitcher: some View {
        UnderlineTabSwitcher(
            items: SeasonDetailTab.allCases.map(\.rawValue),
            selectedIndex: SeasonDetailTab.allCases.firstIndex(of: activeTab) ?? 0,
            accessibilityLabels: ["Today's tasks", "Season stats"]
        ) { index in
            activeTab = SeasonDetailTab.allCases[index]
        }
        .padding(.top, 10)
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

    /// The season's numbers — the full week/month/season stats,
    /// rendered inline beneath the sky. The docked week chip leads:
    /// the same score + 7-day stripe from the sky corner, now the
    /// stats' header — tapping it closes the detail and returns the
    /// user to the top of the homepage.
    private var statsTab: some View {
        staggered(1) {
            VStack(spacing: 0) {
                weekChipHeader
                StatsTabView()
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Docked week chip

    /// The week peek's twin, docked at the top of the stats view. One
    /// tap folds the detail closed — the parent then scrolls home, a
    /// perfect round trip.
    private var weekChipHeader: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMinimize()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEEK")
                        .font(.sans(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.textCream.opacity(0.75))

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(store.weekScore)")
                            .font(.serif(20, weight: .medium))
                            .foregroundStyle(Theme.textCream)
                            .contentTransition(.numericText(value: Double(store.weekScore)))
                        Text(" / \(store.currentSeason.weeklyGoal)")
                            .font(.serif(15, weight: .medium))
                            .foregroundStyle(Theme.textCream.opacity(0.55))
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 7) {
                    WeekStripeView(dayOpacities: weekChipOpacities)
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .semibold))
                        Text("TAP TO RETURN HOME")
                            .font(.sans(8, weight: .medium))
                            .tracking(1.4)
                    }
                    .foregroundStyle(Theme.textCream.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(glassStroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableTileStyle())
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .accessibilityLabel("Week score \(store.weekScore) of \(store.currentSeason.weeklyGoal)")
        .accessibilityHint("Closes the season detail and returns to the top of the homepage")
    }

    /// Same translation the sky's week peek uses — today reads at a
    /// fixed 0.9, past days scale from a 0.15 floor by goal progress.
    private var weekChipOpacities: [Double] {
        let goal = max(1, store.currentSeason.dailyGoal)
        return store.weekStripeData.enumerated().map { index, score in
            if index == 6 { return 0.9 }
            let progress = Double(score) / Double(goal)
            return 0.15 + min(progress, 1.0) * 0.75
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textCream.opacity(0.6))
    }

    // MARK: - Season options

    /// A quiet expandable row near the bottom of the expanded area —
    /// collapsed by default. Unfolding reveals the two-column grid of
    /// season controls and the next-season action with a gentle spring.
    private var seasonOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    optionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    sectionHeader("Season options")

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textCream.opacity(0.5))
                        .rotationEffect(.degrees(optionsExpanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Season options")
            .accessibilityHint(
                optionsExpanded
                    ? "Collapses the season controls"
                    : "Expands the season controls — new task, reduce, trains, boosters, milestones, scoring, next season"
            )
            .accessibilityAddTraits(optionsExpanded ? .isSelected : [])

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 10) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
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

    // MARK: - Minimize control

    /// Small, centered, understated close control — a chevron with
    /// tiny "minimize" text, no heavy background. The parent folds the
    /// detail with the same spring + scroll-home as the score-band tap.
    private var minimizeControl: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMinimize()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("minimize")
                    .font(.sans(9, weight: .medium))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.textCream.opacity(0.55))
            .padding(.vertical, 12)
            .padding(.horizontal, 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableTileStyle())
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 18)
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
        SeasonInlineDetailView(activeTab: .constant(.tasks))
    }
    .background(Theme.skyDeep)
    .environment(\.sunSky, .make(now: .now, coordinate: nil))
    .environment(Store())
}
