//
//  SeasonStatsView.swift
//  FrisFocus
//
//  The Season scope of the stats screen — the whole season at a
//  glance. A week-by-week bar chart across the season with the weekly
//  goal line (tapping a week bar jumps into that week's detail), then
//  a season summary (total points, days elapsed/left, weekly goal hit
//  rate, milestones), and overall gains & losses. Quiet empty state
//  when nothing has been logged this season yet.
//

import SwiftUI
import UIKit

struct SeasonStatsView: View {
    @Environment(Store.self) private var store

    /// Called with a non-positive week offset (0 = current week) when
    /// a week bar is tapped; the host jumps to that week's detail.
    var onSelectWeek: (Int) -> Void = { _ in }

    @State private var barsRevealed: Bool = false

    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    private let positiveAreaHeight: CGFloat = 140
    private let negativeAreaHeight: CGFloat = 22

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 14) {
            seasonHeaderCard

            if seasonEntries.isEmpty {
                emptySeasonCard
            } else {
                chartCard
                seasonSummaryCard
                gainsAndLossesCard
            }
        }
        .onAppear { barsRevealed = true }
    }

    // MARK: - Season header

    private var seasonHeaderCard: some View {
        VStack(spacing: 2) {
            Text(store.currentSeason.name)
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textCream)
            Text("day \(store.currentSeasonDay) of \(store.currentSeason.lengthDays) · \(daysLeft) left")
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    private var daysLeft: Int {
        max(0, store.currentSeason.lengthDays - store.currentSeasonDay + 1)
    }

    // MARK: - Week-by-week chart

    private var chartCard: some View {
        VStack(spacing: 10) {
            HStack {
                sectionHeader("Week by week")
                Spacer()
                Text("tap a week to open it")
                    .font(.sans(9, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.45))
            }

            ZStack(alignment: .bottomLeading) {
                barsRow
                goalLine
            }

            weekLabelsRow
        }
        .padding(14)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    private var barsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(seasonWeeks.enumerated()), id: \.offset) { index, week in
                barColumn(for: week, index: index)
            }
        }
    }

    @ViewBuilder
    private func barColumn(for week: DateInterval, index: Int) -> some View {
        let total = weekTotal(in: week)
        let isCurrent = week.contains(today)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectWeek(weekOffset(for: week))
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(height: positiveAreaHeight)

                    if total > 0 {
                        barShape(
                            total: total,
                            isCurrent: isCurrent,
                            height: positiveHeight(for: total),
                            index: index
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(isCurrent ? 0.35 : 0.18))
                            .frame(height: 3)
                    }
                }

                if negativeMagnitude > 0 {
                    ZStack(alignment: .top) {
                        Color.clear
                            .frame(height: negativeAreaHeight)

                        if total < 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Theme.alertRed.opacity(0.75))
                                .frame(height: negativeHeight(for: total))
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
        .accessibilityLabel(accessibilityWeekLabel(week, total: total, index: index))
        .accessibilityHint("Opens this week's detail")
    }

    @ViewBuilder
    private func barShape(total: Int, isCurrent: Bool, height: CGFloat, index: Int) -> some View {
        let hitGoal = total >= store.currentSeason.weeklyGoal

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
                    : AnyShapeStyle(Theme.textCream.opacity(isCurrent ? 0.7 : 0.4))
            )
            .frame(height: height)
            .shadow(
                color: hitGoal ? Theme.sunOuter.opacity(0.5) : .clear,
                radius: 4
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Theme.textCream.opacity(0.9) : Color.clear,
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

    private var goalLine: some View {
        let offsetFromBottom = negativeRegionTotal + goalLineHeight

        return HStack(spacing: 6) {
            StatsGoalLineShape()
                .stroke(
                    Theme.textCream.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(height: 1)

            Text("goal \(store.currentSeason.weeklyGoal)")
                .font(.sans(9, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.5))
                .fixedSize()
        }
        .offset(y: -offsetFromBottom)
        .allowsHitTesting(false)
    }

    private var weekLabelsRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(seasonWeeks.enumerated()), id: \.offset) { index, week in
                let isCurrent = week.contains(today)
                Text("w\(index + 1)")
                    .font(.sans(9, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.textCream.opacity(isCurrent ? 0.9 : 0.5))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: - Chart math

    private var positiveMagnitude: Int {
        let maxTotal = seasonWeeks.map { weekTotal(in: $0) }.max() ?? 0
        return max(store.currentSeason.weeklyGoal, maxTotal, 1)
    }

    private var negativeMagnitude: Int {
        let minTotal = seasonWeeks.map { weekTotal(in: $0) }.min() ?? 0
        return max(0, -minTotal)
    }

    private var negativeRegionTotal: CGFloat {
        negativeMagnitude > 0 ? negativeAreaHeight : 0
    }

    private var goalLineHeight: CGFloat {
        CGFloat(store.currentSeason.weeklyGoal) / CGFloat(positiveMagnitude) * positiveAreaHeight
    }

    private func positiveHeight(for total: Int) -> CGFloat {
        max(4, CGFloat(total) / CGFloat(positiveMagnitude) * positiveAreaHeight)
    }

    private func negativeHeight(for total: Int) -> CGFloat {
        guard negativeMagnitude > 0 else { return 0 }
        return max(3, CGFloat(-total) / CGFloat(negativeMagnitude) * (negativeAreaHeight - 4))
    }

    private func accessibilityWeekLabel(_ week: DateInterval, total: Int, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week \(index + 1), starting \(formatter.string(from: week.start)), \(total) points"
    }

    // MARK: - Season summary

    private var seasonSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Season so far")

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(seasonTotal)")
                    .font(.serif(30, weight: .medium))
                    .foregroundStyle(seasonTotal < 0 ? Theme.alertRed : Theme.textCream)
                    .contentTransition(.numericText())
                Text(" points")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.5))

                Spacer()

                Text("avg \(averagePerDay) / day")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.55))
            }

            HStack(spacing: 10) {
                summaryStat(
                    label: "Days",
                    value: "\(store.currentSeasonDay) of \(store.currentSeason.lengthDays)"
                )
                summaryStat(
                    label: "Weeks at goal",
                    value: "\(weeksAtGoal) of \(seasonWeeks.count)"
                )
                summaryStat(
                    label: "Milestones",
                    value: milestonesValue
                )
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

    private var averagePerDay: Int {
        let elapsed = max(1, store.currentSeasonDay)
        return Int((Double(seasonTotal) / Double(elapsed)).rounded())
    }

    private var weeksAtGoal: Int {
        seasonWeeks.filter { weekTotal(in: $0) >= store.currentSeason.weeklyGoal }.count
    }

    private var milestonesValue: String {
        let milestones = store.currentSeason.milestones
        guard !milestones.isEmpty else { return "—" }
        let done = milestones.filter { $0.isCompleted }.count
        return "\(done) of \(milestones.count)"
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
        seasonEntries
            .filter { $0.entryType == type }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    // MARK: - Empty season

    private var emptySeasonCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textCream.opacity(0.45))

            Text("A quiet season — so far.")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textCream)

            Text("Nothing has been logged this season yet.")
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

    // MARK: - Season data

    /// The season's date span — start of `startDate` through
    /// `lengthDays` days later (or the end of the current week if the
    /// season has already overrun its planned length).
    private var seasonInterval: DateInterval {
        let start = cal.startOfDay(for: store.currentSeason.startDate)
        let plannedEnd = cal.date(
            byAdding: .day,
            value: store.currentSeason.lengthDays,
            to: start
        ) ?? start
        let end = max(plannedEnd, cal.date(byAdding: .day, value: 1, to: today) ?? today)
        return DateInterval(start: start, end: end)
    }

    /// Calendar weeks from the week containing the season start
    /// through the current week (never past the season's end week).
    private var seasonWeeks: [DateInterval] {
        guard var cursor = cal.dateInterval(of: .weekOfYear, for: seasonInterval.start)
        else { return [] }

        let lastStart = cal.dateInterval(of: .weekOfYear, for: min(today, seasonInterval.end))?.start
            ?? cursor.start

        var weeks: [DateInterval] = []
        while cursor.start <= lastStart, weeks.count < 60 {
            weeks.append(cursor)
            guard let nextStart = cal.date(byAdding: .weekOfYear, value: 1, to: cursor.start),
                  let next = cal.dateInterval(of: .weekOfYear, for: nextStart)
            else { break }
            cursor = next
        }
        return weeks
    }

    /// Non-positive offset of `week` from the current calendar week —
    /// the value the Week pager understands.
    private func weekOffset(for week: DateInterval) -> Int {
        guard let currentWeek = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        let weeks = cal.dateComponents(
            [.weekOfYear],
            from: week.start,
            to: currentWeek.start
        ).weekOfYear ?? 0
        return -max(0, weeks)
    }

    private var seasonEntries: [LogEntry] {
        store.logEntries.filter {
            $0.date >= seasonInterval.start && $0.date < seasonInterval.end
        }
    }

    private var seasonTotal: Int {
        seasonEntries.map(\.pointsEarned).reduce(0, +)
    }

    private func weekTotal(in week: DateInterval) -> Int {
        store.logEntries
            .filter { $0.date >= week.start && $0.date < week.end }
            .map(\.pointsEarned)
            .reduce(0, +)
    }
}
