//
//  MonthStatsView.swift
//  FrisFocus
//
//  The Month scope of the stats screen. A month pager (arrows + swipe)
//  above a bar chart of every day in the month with a goal line and
//  tappable bars, then the selected day's breakdown, a month summary
//  (total, average per day, best day, goal days), gains & losses, and
//  a "vs the month before" strip. Quiet empty state when nothing was
//  logged in the visible month.
//

import SwiftUI
import UIKit

struct MonthStatsView: View {
    @Environment(Store.self) private var store

    /// 0 = current month, -1 = last month, back to the month of the
    /// earliest log entry.
    @State private var monthOffset: Int = 0
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())
    @State private var barsRevealed: Bool = false

    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    private let positiveAreaHeight: CGFloat = 140
    private let negativeAreaHeight: CGFloat = 22

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 14) {
            monthPager

            if monthEntries.isEmpty {
                emptyMonthCard
            } else {
                chartCard

                if let day = selectedDay, dayIsInMonth(day) {
                    StatsDayDetailCard(day: day)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }

                monthSummaryCard
                gainsAndLossesCard

                if monthOffset > earliestMonthOffset {
                    comparisonStrip
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: selectedDay)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: monthOffset)
        .onAppear { barsRevealed = true }
        .onChange(of: monthOffset) { _, newOffset in
            barsRevealed = false
            selectedDay = newOffset == 0 ? today : nil
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                barsRevealed = true
            }
        }
    }

    // MARK: - Month pager

    private var monthPager: some View {
        HStack(spacing: 10) {
            pagerArrow(iconName: "chevron.left", enabled: canGoBack) {
                monthOffset -= 1
            }

            VStack(spacing: 2) {
                Text(monthTitle)
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .contentTransition(.numericText())
                Text(monthSubtitle)
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            pagerArrow(iconName: "chevron.right", enabled: canGoForward) {
                monthOffset += 1
            }
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
        .accessibilityLabel(iconName == "chevron.left" ? "Previous month" : "Next month")
    }

    private var canGoBack: Bool { monthOffset > earliestMonthOffset }
    private var canGoForward: Bool { monthOffset < 0 }

    private var earliestMonthOffset: Int {
        guard let earliest = store.logEntries.map(\.date).min(),
              let earliestMonth = cal.dateInterval(of: .month, for: earliest),
              let currentMonth = cal.dateInterval(of: .month, for: Date())
        else { return 0 }
        let months = cal.dateComponents(
            [.month],
            from: earliestMonth.start,
            to: currentMonth.start
        ).month ?? 0
        return -max(0, months)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthInterval.start)
    }

    private var monthSubtitle: String {
        switch monthOffset {
        case 0: return "this month"
        case -1: return "last month"
        default: return "\(-monthOffset) months ago"
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                barsRow
                goalLine
            }

            axisRow
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
                            monthOffset += 1
                        }
                    } else if dx > 0, canGoBack {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            monthOffset -= 1
                        }
                    }
                }
        )
    }

    private var barsRow: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(Array(monthDays.enumerated()), id: \.element) { index, day in
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
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.4 : 0.18))
                            .frame(height: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                    }
                }

                if negativeMagnitude > 0 {
                    ZStack(alignment: .top) {
                        Color.clear
                            .frame(height: negativeAreaHeight)

                        if score < 0 {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Theme.alertRed.opacity(isSelected ? 0.95 : 0.7))
                                .frame(height: negativeHeight(for: score))
                                .scaleEffect(y: barsRevealed ? 1 : 0.001, anchor: .top)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(0.012 * Double(index)),
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

        RoundedRectangle(cornerRadius: 2, style: .continuous)
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
                color: hitGoal ? Theme.sunOuter.opacity(0.4) : .clear,
                radius: 2.5
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.textCream.opacity(0.9) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(y: barsRevealed ? 1 : 0.001, anchor: .bottom)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(0.012 * Double(index)),
                value: barsRevealed
            )
    }

    private var goalLine: some View {
        let offsetFromBottom = negativeRegionTotal + goalLineHeight

        return HStack(spacing: 6) {
            StatsGoalLineShape()
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

    /// 31 bars are too tight for per-day labels — anchor the axis with
    /// the first day, mid-month, and the last day instead.
    private var axisRow: some View {
        let lastDay = monthDays.count

        return HStack {
            Text("1")
            Spacer()
            Text("15")
            Spacer()
            Text("\(lastDay)")
        }
        .font(.sans(9, weight: .regular))
        .foregroundStyle(Theme.textCream.opacity(0.5))
        .padding(.horizontal, 2)
    }

    // MARK: - Chart math

    private var positiveMagnitude: Int {
        let maxScore = monthDays.map { dayScore(on: $0) }.max() ?? 0
        return max(store.currentSeason.dailyGoal, maxScore, 1)
    }

    private var negativeMagnitude: Int {
        let minScore = monthDays.map { dayScore(on: $0) }.min() ?? 0
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

    private func accessibilityDayLabel(_ day: Date, score: Int, future: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        let name = formatter.string(from: day)
        if future { return "\(name), upcoming" }
        return "\(name), \(score) points"
    }

    // MARK: - Month summary

    private var monthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Month summary")

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(monthTotal)")
                    .font(.serif(30, weight: .medium))
                    .foregroundStyle(monthTotal < 0 ? Theme.alertRed : Theme.textCream)
                    .contentTransition(.numericText())
                Text(" points")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.5))

                Spacer()
            }

            HStack(spacing: 10) {
                summaryStat(label: "Avg / day", value: "\(averagePerDay)")
                summaryStat(label: "Best day", value: bestDayLabel)
                summaryStat(label: "Goal days", value: "\(goalDaysCount) of \(elapsedDayCount)")
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

    /// Days of this month that have already happened — current month
    /// counts only elapsed days so mid-month averages stay honest.
    private var elapsedDayCount: Int {
        max(1, monthDays.filter { $0 <= today }.count)
    }

    private var averagePerDay: Int {
        Int((Double(monthTotal) / Double(elapsedDayCount)).rounded())
    }

    private var bestDayLabel: String {
        let scored = monthDays
            .filter { $0 <= today }
            .map { (day: $0, score: dayScore(on: $0)) }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0 else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: best.day)) · \(best.score)"
    }

    private var goalDaysCount: Int {
        monthDays
            .filter { $0 <= today }
            .filter { dayScore(on: $0) >= store.currentSeason.dailyGoal }
            .count
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
                    points: points(for: .milestone) + points(for: .milestoneStep)
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
        monthEntries
            .filter { $0.entryType == type }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    // MARK: - vs last month

    private var comparisonStrip: some View {
        let current = monthTotal
        let previous = previousMonthTotal
        let diff = current - previous
        let trendingUp = diff >= 0

        return HStack(spacing: 12) {
            Image(systemName: trendingUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trendingUp ? Theme.sunWarm : Theme.alertRed)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    diff == 0
                        ? "Even with the month before"
                        : "\(abs(diff)) points \(trendingUp ? "above" : "below") the month before"
                )
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textCream)

                Text("\(current) this month · \(previous) the month before")
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

    // MARK: - Empty month

    private var emptyMonthCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textCream.opacity(0.45))

            Text("A quiet month.")
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

    // MARK: - Month data

    private var monthInterval: DateInterval {
        let anchor = cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return cal.dateInterval(of: .month, for: anchor)
            ?? DateInterval(start: today, duration: 30 * 86_400)
    }

    private var monthDays: [Date] {
        let dayCount = cal.range(of: .day, in: .month, for: monthInterval.start)?.count ?? 30
        return (0..<dayCount).compactMap {
            cal.date(byAdding: .day, value: $0, to: monthInterval.start)
        }
    }

    private func dayIsInMonth(_ day: Date) -> Bool {
        day >= monthInterval.start && day < monthInterval.end
    }

    private var monthEntries: [LogEntry] {
        entries(in: monthInterval)
    }

    private var monthTotal: Int {
        monthEntries.map(\.pointsEarned).reduce(0, +)
    }

    private var previousMonthTotal: Int {
        let anchor = cal.date(byAdding: .month, value: monthOffset - 1, to: Date()) ?? Date()
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return 0 }
        return entries(in: interval).map(\.pointsEarned).reduce(0, +)
    }

    private func entries(in interval: DateInterval) -> [LogEntry] {
        store.logEntries.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private func dayScore(on day: Date) -> Int {
        store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .map(\.pointsEarned)
            .reduce(0, +)
    }
}

/// A straight horizontal line — the dashed goal marker, shared by the
/// month and season charts.
struct StatsGoalLineShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
