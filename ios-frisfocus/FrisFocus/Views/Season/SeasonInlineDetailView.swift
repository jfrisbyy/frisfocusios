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
//  Content order: minimize pill → title strip → category pills → mode
//  filter pills → per-category sections → Cadence earned → library
//  actions → season footer → "the work" scroll hint. Sections reveal
//  with a gentle stagger when the zone expands.
//

import SwiftUI
import UIKit

struct SeasonInlineDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.sunSky) private var sky

    /// Folds the detail back into the compact sun zone. The parent
    /// owns the expansion state and the collapse animation.
    var onMinimize: () -> Void = {}

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
    /// Drives the staggered entrance of each content band.
    @State private var revealed: Bool = false

    // Glass-on-sky tokens — translucent whites over the deep gradient.
    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    var body: some View {
        VStack(spacing: 0) {
            staggered(0) { minimizePill }
            staggered(0) { titleStrip }
            staggered(1) { categoryPills }
            staggered(1) { modeFilterPills }

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

            staggered(3) { libraryActionRow }
            staggered(3) { seasonFooter }
            staggered(3) { workHint }
        }
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

    // MARK: - Minimize pill

    private var minimizePill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onMinimize()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                Text("minimize")
                    .font(.sans(10, weight: .medium))
                    .tracking(1.6)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.textCream.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(glassFill))
            .overlay(Capsule().strokeBorder(glassStroke, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel("Minimize season details")
        .accessibilityHint("Folds the season detail back into the sun zone")
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

    // MARK: - Library actions

    private var libraryActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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

                // Task library — TODO: navigate to the library view in a
                // future prompt. Intentionally inert until it ships.
                libraryButton(label: "Task library", iconName: "list.bullet") { }
            }
            .padding(.horizontal, 22)
        }
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
            .foregroundStyle(Theme.textCream.opacity(0.92))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Season footer

    private var seasonFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 0.5)
                .padding(.bottom, 16)

            Text(store.currentSeason.name.uppercased())
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textCream.opacity(0.6))
                .padding(.bottom, 14)

            HStack(spacing: 10) {
                statCard(
                    label: "This week",
                    value: "\(store.weekScore)",
                    denominator: " / \(store.currentSeason.weeklyGoal)"
                )
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
    }

    private var daysLeft: Int {
        max(0, store.currentSeason.lengthDays - store.currentSeasonDay + 1)
    }

    @ViewBuilder
    private func statCard(label: String, value: String, denominator: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.6))

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.serif(23, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .contentTransition(.numericText())
                Text(denominator)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
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
                        .foregroundStyle(Theme.textCream)
                    Text(milestonesSubline)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.65))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
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

    // MARK: - Work hint

    /// While the zone is expanded the "scroll · the work" breadcrumb
    /// lives below the season content so the page still reads
    /// top-to-bottom.
    private var workHint: some View {
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
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 22)
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

#Preview {
    ScrollView {
        SeasonInlineDetailView()
    }
    .background(Theme.skyDeep)
    .environment(\.sunSky, .make(now: .now, coordinate: nil))
    .environment(Store())
}
