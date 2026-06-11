//
//  StatsTabView.swift
//  FrisFocus
//
//  The Stats tab of the expanded season area — the old full-screen
//  stats page, now rendered inline beneath the sky band. A quiet
//  Week · Month · Season underline switcher sits at the top; Week
//  keeps the pager, seven-day chart with goal line and tappable bars,
//  day breakdown, week summary, gains & losses, and the "vs last
//  week" strip. Month and Season live in MonthStatsView /
//  SeasonStatsView; tapping a week bar in the season chart jumps
//  back into that week's detail. A small share icon beside the week
//  pager opens the share camera with the week's suns.
//

import SwiftUI
import UIKit

struct StatsTabView: View {
    @Environment(Store.self) private var store

    /// The three zoom levels of the stats tab.
    private enum StatsScope: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case season = "Season"
    }

    @State private var scope: StatsScope = .week
    /// 0 = current week, -1 = last week, and so on back to the week of
    /// the earliest log entry.
    @State private var weekOffset: Int = 0
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())
    /// Bars grow from the baseline when the tab opens or the week flips.
    @State private var barsRevealed: Bool = false
    @State private var showWeekShare: Bool = false

    // Glass-on-sky tokens — matching SeasonInlineDetailView.
    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    private let positiveAreaHeight: CGFloat = 140
    private let negativeAreaHeight: CGFloat = 26

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            scopeSwitcher
                .padding(.top, 2)

            Group {
                switch scope {
                case .week:
                    weekContent
                case .month:
                    MonthStatsView()
                        .transition(.opacity)
                case .season:
                    SeasonStatsView { offset in
                        jumpToWeek(offset)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .onAppear { barsRevealed = true }
        .onChange(of: weekOffset) { _, newOffset in
            barsRevealed = false
            selectedDay = newOffset == 0 ? today : nil
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                barsRevealed = true
            }
        }
        .fullScreenCover(isPresented: $showWeekShare) {
            ShareCameraView(context: store.weekShareContext())
        }
    }

    // MARK: - Scope switcher

    /// Week · Month · Season — plain text with a thin sliding underline.
    private var scopeSwitcher: some View {
        UnderlineTabSwitcher(
            items: StatsScope.allCases.map(\.rawValue),
            selectedIndex: StatsScope.allCases.firstIndex(of: scope) ?? 0,
            accessibilityLabels: StatsScope.allCases.map { "\($0.rawValue) stats" }
        ) { index in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                scope = StatsScope.allCases[index]
            }
        }
    }

    /// Jumps from the season chart into one specific week's detail.
    private func jumpToWeek(_ offset: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            weekOffset = offset
            scope = .week
        }
    }

    // MARK: - Week scope content

    private var weekContent: some View {
        VStack(spacing: 14) {
            weekPager

            if weekEntries.isEmpty {
                emptyWeekCard
            } else {
                chartCard

                if let day = selectedDay, dayIsInWeek(day) {
                    StatsDayDetailCard(day: day)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }

                weekSummaryCard
                gainsAndLossesCard

                if weekOffset > earliestWeekOffset {
                    comparisonStrip
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: selectedDay)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: weekOffset)
    }

    // MARK: - Week pager

    private var weekPager: some View {
        HStack(spacing: 8) {
            pagerArrow(iconName: "chevron.left", enabled: canGoBack) {
                weekOffset -= 1
            }

            VStack(spacing: 2) {
                Text(weekTitle)
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .contentTransition(.numericText())
                Text(weekSubtitle)
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            pagerArrow(iconName: "chevron.right", enabled: canGoForward) {
                weekOffset += 1
            }

            shareWeekButton
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    /// Small, discreet share entry beside the pager — opens the share
    /// camera with seven small suns for the week.
    private var shareWeekButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showWeekShare = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textCream.opacity(0.6))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share your week")
        .accessibilityHint("Opens the share camera with seven small suns for the week")
    }

    @ViewBuilder
    private func pagerArrow(
        iconName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                action()
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textCream.opacity(enabled ? 0.85 : 0.25))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(enabled ? 0.08 : 0.03))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(iconName == "chevron.left" ? "Previous week" : "Next week")
    }

    private var canGoBack: Bool { weekOffset > earliestWeekOffset }
    private var canGoForward: Bool { weekOffset < 0 }

    /// How far back the pager may travel — the week containing the
    /// earliest log entry, as a non-positive offset from this week.
    private var earliestWeekOffset: Int {
        guard let earliest = store.logEntries.map(\.date).min(),
              let earliestWeek = cal.dateInterval(of: .weekOfYear, for: earliest),
              let currentWeek = cal.dateInterval(of: .weekOfYear, for: Date())
        else { return 0 }
        let weeks = cal.dateComponents(
            [.weekOfYear],
            from: earliestWeek.start,
            to: currentWeek.start
        ).weekOfYear ?? 0
        return -max(0, weeks)
    }

    private var weekTitle: String {
        let start = weekInterval.start
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "MMM d"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = cal.isDate(start, equalTo: end, toGranularity: .month)
            ? "d"
            : "MMM d"
        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }

    private var weekSubtitle: String {
        switch weekOffset {
        case 0: return "this week"
        case -1: return "last week"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                barsRow
                goalLine
            }

            dayLabelsRow
        }
        .padding(14)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else { return }
                    if dx < 0, canGoForward {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            weekOffset += 1
                        }
                    } else if dx > 0, canGoBack {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            weekOffset -= 1
                        }
                    }
                }
        )
    }

    private var barsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(weekDays.enumerated()), id: \.element) { index, day in
                barColumn(for: day, index: index)
            }
        }
    }

    @ViewBuilder
    private func barColumn(for day: Date, index: Int) -> some View {
        let score = dayScore(on: day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let future = day > today

        Button {
            guard !future else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                selectedDay = isSelected ? nil : day
            }
        } label: {
            VStack(spacing: 0) {
                // Positive region — bars grow upward from the baseline.
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(height: positiveAreaHeight)

                    if score > 0 {
                        barShape(
                            score: score,
                            isSelected: isSelected,
                            height: positiveHeight(for: score),
                            index: index
                        )
                    } else if !future {
                        // Zero (or negative) day — a quiet stub at the baseline.
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.4 : 0.18))
                            .frame(height: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                    }
                }

                // Negative region — only present when the week has a loss day.
                if negativeMagnitude > 0 {
                    ZStack(alignment: .top) {
                        Color.clear
                            .frame(height: negativeAreaHeight)

                        if score < 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.alertRed.opacity(isSelected ? 0.95 : 0.7))
                                .frame(height: negativeHeight(for: score))
                                .scaleEffect(y: barsRevealed ? 1 : 0.001, anchor: .top)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(0.04 * Double(index)),
                                    value: barsRevealed
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(accessibilityDayLabel(day, score: score, future: future))
    }

    @ViewBuilder
    private func barShape(score: Int, isSelected: Bool, height: CGFloat, index: Int) -> some View {
        let hitGoal = score >= store.currentSeason.dailyGoal

        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                hitGoal
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Theme.sunShadow, Theme.sunWarm],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    : AnyShapeStyle(Theme.textCream.opacity(isSelected ? 0.7 : 0.4))
            )
            .frame(height: height)
            .shadow(
                color: hitGoal ? Theme.sunOuter.opacity(0.5) : .clear,
                radius: 4
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.textCream.opacity(0.9) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(y: barsRevealed ? 1 : 0.001, anchor: .bottom)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(0.04 * Double(index)),
                value: barsRevealed
            )
    }

    /// Dashed goal marker drawn across the positive region.
    private var goalLine: some View {
        let offsetFromBottom = negativeRegionTotal + goalLineHeight

        return HStack(spacing: 6) {
            Line()
                .stroke(
                    Theme.textCream.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(height: 1)

            Text("goal \(store.currentSeason.dailyGoal)")
                .font(.sans(9, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.5))
                .fixedSize()
        }
        .offset(y: -offsetFromBottom)
        .allowsHitTesting(false)
    }

    private var dayLabelsRow: some View {
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                let isToday = cal.isDate(day, inSameDayAs: today)

                VStack(spacing: 1) {
                    Text(weekdayLetter(for: day))
                        .font(.sans(10, weight: isSelected ? .semibold : .regular))
                    Text("\(cal.component(.day, from: day))")
                        .font(.sans(9, weight: .regular))
                        .opacity(0.7)
                }
                .foregroundStyle(
                    Theme.textCream.opacity(isSelected ? 0.95 : (isToday ? 0.8 : 0.5))
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Chart math

    /// Highest value the positive region must fit — at least the daily
    /// goal so the goal line always sits inside the chart.
    private var positiveMagnitude: Int {
        let maxScore = weekDays.map { dayScore(on: $0) }.max() ?? 0
        return max(store.currentSeason.dailyGoal, maxScore, 1)
    }

    /// Deepest loss in the week (as a positive number); 0 when the week
    /// has no negative day, which removes the negative region entirely.
    private var negativeMagnitude: Int {
        let minScore = weekDays.map { dayScore(on: $0) }.min() ?? 0
        return max(0, -minScore)
    }

    private var negativeRegionTotal: CGFloat {
        negativeMagnitude > 0 ? negativeAreaHeight : 0
    }

    private var goalLineHeight: CGFloat {
        CGFloat(store.currentSeason.dailyGoal) / CGFloat(positiveMagnitude) * positiveAreaHeight
    }

    private func positiveHeight(for score: Int) -> CGFloat {
        max(4, CGFloat(score) / CGFloat(positiveMagnitude) * positiveAreaHeight)
    }

    private func negativeHeight(for score: Int) -> CGFloat {
        guard negativeMagnitude > 0 else { return 0 }
        return max(3, CGFloat(-score) / CGFloat(negativeMagnitude) * (negativeAreaHeight - 4))
    }

    private func weekdayLetter(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: day)
    }

    private func accessibilityDayLabel(_ day: Date, score: Int, future: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        let name = formatter.string(from: day)
        if future { return "\(name), upcoming" }
        return "\(name), \(score) points"
    }

    // MARK: - Week summary

    private var weekSummaryCard: some View {
        let total = weekTotal
        let goal = store.currentSeason.weeklyGoal

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Week summary")

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(total)")
                    .font(.serif(30, weight: .medium))
                    .foregroundStyle(total < 0 ? Theme.alertRed : Theme.textCream)
                    .contentTransition(.numericText())
                Text(" / \(goal)")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.5))

                Spacer()

                Text(total >= goal ? "goal reached" : "\(goal - total) to go")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }

            progressTrack(ratio(total, goal))

            HStack(spacing: 10) {
                summaryStat(label: "Avg / day", value: "\(averagePerDay)")
                summaryStat(label: "Best day", value: bestDayLabel)
                summaryStat(label: "Goal days", value: "\(goalDaysCount) of 7")
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.sans(9, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.55))
            Text(value)
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textCream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Average over elapsed days for the current week, over all seven
    /// for completed weeks — so a Tuesday doesn't read as a slump.
    private var averagePerDay: Int {
        let days = weekOffset == 0
            ? max(1, weekDays.filter { $0 <= today }.count)
            : 7
        return Int((Double(weekTotal) / Double(days)).rounded())
    }

    private var bestDayLabel: String {
        let scored = weekDays
            .filter { $0 <= today }
            .map { (day: $0, score: dayScore(on: $0)) }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0 else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return "\(formatter.string(from: best.day)) · \(best.score)"
    }

    private var goalDaysCount: Int {
        weekDays.filter { dayScore(on: $0) >= store.currentSeason.dailyGoal }.count
    }

    // MARK: - Gains & losses

    private var gainsAndLossesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Gains & losses")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                gainLossTile(
                    label: "Boosters",
                    iconName: "sparkles",
                    points: points(for: .boosterBonus)
                )
                gainLossTile(
                    label: "Routines",
                    iconName: "rectangle.stack.fill",
                    points: points(for: .trainBonus)
                )
                gainLossTile(
                    label: "Milestones",
                    iconName: "flag.checkered",
                    points: points(for: .milestone)
                )
                gainLossTile(
                    label: "Penalties",
                    iconName: "exclamationmark.circle.fill",
                    points: points(for: .penalty)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func gainLossTile(label: String, iconName: String, points: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    points < 0
                        ? Theme.alertRed
                        : (points > 0 ? Theme.sunWarm : Theme.textCream.opacity(0.35))
                )
                .frame(width: 18)

            Text(label)
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.85))

            Spacer(minLength: 4)

            Text(points > 0 ? "+\(points)" : "\(points)")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(
                    points < 0
                        ? Theme.alertRed
                        : Theme.textCream.opacity(points > 0 ? 1 : 0.45)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func points(for type: LogEntryType) -> Int {
        weekEntries
            .filter { $0.entryType == type }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    // MARK: - vs last week

    private var comparisonStrip: some View {
        let current = weekTotal
        let previous = previousWeekTotal
        let diff = current - previous
        let trendingUp = diff >= 0

        return HStack(spacing: 12) {
            Image(systemName: trendingUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trendingUp ? Theme.sunWarm : Theme.alertRed)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    diff == 0
                        ? "Even with the week before"
                        : "\(abs(diff)) points \(trendingUp ? "ahead of" : "behind") the week before"
                )
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textCream)

                Text("\(current) this week · \(previous) the week before")
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }

            Spacer()
        }
        .padding(14)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    // MARK: - Empty week

    private var emptyWeekCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textCream.opacity(0.45))

            Text("A quiet week.")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textCream)

            Text("Nothing was logged between these days.")
                .font(.serifItalic(13))
                .foregroundStyle(Theme.textCream.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    // MARK: - Shared bits

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textCream.opacity(0.6))
    }

    /// Slim glowing progress bar — same warm gradient as the charts.
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
    }

    private func ratio(_ value: Int, _ total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    // MARK: - Week data

    /// The calendar week being viewed, honouring the locale's first
    /// weekday (Sunday in en_US, Monday elsewhere).
    private var weekInterval: DateInterval {
        let anchor = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return cal.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: today, duration: 7 * 86_400)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap {
            cal.date(byAdding: .day, value: $0, to: weekInterval.start)
        }
    }

    private func dayIsInWeek(_ day: Date) -> Bool {
        weekDays.contains { cal.isDate($0, inSameDayAs: day) }
    }

    private var weekEntries: [LogEntry] {
        entries(in: weekInterval)
    }

    private var weekTotal: Int {
        weekEntries.map(\.pointsEarned).reduce(0, +)
    }

    private var previousWeekTotal: Int {
        let anchor = cal.date(byAdding: .weekOfYear, value: weekOffset - 1, to: Date()) ?? Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: anchor) else { return 0 }
        return entries(in: interval).map(\.pointsEarned).reduce(0, +)
    }

    private func entries(in interval: DateInterval) -> [LogEntry] {
        store.logEntries.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private func dayEntries(on day: Date) -> [LogEntry] {
        store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private func dayScore(on day: Date) -> Int {
        dayEntries(on: day).map(\.pointsEarned).reduce(0, +)
    }
}

/// A straight horizontal line — used for the dashed goal marker.
private struct Line: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview {
    ScrollView {
        StatsTabView()
    }
    .background(Theme.skyDeep)
    .environment(Store())
}
