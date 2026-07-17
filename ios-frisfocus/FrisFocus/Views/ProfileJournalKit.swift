//
//  ProfileJournalKit.swift
//  FrisFocus
//
//  The quiet editorial pieces every profile body is built from —
//  hairline section headers instead of boxed cards, the TODAY headline
//  row with task chips, the single italic witness line, the season's
//  destinations as a vertical timeline, the "seasons before" poster
//  row, and the week-rhythm peek sheet.
//
//  Shared by the friend profile, my own profile, and the discovery
//  sheet so every profile reads as one design.
//

import SwiftUI
import UIKit

// MARK: - Hairline + section header

/// A 0.5pt rule in the page ink, the only separator the journal body uses.
struct JournalHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.10))
            .frame(height: 0.5)
    }
}

/// Small tracked uppercase label with an optional trailing link —
/// "TODAY        Tue ›".
struct JournalSectionHeader: View {
    let label: String
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.sans(10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Spacer(minLength: 8)
            if let trailingTitle, let trailingAction {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    trailingAction()
                } label: {
                    HStack(spacing: 2) {
                        Text(trailingTitle)
                            .font(.sans(12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.sans(9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - TODAY headline row

/// The slim ring + serif headline + sub-line that leads the TODAY
/// section: "Strong day so far / 6 of 8 done · most of the way".
struct TodayHeadlineRow: View {
    let fraction: Double
    let tint: Color
    let headline: String
    let subline: String?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.textPrimary.opacity(0.10), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                if let subline, !subline.isEmpty {
                    Text(subline)
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subline ?? "")")
    }
}

/// The serif headline for a day at the given completion strength.
func dayHeadline(fraction: Double, hasAnything: Bool) -> String {
    guard hasAnything else { return "An open day" }
    switch fraction {
    case 1...: return "Day complete"
    case 0.7..<1: return "Strong day so far"
    case 0.4..<0.7: return "Finding the rhythm"
    case 0.01..<0.4: return "Getting going"
    default: return "Quiet so far"
    }
}

/// The quiet sub-line under the headline — "6 of 8 done · most of the way".
func daySubline(done: Int, total: Int) -> String? {
    guard total > 0 else { return nil }
    let shape: String
    let f = Double(done) / Double(total)
    switch f {
    case 1...: shape = "all of it"
    case 0.7..<1: shape = "most of the way"
    case 0.4..<0.7: shape = "halfway there"
    case 0.01..<0.4: shape = "early yet"
    default: shape = "the day's not over"
    }
    return "\(done) of \(total) done · \(shape)"
}

// MARK: - Task chips

/// One soft chip — ticked and tinted when done, gentle grey when open.
struct TaskChip: View {
    let title: String
    let isDone: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.sans(10, weight: .bold))
            }
            Text(title)
                .font(.sans(13, weight: isDone ? .medium : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(isDone ? accent.darkened : Theme.textPrimary.opacity(0.45))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(isDone ? accent.opacity(0.16) : Theme.textPrimary.opacity(0.05))
        )
        .accessibilityLabel("\(title), \(isDone ? "done" : "still open")")
    }
}

/// A wrapping flow of task chips with a "+N" overflow chip.
struct TaskChipsFlow: View {
    /// (title, isDone) pairs, done-first ordering is the caller's job.
    let items: [(title: String, isDone: Bool)]
    let accent: Color
    var maxVisible: Int = 6

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(items.prefix(maxVisible).enumerated()), id: \.offset) { _, item in
                TaskChip(title: item.title, isDone: item.isDone, accent: accent)
            }
            if items.count > maxVisible {
                Text("+\(items.count - maxVisible)")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.textPrimary.opacity(0.05))
                    )
            }
        }
    }
}

private extension Color {
    /// A hand-dimmed variant for legible chip text on a light tint.
    var darkened: Color {
        let hsl = hslComponents
        return Color(hsl: (h: hsl.h, s: min(1, hsl.s * 1.05), l: max(0, hsl.l * 0.55), a: hsl.a))
    }
}

// MARK: - Quiet inline action

/// A small text action used under TODAY — "Send a proof ·" style,
/// quiet by design so the card stays the loud part.
struct QuietActionLink: View {
    let icon: String
    let title: String
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.sans(12, weight: .semibold))
                    if badge {
                        Circle()
                            .fill(Theme.alertRed)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -3)
                    }
                }
                Text(title)
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Witness line

/// The single italic sentence with a colored rule — "Came back after
/// 3 quiet days." Generated from the real story, one line per visit.
struct WitnessLineView: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 3)
            Text(text)
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
        .accessibilityLabel(text)
    }
}

/// Pick one true witness sentence from the day's rhythm and the
/// published card — a comeback, a fresh milestone, a strong week, or
/// quiet honesty. Nil when there's nothing meaningful to say yet.
func makeWitnessLine(day: FriendDay, card: SeasonCard?) -> String? {
    let cal = Calendar.current

    // A milestone that landed within the last 7 days.
    if let fresh = card?.milestones.first(where: { milestone in
        guard milestone.isDone, let when = milestone.completedDate else { return false }
        let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: when), to: cal.startOfDay(for: Date())).day ?? 99
        return daysAgo >= 0 && daysAgo <= 7
    }) {
        return "Reached “\(fresh.title)” this week."
    }

    let bars = day.rhythmBars
    // A comeback — active today after two or more quiet days.
    if bars.count >= 4, let last = bars.last, last > 0 {
        var quiet = 0
        for value in bars.dropLast().reversed() {
            if value <= 0.01 { quiet += 1 } else { break }
        }
        if quiet >= 2 {
            return "Came back after \(quiet) quiet days."
        }
    }

    // A strong week — most of the last 7 days held real effort.
    // Hard rule: never "N of N", fractions, or percentages — plain
    // counts and sun language only.
    if bars.count >= 7 {
        let lastSeven = bars.suffix(7)
        let strong = lastSeven.filter { $0 >= 0.5 }.count
        if strong >= 7 {
            return "A strong week — every day full."
        }
        if strong >= 5 {
            return "A strong week — \(strong) full days."
        }
        let active = lastSeven.filter { $0 > 0 }.count
        if active >= 7 {
            return "Showed up every day this week."
        }
        if active >= 6 {
            return "Showed up \(active) days this week."
        }
    }

    // A steady stretch.
    if day.rhythmDays >= 7 {
        return "Showed up \(day.rhythmDays) days lately."
    }

    // Quiet honesty — only when truly quiet, never as a judgment.
    if day.rhythmDays <= 2, bars.suffix(3).allSatisfy({ $0 <= 0.01 }) {
        return "A quieter stretch — still here."
    }

    return nil
}

// MARK: - Destinations timeline

/// The season's milestones as a vertical timeline — reached ones get
/// a filled check and the day they landed, the one in flight shows
/// live progress, future ones wait as faded dots.
struct DestinationsTimeline: View {
    let milestones: [SeasonCardMilestone]
    let accent: Color
    let seasonStart: Date?

    private var currentId: UUID? {
        milestones.first(where: { !$0.isDone })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                row(milestone, isLast: index == milestones.count - 1)
            }
        }
    }

    private func row(_ milestone: SeasonCardMilestone, isLast: Bool) -> some View {
        let isCurrent = milestone.id == currentId
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                indicator(milestone, isCurrent: isCurrent)
                if !isLast {
                    Rectangle()
                        .fill(milestone.isDone ? accent.opacity(0.45) : Theme.textPrimary.opacity(0.12))
                        .frame(width: 2, height: 26)
                }
            }
            .frame(width: 26)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(milestone.title)
                    .font(.sans(15, weight: milestone.isDone || isCurrent ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(milestone.isDone || isCurrent ? 0.9 : 0.4))
                    .lineLimit(2)
                Text(detail(milestone, isCurrent: isCurrent))
                    .font(.sans(12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? accent.opacity(0.95) : Theme.textPrimary.opacity(0.4))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(milestone.title), \(milestone.isDone ? "reached" : isCurrent ? "in progress" : "ahead")")
    }

    @ViewBuilder
    private func indicator(_ milestone: SeasonCardMilestone, isCurrent: Bool) -> some View {
        if milestone.isDone {
            ZStack {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.sans(11, weight: .bold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 26, height: 26)
        } else if isCurrent {
            Circle()
                .strokeBorder(accent, lineWidth: 2.5)
                .background(Circle().fill(Theme.warmWheat))
                .frame(width: 26, height: 26)
        } else {
            Circle()
                .fill(Theme.textPrimary.opacity(0.12))
                .frame(width: 14, height: 14)
                .frame(width: 26, height: 26)
        }
    }

    private func detail(_ milestone: SeasonCardMilestone, isCurrent: Bool) -> String {
        if milestone.isDone {
            if let landed = milestone.completedDate, let start = seasonStart {
                let cal = Calendar.current
                let day = (cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: landed)).day ?? 0) + 1
                if day >= 1 { return "day \(day)" }
            }
            return "landed"
        }
        if let target = milestone.targetDate {
            return "by \(Self.milestoneTargetFormatter.string(from: target))"
        }
        return isCurrent ? "in motion" : "upcoming"
    }

    private static let milestoneTargetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - Seasons before

/// Past seasons as small posters in their own palettes, with a "+N"
/// tile opening the full chapter list.
struct SeasonsBeforeRow: View {
    let chapters: [PastSeasonSummary]
    var showsMilestones: Bool = true

    @State private var showAll: Bool = false

    private var visible: [PastSeasonSummary] { Array(chapters.prefix(2)) }
    private var overflow: Int { max(0, chapters.count - visible.count) }

    var body: some View {
        // 168pt square poster cards (r20) — horizontally scrollable so
        // the overflow tile never clips at the page edge.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visible) { chapter in
                    miniPoster(chapter)
                }
                if overflow > 0 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showAll = true
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Theme.duskDeep.opacity(0.85))
                            Text("+\(overflow)")
                                .font(.serif(24, weight: .medium))
                                .foregroundStyle(Theme.textCream)
                        }
                        .frame(width: 96, height: 168)
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(overflow) more past seasons")
                }
            }
        }
        .scrollClipDisabled(false)
        .sheet(isPresented: $showAll) {
            AllChaptersSheet(chapters: chapters, showsMilestones: showsMilestones)
        }
    }

    private func miniPoster(_ chapter: PastSeasonSummary) -> some View {
        let accent: Color = {
            if let hex = chapter.accentHex { return Color(hex: hex) }
            if let cover = chapter.coverId.flatMap(SeasonCoverKind.init(rawValue:)) {
                return Color(hex: cover.suggestedAccentHex)
            }
            return Theme.duskMid
        }()
        return ZStack(alignment: .bottomLeading) {
            Group {
                if let cover = chapter.coverId.flatMap(SeasonCoverKind.init(rawValue:)) {
                    SeasonCoverView(kind: cover, animated: false)
                } else {
                    LinearGradient(
                        colors: [accent, accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.name)
                    .font(.serifItalic(15, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(1)
                Text(chapter.ranDescription.replacingOccurrences(of: "ran ", with: ""))
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(width: 168, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chapter.name), \(chapter.ranDescription)")
    }
}

/// The full chapter list, opened from the "+N" tile.
struct AllChaptersSheet: View {
    let chapters: [PastSeasonSummary]
    var showsMilestones: Bool = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 148), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(chapters) { chapter in
                            PastSeasonChapterCard(chapter: chapter, showsMilestones: showsMilestones)
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Seasons before")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Week rhythm peek

/// Seven quiet day-dots showing the week's rhythm — opened from the
/// "Tue ›" link beside TODAY. Built from the last 7 rhythm bars.
struct WeekRhythmSheet: View {
    let name: String
    let bars: [Double]
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    private var weekBars: [Double] { Array(bars.suffix(7)) }

    /// Weekday letters ending today.
    private var dayLabels: [String] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return (0..<weekBars.count).reversed().map { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return "" }
            return formatter.string(from: day)
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Theme.textPrimary.opacity(0.15))
                .frame(width: 36, height: 4.5)
                .padding(.top, 10)

            VStack(spacing: 6) {
                Text("\(name)’s week")
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("How the last seven days held")
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            HStack(spacing: 14) {
                ForEach(Array(weekBars.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 8) {
                        Circle()
                            .fill(value > 0.01 ? accent.opacity(0.25 + 0.75 * value) : Theme.textPrimary.opacity(0.08))
                            .frame(width: 26, height: 26)
                            .overlay {
                                if value >= 0.95 {
                                    Image(systemName: "checkmark")
                                        .font(.sans(10, weight: .bold))
                                        .foregroundStyle(Theme.textCream)
                                }
                            }
                        Text(index < dayLabels.count ? dayLabels[index] : "")
                            .font(.sans(10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                }
            }

            Text("Full days fill all the way · quiet days stay soft. Never a streak, never a judgment.")
                .font(.serifItalic(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.warmWheat)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }
}
