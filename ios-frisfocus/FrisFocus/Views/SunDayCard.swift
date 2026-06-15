//
//  SunDayCard.swift
//  FrisFocus
//
//  The warm "today" card every profile shares. The sun is the hero:
//  a glowing disc on the left, simply growing in size and warming the
//  closer the day is to its goal — a dim ember on a quiet day, a full
//  warm glow on a strong one.
//
//  The card itself stays a slim horizontal band: sun, headline, and
//  points. It only expands (in height, in place) to reveal a row of
//  recent days as bare suns. The day's task list lives SEPARATELY,
//  below the card, via `DayTaskList`. Tapping any sun moves the shared
//  `selectedId` binding, and the list below rewinds to that day.
//
//  Privacy is the caller's job: each `SunDay` already carries only what
//  the viewer is allowed to see (task names and score are omitted at
//  sharing levels that don't reveal them).
//

import SwiftUI
import UIKit

/// One soft chip describing something done (or open) on a given day.
/// Each chip carries its life-area `category` (when known) so the list
/// below the sun can group and color-code it the way the rest of the
/// app does. When `summaryDone`/`summaryTotal` are set, the chip is a
/// category SUMMARY row (the Open privacy tier, where task names aren't
/// shared) rather than a single task.
struct SunDayChip: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isDone: Bool
    var category: Category? = nil
    var summaryDone: Int? = nil
    var summaryTotal: Int? = nil

    /// True when this chip stands for a whole category's done/total
    /// count rather than one named task.
    var isSummary: Bool { summaryTotal != nil }
}

/// A single day on the card. `id` is days-ago (0 = today). The caller
/// builds these tier-resolved, so the card just renders what it's given.
struct SunDay: Identifiable, Equatable {
    /// Days ago — 0 is today.
    let id: Int
    let date: Date
    /// Strength toward goal, 0…1 (may exceed 1). Drives the sun.
    let ratio: Double
    let headline: String
    let subline: String?
    let chips: [SunDayChip]
    /// The bold score line — e.g. "47 points". `nil` keeps it private.
    let scoreText: String?
}

struct SunDayCard: View {
    /// Recent days, oldest first, ending with today. Must be non-empty.
    let days: [SunDay]
    let accent: Color
    /// Currently viewed day, as days-ago. 0 = today. Owned by the parent
    /// so the separate task list below can follow the same selection.
    @Binding var selectedId: Int

    @State private var expanded: Bool = false

    private var today: SunDay { days.last ?? days[0] }
    private var selected: SunDay { days.first { $0.id == selectedId } ?? today }
    private var isViewingPast: Bool { selectedId != 0 }
    private var canExpand: Bool { days.count >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            content
            // The recent-days strip is always part of the layout; it
            // simply has zero height when collapsed. Animating the
            // height (rather than inserting/removing the view) keeps the
            // card's growth contained and stops the page from jumping.
            if canExpand {
                expandTray
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Content (the selected day) — slim horizontal band

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isViewingPast {
                viewingPill
            }

            HStack(alignment: .center, spacing: 16) {
                CenteredSunView(ratio: selected.ratio, maxDiameter: 40)
                    .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 5) {
                    Text(selected.headline)
                        .font(.serif(18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subline = selected.subline, !subline.isEmpty {
                        Text(subline)
                            .font(.sans(12.5, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let scoreText = selected.scoreText, !scoreText.isEmpty {
                        Text(scoreText)
                            .font(.serif(14, weight: .medium))
                            .foregroundStyle(accent.opacity(0.9))
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(selected.id)
                .transition(.opacity)
            }
            .frame(minHeight: 84)

            if canExpand {
                expandToggle
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedId)
    }

    /// The recent-days tray. Always present so its presence never shifts
    /// the page; only its height animates between zero and a fixed band.
    /// The strip inside scrolls horizontally so a long run of days can
    /// never impose a width wider than the card (which would shove the
    /// whole page sideways).
    private var expandTray: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 18)
            RecentSunsStrip(
                days: days,
                selectedId: selectedId,
                accent: accent,
                onSelect: select
            )
            .padding(.vertical, 14)
        }
        .frame(height: expanded ? nil : 0, alignment: .top)
        .opacity(expanded ? 1 : 0)
        .clipped()
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: expanded)
    }

    private var viewingPill: some View {
        Button {
            select(0)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.left")
                    .font(.sans(10, weight: .bold))
                Text("Viewing \(longLabel(selected.date)) · Back to today")
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(accent.darkenedForLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(accent.opacity(0.14)))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Viewing \(longLabel(selected.date)). Tap to return to today.")
    }

    private var expandToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            expanded.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(expanded ? "Hide recent days" : "Recent days")
                    .font(.sans(12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.sans(10, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Hide recent days" : "Show recent days")
    }

    private func select(_ id: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedId = id
        }
    }

    private func longLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Day task list

/// The calm task list that lives BELOW the sun card. It renders the
/// chips of whichever `SunDay` is currently selected — done items ticked
/// and tinted, open items quiet. Swapping `day` cross-fades the rows so
/// tapping a past sun rewinds the list smoothly. Empty days (or privacy
/// levels that reveal no task names) show a soft, honest empty line.
struct DayTaskList: View {
    let day: SunDay
    let accent: Color
    /// When true, the list shows a quiet empty line for days with no
    /// revealed items. When false, the section simply renders nothing.
    var showsEmptyState: Bool = true

    /// True when this day only shares category counts (Open tier), not
    /// individual task names — render one summary row per category.
    private var isSummaryList: Bool { day.chips.contains { $0.isSummary } }

    /// The named-task chips grouped under their life-area category,
    /// preserving the order categories first appear in the day.
    private var groups: [DayTaskGroupModel] {
        var order: [String] = []
        var byKey: [String: [SunDayChip]] = [:]
        var catForKey: [String: Category?] = [:]
        for chip in day.chips {
            let key = chip.category?.rawValue ?? "_none"
            if byKey[key] == nil {
                order.append(key)
                catForKey[key] = chip.category
            }
            byKey[key, default: []].append(chip)
        }
        return order.map {
            DayTaskGroupModel(id: $0, category: catForKey[$0] ?? nil, chips: byKey[$0] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if day.chips.isEmpty {
                if showsEmptyState {
                    emptyLine
                }
            } else if isSummaryList {
                ForEach(day.chips) { chip in
                    DayCategorySummaryRow(chip: chip, accent: accent)
                }
            } else {
                ForEach(groups) { group in
                    DayTaskGroupView(group: group, accent: accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("day-list-\(day.id)")
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.28), value: day.id)
    }

    private var emptyLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text(day.id == 0 ? "Nothing on today's plan yet" : "A quiet day — nothing logged")
                .font(.sans(13.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.42))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.03))
        )
    }
}

/// One life-area group in the day list — a soft category header (dot,
/// name, done count) over the tasks logged in that area that day.
struct DayTaskGroupModel: Identifiable {
    let id: String
    let category: Category?
    let chips: [SunDayChip]

    var done: Int { chips.filter { $0.isDone }.count }
    var total: Int { chips.count }
}

private struct DayTaskGroupView: View {
    let group: DayTaskGroupModel
    let accent: Color

    private var tint: Color {
        group.category.map { Color(hex: $0.hexColor) } ?? accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text((group.category?.displayName ?? "Other").uppercased())
                    .font(.sans(11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer(minLength: 0)
                Text("\(group.done) of \(group.total)")
                    .font(.sans(11.5, weight: .semibold))
                    .foregroundStyle(tint.darkenedForLabel.opacity(0.85))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(group.chips) { chip in
                    DayTaskRow(chip: chip, tint: tint)
                }
            }
        }
    }
}

/// A single calm row in the day task list — a checked-off box matching
/// the rest of the app, tinted to its category.
private struct DayTaskRow: View {
    let chip: SunDayChip
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            checkbox

            Text(chip.title)
                .font(.sans(14.5, weight: chip.isDone ? .medium : .regular))
                .foregroundStyle(chip.isDone ? Theme.textPrimary.opacity(0.85) : Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(chip.isDone ? tint.opacity(0.08) : Theme.textPrimary.opacity(0.03))
        )
        .accessibilityElement()
        .accessibilityLabel("\(chip.title), \(chip.isDone ? "done" : "not done")")
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(chip.isDone ? tint : Color.clear)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        chip.isDone ? Color.clear : Theme.textPrimary.opacity(0.22),
                        lineWidth: 1.5
                    )
            )
            .overlay {
                if chip.isDone {
                    Image(systemName: "checkmark")
                        .font(.sans(12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

/// A category summary row — used when only counts are shared (Open
/// tier), not task names. Styled to sit alongside the task rows.
private struct DayCategorySummaryRow: View {
    let chip: SunDayChip
    let accent: Color

    private var tint: Color {
        chip.category.map { Color(hex: $0.hexColor) } ?? accent
    }
    private var done: Int { chip.summaryDone ?? 0 }
    private var total: Int { chip.summaryTotal ?? 0 }
    private var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(chip.category?.displayName ?? chip.title)
                .font(.sans(14.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.82))

            Spacer(minLength: 8)

            Text("\(done) of \(total)")
                .font(.sans(12.5, weight: .semibold))
                .foregroundStyle(tint.darkenedForLabel.opacity(0.9))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.05 + 0.07 * fraction))
        )
        .accessibilityElement()
        .accessibilityLabel("\(chip.category?.displayName ?? chip.title), \(done) of \(total) done")
    }
}

// MARK: - Centered sun

/// The sun alone, centered and unboxed. It does not rise or set — it
/// only grows in size and warms in glow with `ratio`. Quiet days read
/// as a small dim ember; strong days bloom to a full warm sun with
/// rays at goal.
struct CenteredSunView: View {
    /// Raw ratio — may exceed 1.0; visuals clamp, rays key off ≥ 1.
    let ratio: Double
    var maxDiameter: CGFloat = 86

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var isFull: Bool { ratio >= 1.0 }
    /// Size grows from a small ember (50%) to full (100%).
    private var d: CGFloat { maxDiameter * (0.5 + 0.5 * clamped) }
    /// The fixed box the sun and ALL of its glow live inside. Every
    /// glowing layer is sized and faded to vanish before this edge so
    /// nothing ever bleeds past the card and into the page.
    private var side: CGFloat { maxDiameter * 2.0 }

    private var coreColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunCore, SkyPalette.afternoon.sunCore, t: clamped)
    }
    private var warmColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunWarm, SkyPalette.afternoon.sunWarm, t: clamped)
    }
    private var outerColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunOuter, SkyPalette.afternoon.sunOuter, t: clamped)
    }
    private var haloColor: Color {
        Color.lerpHSL(SkyPalette.dusk.halo, SkyPalette.afternoon.halo, t: clamped)
    }

    var body: some View {
        ZStack {
            // Atmospheric bleed — widest, softest light.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: haloColor.opacity(0.04 + 0.16 * clamped), location: 0.0),
                            .init(color: outerColor.opacity(0.08 * clamped), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: maxDiameter * 1.05
                    )
                )
                .frame(width: side, height: side)
                .blur(radius: 5)

            // Soft halo — radius grows with ratio.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: haloColor.opacity(0.12 + 0.40 * clamped), location: 0.0),
                            .init(color: outerColor.opacity(0.05 + 0.20 * clamped), location: 0.55),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: d * 0.95
                    )
                )
                .frame(width: min(d * 1.9, side), height: min(d * 1.9, side))
                .blur(radius: 4)

            // Warm body bloom.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: warmColor.opacity(0.9), location: 0.0),
                            .init(color: outerColor.opacity(0.5), location: 0.7),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: d * 0.72
                    )
                )
                .frame(width: d * 1.44, height: d * 1.44)
                .opacity(0.25 + 0.75 * clamped)

            // Luminous core — always present, muted when dim.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: coreColor, location: 0.0),
                            .init(color: warmColor, location: 0.55),
                            .init(color: outerColor, location: 1.0)
                        ],
                        center: UnitPoint(x: 0.45, y: 0.42),
                        startRadius: 0,
                        endRadius: d * 0.6
                    )
                )
                .frame(width: d, height: d)
                .opacity(0.68 + 0.32 * clamped)

            // Upper-left highlight — a soft white kiss.
            Circle()
                .fill(Color.white.opacity(0.26 * clamped))
                .frame(width: d * 0.3, height: d * 0.3)
                .blur(radius: d * 0.05)
                .offset(x: -d * 0.12, y: -d * 0.1)

            // Rays — discrete, ONLY at goal-hit.
            if isFull {
                ForEach([-64.0, -32.0, 0.0, 32.0, 64.0], id: \.self) { angle in
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: haloColor.opacity(0.8), location: 0.0),
                                    .init(color: haloColor.opacity(0.22), location: 0.6),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: d * 0.07 + 1.0, height: d * 0.44)
                        .blur(radius: d * 0.02)
                        .offset(y: -d * 0.92)
                        .rotationEffect(.degrees(angle))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: clamped)
        .accessibilityElement()
        .accessibilityLabel("Sun at \(Int((max(0, ratio) * 100).rounded())) percent of the daily goal")
    }
}

// MARK: - Recent suns

/// A row of bare suns — one per recent day, each lit and sized to how
/// that day went, with a quiet day label under each. Tapping one
/// rewinds the card to that day; the selected one is ringed in accent.
private struct RecentSunsStrip: View {
    let days: [SunDay]
    let selectedId: Int
    let accent: Color
    let onSelect: (Int) -> Void

    /// Up to the last ten days, oldest first.
    private var shown: [SunDay] { Array(days.suffix(10)) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(shown) { day in
                    dayCell(day)
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .frame(height: 64)
    }

    private func dayCell(_ day: SunDay) -> some View {
        let isSelected = day.id == selectedId
        let isToday = day.id == 0
        return Button {
            onSelect(day.id)
        } label: {
            VStack(spacing: 5) {
                CenteredSunView(ratio: day.ratio, maxDiameter: 26)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .strokeBorder(
                                isSelected ? accent.opacity(0.7) : Color.clear,
                                lineWidth: 1.6
                            )
                    )

                Text(label(day))
                    .font(.sans(9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? accent.darkenedForLabel : Theme.textPrimary.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 46)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if isToday {
                    Circle()
                        .fill(accent.opacity(0.5))
                        .frame(width: 3, height: 3)
                        .offset(y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label(day)), tap to view this day")
    }

    private func label(_ day: SunDay) -> String {
        if day.id == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: day.date)
    }
}

// MARK: - Helpers

extension Color {
    /// A hand-dimmed accent variant that stays legible on light fills.
    var darkenedForLabel: Color {
        let hsl = hslComponents
        return Color(hsl: (h: hsl.h, s: min(1, hsl.s * 1.05), l: max(0, hsl.l * 0.5), a: hsl.a))
    }
}

private struct SunDayCardPreview: View {
    @State private var selectedId: Int = 0

    private var days: [SunDay] {
        (0..<7).reversed().map { offset in
            let ratios: [Double] = [0.2, 0.9, 1.0, 0.5, 0.0, 0.7, 0.85]
            return SunDay(
                id: offset,
                date: Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date(),
                ratio: ratios[6 - offset],
                headline: offset == 0 ? "12 to a productive day" : "Strong day so far",
                subline: offset == 0 ? "6 of 8 done · most of the way" : "5 done",
                chips: [
                    SunDayChip(title: "Write", isDone: true, category: .creative),
                    SunDayChip(title: "Sketch", isDone: false, category: .creative),
                    SunDayChip(title: "Run", isDone: true, category: .fitness),
                    SunDayChip(title: "Read", isDone: false, category: .work)
                ],
                scoreText: offset == 0 ? "38 points" : "\(40 + offset) points"
            )
        }
    }

    private var selected: SunDay {
        days.first { $0.id == selectedId } ?? days[days.count - 1]
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    SunDayCard(days: days, accent: Color(hex: 0x639922), selectedId: $selectedId)
                    DayTaskList(day: selected, accent: Color(hex: 0x639922))
                }
                .padding()
            }
        }
    }
}

#Preview {
    SunDayCardPreview()
}
