//
//  ProfileMirrorKit.swift
//  FrisFocus
//
//  The shared building blocks of the redesigned profile — the "mirror"
//  page that self and friend views both render. Only the action row
//  differs between the two; everything else here is identical, so what
//  a friend sees at a given tier is exactly what you preview.
//
//  The signature piece is `SunRingAvatar`: one avatar bubble whose RING
//  is today's sun (glow/thickness/halo from `ratio = points ÷ target`)
//  and whose FILL becomes a story preview when a story is active. Two
//  signals, never conflated — the fill tells the story, the ring keeps
//  the day. Reused everywhere a person's face appears.
//
//  Hard rule across this file: NO denominators, NO fractions, NO point
//  values ever render. Only completions ("N today"), sun language, and
//  qualitative copy.
//

import SwiftUI
import UIKit

// MARK: - Sun-ring avatar (the shared bubble)

/// The one avatar bubble used across the app. The ring is today's sun,
/// computed from `ratio` (points ÷ target). Story presence is signalled
/// by segment ticks + a base glyph and by swapping the FILL to a story
/// preview — never by changing the ring's meaning.
struct SunRingAvatar: View {
    /// Today's sun ratio (points ÷ target). May exceed 1 — the halo
    /// only flares fully at ≥ 1.
    let ratio: Double

    var diameter: CGFloat = 110

    // Fill
    var photoURL: URL? = nil
    var initials: String = "?"
    var fillColor: Color = Theme.textPrimary

    // Story state
    /// Number of story units (one segment tick each). 0 = no story.
    var storyUnitCount: Int = 0
    /// How many of those units have been viewed (dim ticks).
    var viewedUnitCount: Int = 0
    /// Latest story frame — replaces the fill while a story is unwatched.
    var storyPreviewURL: URL? = nil

    var reduceMotion: Bool = false
    /// Slow shimmer flag driven by the parent (unviewed stories).
    var shimmer: Bool = false

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var isFull: Bool { ratio >= 1.0 }
    private var hasStory: Bool { storyUnitCount > 0 }
    private var allViewed: Bool { hasStory && viewedUnitCount >= storyUnitCount }
    /// While a story is live the fill previews it — even once watched.
    /// Watched state shows only through the dimmed segment ticks.
    private var showsPreview: Bool { hasStory && storyPreviewURL != nil }

    /// The crisp gold ring — a clean luminous band that thickens
    /// slightly with the day.
    private var ringWidth: CGFloat { diameter * (0.050 + 0.014 * clamped) }
    /// The clear dark gap between the ring and the fill.
    private var gapWidth: CGFloat { diameter * 0.038 }

    private var warm: Color { Color.lerpHSL(Color(hex: 0x9A6E33), Theme.sunWarm, t: clamped) }
    private var core: Color { Color.lerpHSL(Color(hex: 0xC79A55), Theme.sunCore, t: clamped) }

    var body: some View {
        ZStack {
            haloLayer
            backingDisc
            fillLayer
            sunRing
            if hasStory { segmentTicks }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottom) {
            if hasStory { baseGlyph }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: clamped)
    }

    /// The dark disc behind the fill — it renders the clean dark gap
    /// between the gold ring and the photo, per the mock's construction.
    private var backingDisc: some View {
        Circle()
            .fill(Color(hex: 0x2A1B0C))
            .frame(width: diameter - ringWidth, height: diameter - ringWidth)
    }

    // The outer glow — a soft warm halo breathing outward from the
    // ring; it grows and warms with the day and flares at goal.
    private var haloLayer: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .clear, location: 0.28),
                            .init(color: core.opacity(0.14 + 0.30 * clamped), location: 0.42),
                            .init(color: Theme.sunOuter.opacity(0.06 + 0.20 * clamped), location: 0.62),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * (isFull ? 1.0 : 0.82)
                    )
                )
                .frame(width: diameter * 2.0, height: diameter * 2.0)
                .blur(radius: 6)

            if isFull {
                ForEach([-58.0, -29.0, 0.0, 29.0, 58.0], id: \.self) { angle in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [core.opacity(0.7), .clear],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: diameter * 0.05 + 1, height: diameter * 0.34)
                        .blur(radius: 1.5)
                        .offset(y: -diameter * 0.72)
                        .rotationEffect(.degrees(angle))
                }
            }
        }
        .opacity(reduceMotion ? 1 : (shimmer ? 1 : 0.9))
    }

    @ViewBuilder
    private var fillLayer: some View {
        let inset = ringWidth + gapWidth
        Group {
            if showsPreview, let url = storyPreviewURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { photoOrInitials }
            } else {
                photoOrInitials
            }
        }
        .frame(width: diameter - inset * 2, height: diameter - inset * 2)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var photoOrInitials: some View {
        if let photoURL {
            CachedImage(url: photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: { initialsDisc }
        } else {
            initialsDisc
        }
    }

    private var initialsDisc: some View {
        ZStack {
            Circle().fill(fillColor)
            Text(initials.isEmpty ? "?" : initials)
                .font(.serif(diameter * 0.34, weight: .light))
                .foregroundStyle(Theme.textCream.opacity(0.95))
        }
    }

    private var sunRing: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [core, warm],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: ringWidth
            )
            .opacity(0.55 + 0.45 * clamped)
            .shadow(color: core.opacity(0.2 + (isFull ? 0.4 : 0.1)), radius: isFull ? 10 : 6)
    }

    /// Thin arc segments just outside the ring — one per story unit,
    /// viewed ones dim. Signals story presence without touching the sun.
    private var segmentTicks: some View {
        let n = max(1, storyUnitCount)
        let gap: CGFloat = n > 1 ? 0.045 : 0
        let tickD = diameter + 9
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                let start = CGFloat(i) / CGFloat(n) + gap / 2
                let end = CGFloat(i + 1) / CGFloat(n) - gap / 2
                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        Theme.textCream.opacity(i < viewedUnitCount ? 0.28 : 0.95),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .frame(width: tickD, height: tickD)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var baseGlyph: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Image(systemName: allViewed ? "checkmark" : "play.fill")
                .font(.system(size: diameter * 0.075, weight: .bold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: diameter * 0.19, height: diameter * 0.19)
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.6))
        .offset(y: 3)
    }
}

// MARK: - Glass corner control

/// A circular translucent-dark blurred control for the header corners.
struct MirrorGlassControl: View {
    let icon: String
    var badge: Bool = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 44, height: 44)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            Circle().fill(Color.black.opacity(0.30))
                        }
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                if badge {
                    Circle().fill(Theme.alertRed)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Header background (full-bleed identity photo + fixed scrim)

/// The full-bleed header — pure identity (photo or accent), NOT the
/// season. A fixed bottom scrim always guarantees legible text.
struct MirrorHeaderBackground: View {
    let headerURL: URL?
    let accent: Color
    /// The owner's day (0…1) — a soft golden lift on strong days.
    var strength: Double = 0.5

    private var clampedStrength: Double { min(1, max(0, strength)) }

    var body: some View {
        ZStack {
            if let headerURL {
                accent
                Color.clear
                    .overlay {
                        CachedImage(url: headerURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { accent }
                    }
                    .clipped()
                    .allowsHitTesting(false)
                if clampedStrength > 0.6 {
                    RadialGradient(
                        colors: [Color(hex: 0xFFD27A).opacity(0.26 * (clampedStrength - 0.6) / 0.4), .clear],
                        center: .init(x: 0.7, y: 0.22),
                        startRadius: 0, endRadius: 360
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.95), accent, accent.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            // The always-on scrim: transparent up top, deepening to a
            // warm near-black over the lower half. Any photo stays legible.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.36),
                    .init(color: Color(hex: 0x140D06).opacity(0.38), location: 0.64),
                    .init(color: Color(hex: 0x140D06).opacity(0.78), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Status line + season pill

/// The single merged status slot — user-set or witness-authored, always
/// identical styling. The pencil affordance only appears when editable.
struct MirrorStatusLine: View {
    let text: String
    var editable: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            Text("“\(text)”")
                .font(.serifItalic(17, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if editable, let onEdit {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit your status")
            }
            Spacer(minLength: 0)
        }
    }
}

/// The quiet season pill — a category-colored dot, the season name, and
/// the season's day count (season info, never a task denominator).
struct MirrorSeasonPill: View {
    let seasonName: String
    let dayNumber: Int?
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 8, height: 8)
            Text(dayNumber != nil ? "\(seasonName) · day \(dayNumber!)" : seasonName)
                .font(.sans(13.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(Theme.textPrimary.opacity(0.08)))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.05), lineWidth: 0.5))
    }
}

// MARK: - The day block (sun + qualitative line + seven-sun horizon)

/// The single rounded day card: today's sun, a qualitative line (never
/// a count), and the seven-sun horizon strip.
struct MirrorDayBlock: View {
    let ratio: Double
    let weekday: String
    let seasonName: String
    /// The last-7 days' ratios, oldest first ending today.
    let horizonRatios: [Double]
    let accent: Color
    /// daysAgo (0 = today) tapped in the horizon.
    var onTapDay: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                // Today's sun over its own short horizon hairline.
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.18))
                        .frame(width: 58, height: 1)
                    CenteredSunView(ratio: ratio, maxDiameter: 34)
                        .frame(width: 68, height: 60)
                        .offset(y: 8)
                }
                .frame(width: 68, height: 66)
                .clipped()

                VStack(alignment: .leading, spacing: 5) {
                    Text(qualitativeDayLine(ratio: ratio))
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(weekday) · \(seasonName)")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            SevenSunHorizon(ratios: horizonRatios, accent: accent, onTapDay: onTapDay)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.05), lineWidth: 0.8)
        )
    }
}

/// The iconic strip — the last 7 days as mini suns, each rising to its
/// true height above its OWN short baseline segment (seven separate
/// little horizons, per the mock). Today is slightly larger.
struct SevenSunHorizon: View {
    /// Oldest first, ending today. Up to 7.
    let ratios: [Double]
    let accent: Color
    var onTapDay: (Int) -> Void

    private var shown: [Double] { Array(ratios.suffix(7)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.offset) { idx, r in
                    let daysAgo = (shown.count - 1) - idx
                    HorizonDayColumn(ratio: r, isToday: daysAgo == 0) {
                        onTapDay(daysAgo)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64)

            Text("last 7 days")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.42))
        }
    }
}

/// One day of the horizon — a mini sun above its own short baseline.
private struct HorizonDayColumn: View {
    let ratio: Double
    let isToday: Bool
    let action: () -> Void

    private var clamped: Double { min(max(ratio, 0), 1) }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            GeometryReader { proxy in
                let lift = max(0, proxy.size.height - 34)
                ZStack(alignment: .bottom) {
                    // The day's own little horizon.
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.16))
                        .frame(height: 1)
                        .padding(.horizontal, 3)

                    CenteredSunView(ratio: ratio, maxDiameter: isToday ? 19 : 16)
                        .frame(width: 30, height: 30)
                        .offset(y: -(2 + clamped * lift))
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isToday ? "Today's sun" : "An earlier day")
    }
}

/// The qualitative day line — 6–8 variants keyed to ratio bands, chosen
/// by day so it doesn't repeat stale within a day. Never a count.
func qualitativeDayLine(ratio: Double) -> String {
    let seed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    let full = ["A full day — every sun risen.", "A full day. You showed up.", "Every sun's up. A full day."]
    let strong = ["A strong day, still going.", "Well into a strong day.", "A strong day taking shape."]
    let mid = ["In motion.", "Finding the rhythm.", "The day's underway."]
    let early = ["The day's still early.", "Just getting going.", "Early yet — the sun's low."]
    let none = ["The day's still early.", "A fresh page.", "The sun's low — plenty of day left."]
    let table: [String]
    switch ratio {
    case 1...: table = full
    case 0.66..<1: table = strong
    case 0.33..<0.66: table = mid
    case 0.01..<0.33: table = early
    default: table = none
    }
    return table[seed % table.count]
}

// MARK: - Category section (checked-first, nested scroll)

/// One task row in a category box.
struct MirrorTaskRow: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isDone: Bool
}

/// A category on the (tier-visible) board — a header with a completion-
/// only count and a box of up to 5 checked-first rows, scrolling within
/// itself when there are more.
struct MirrorCategorySection: View {
    let category: Category
    /// Already sorted checked-first by the caller.
    let rows: [MirrorTaskRow]
    /// When false (e.g. the Open tier, where task names stay private),
    /// only the header + count render — no task box.
    var showsBox: Bool = true

    private var tint: Color { Color(hex: category.hexColor) }
    private var doneCount: Int { rows.filter { $0.isDone }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(category.displayName.uppercased())
                    .font(.sans(12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.62))
                Spacer(minLength: 8)
                if doneCount > 0 {
                    Text("\(doneCount) today")
                        .font(.sans(13.5, weight: .bold))
                        .foregroundStyle(tint)
                } else {
                    Text("quiet so far")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.38))
                }
            }
            .padding(.horizontal, 2)

            if showsBox, !rows.isEmpty {
                MirrorCategoryBox(rows: rows, tint: tint)
            }
        }
    }
}

/// The rounded card holding the rows. ≤ 5 → plain; > 5 → a fixed-height
/// internal scroll region with a bottom fade + "N more · scroll" cue
/// that both vanish once scrolled to the end.
private struct MirrorCategoryBox: View {
    let rows: [MirrorTaskRow]
    let tint: Color

    private let rowHeight: CGFloat = 52
    private let maxRows: Int = 5

    @State private var atBottom: Bool = false

    private var overflowing: Bool { rows.count > maxRows }
    private var boxHeight: CGFloat { rowHeight * CGFloat(maxRows) }

    var body: some View {
        Group {
            if overflowing {
                ScrollView(.vertical, showsIndicators: false) {
                    rowStack
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.y >= geo.contentSize.height - geo.containerSize.height - 6
                        } action: { _, isAtBottom in
                            atBottom = isAtBottom
                        }
                }
                .frame(height: boxHeight)
                .overlay(alignment: .bottom) { fadeCue }
            } else {
                rowStack
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.05), lineWidth: 0.8)
        )
    }

    private var rowStack: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                MirrorTaskRowView(row: row, tint: tint)
                    .frame(height: rowHeight)
            }
        }
    }

    @ViewBuilder
    private var fadeCue: some View {
        if !atBottom {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, Color(hex: 0xFFFBF1)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)

                HStack(spacing: 5) {
                    Text("\(rows.count - maxRows) more · scroll")
                        .font(.sans(12, weight: .medium))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.sans(9, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.42))
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }
}

private struct MirrorTaskRowView: View {
    let row: MirrorTaskRow
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            checkbox
            Text(row.title)
                .font(.sans(16, weight: row.isDone ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(row.isDone ? 0.5 : 0.88))
                .strikethrough(row.isDone, color: Theme.textPrimary.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .accessibilityLabel("\(row.title), \(row.isDone ? "done" : "open")")
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(row.isDone ? tint : Color.clear)
            .frame(width: 26, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(row.isDone ? Color.clear : Theme.textPrimary.opacity(0.22), lineWidth: 1.6)
            )
            .overlay {
                if row.isDone {
                    Image(systemName: "checkmark")
                        .font(.sans(13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

// MARK: - Action row pieces

/// The dark primary pill in the action row (Edit profile / Friends / Add).
struct MirrorPrimaryPill: View {
    let title: String
    var icon: String? = nil
    var filled: Bool = true
    var isWorking: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().controlSize(.small)
                        .tint(filled ? Theme.textCream : Theme.textPrimary)
                } else if let icon {
                    Image(systemName: icon).font(.sans(13, weight: .bold))
                }
                Text(title).font(.sans(16, weight: .semibold))
            }
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
                    .shadow(color: .black.opacity(filled ? 0.18 : 0), radius: 10, x: 0, y: 4)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(filled ? 0 : 0.16), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

/// The round glass companion button in the action row (paint / chat).
struct MirrorActionCircle: View {
    let icon: String
    var badge: Bool = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(Theme.textPrimary.opacity(0.92))
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                if badge {
                    Circle().fill(Theme.alertRed)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color(hex: 0xFFFBF1), lineWidth: 1.5))
                        .offset(x: 0, y: 0)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - "Seen as" chip (self only)

/// The demoted tier-preview chip — a small bordered chip that opens a
/// menu to preview Quiet / Open / Full.
struct SeenAsChip: View {
    @Binding var tier: VisibilityTier

    private func name(_ t: VisibilityTier) -> String {
        switch t {
        case .quiet: return "Quiet"
        case .open: return "Open"
        case .full: return "Full"
        }
    }

    var body: some View {
        Menu {
            ForEach(VisibilityTier.allCases, id: \.self) { t in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) { tier = t }
                } label: {
                    Label(name(t), systemImage: tier == t ? "checkmark" : "eye")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.sans(10, weight: .semibold))
                Text("Seen as: \(name(tier))")
                    .font(.sans(12.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.sans(8, weight: .bold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Theme.textPrimary.opacity(0.04)))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 0.8))
        }
        .accessibilityLabel("Preview how friends see you. Currently \(name(tier)).")
    }
}

// MARK: - Identity handle line

/// The single stat line under the name: `@handle · N days shown up`
/// (the number bold). Falls back to just the day count when no handle.
struct MirrorHandleLine: View {
    let handle: String?
    let daysShownUp: Int

    var body: some View {
        Group {
            if let handle, !handle.isEmpty {
                handleText(handle) + boldDays() + Text(" days shown up")
            } else {
                boldDays() + Text(" days shown up")
            }
        }
        .font(.sans(13.5, weight: .regular))
        .foregroundStyle(Theme.textCream.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("\(handle ?? ""), \(daysShownUp) days shown up")
    }

    private func handleText(_ handle: String) -> Text {
        let h = handle.hasPrefix("@") ? handle : "@\(handle)"
        return Text("\(h) · ")
    }

    private func boldDays() -> Text {
        Text("\(daysShownUp)").font(.sans(13.5, weight: .bold))
    }
}
