//
//  ProfileMirrorKit.swift
//  FrisFocus
//
//  The shared building blocks of the redesigned profile — the "mirror"
//  page that self and friend views both render. Only the action row
//  differs between the two; everything else here is identical, so what
//  a friend sees at a given tier is exactly what you preview.
//
//  Every measurement follows the S4 redline (pt on a 390pt-wide
//  device): ring = avatar+10 @ 3pt stroke, halo ≤ avatar+28; glass
//  corner controls 38; primary pill 44; task rows 40 with 22pt checks.
//  The hero shell (stretchy header, top bar, identity card, board)
//  lives in ProfileHeroKit.swift.
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
/// by segments cut into the ring stroke + a base glyph and by swapping
/// the FILL to a story preview — never by changing the ring's meaning.
///
/// Anatomy at the default 86pt avatar (all values scale linearly):
/// ring 96 @ 3pt stroke · halo ≤ 114 · rays ≤ 10pt ticks only at a
/// full day · total footprint ≤ 116. The layout frame is the avatar
/// circle alone (86), so a 14pt gap keeps neighbours clear of the halo.
struct SunRingAvatar: View {
    /// Today's sun ratio (points ÷ target). May exceed 1 — rays only
    /// appear at ≥ 1.
    let ratio: Double

    var diameter: CGFloat = 86

    // Fill
    var photoURL: URL? = nil
    var initials: String = "?"
    var fillColor: Color = Theme.textPrimary

    // Story state
    /// Number of story units (one ring segment each). 0 = no story.
    var storyUnitCount: Int = 0
    /// How many of those units have been viewed (dimmed segments).
    var viewedUnitCount: Int = 0
    /// Latest story frame — replaces the fill while a story is live.
    var storyPreviewURL: URL? = nil

    var reduceMotion: Bool = false
    /// Slow shimmer flag driven by the parent (unviewed stories).
    var shimmer: Bool = false

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var isFull: Bool { ratio >= 1.0 }
    private var hasStory: Bool { storyUnitCount > 0 }
    private var allViewed: Bool { hasStory && viewedUnitCount >= storyUnitCount }
    /// While a story is live the fill previews it — even once watched.
    /// Watched state shows only through the dimmed ring segments.
    private var showsPreview: Bool { hasStory && storyPreviewURL != nil }

    /// Linear scale from the 86pt reference.
    private var s: CGFloat { diameter / 86 }
    /// Ring diameter: avatar + 10 (5pt outside the avatar edge).
    private var ringDiameter: CGFloat { diameter + 10 * s }
    private var ringStroke: CGFloat { 3 * s }
    /// Halo footprint: avatar + 28 (extends max 14pt past the avatar).
    private var haloDiameter: CGFloat { diameter + 28 * s }
    private var rayLength: CGFloat { 10 * s }

    private var warm: Color { Color.lerpHSL(Color(hex: 0x9A6E33), Theme.sunWarm, t: clamped) }
    private var core: Color { Color.lerpHSL(Color(hex: 0xC79A55), Theme.sunCore, t: clamped) }

    var body: some View {
        ZStack {
            haloLayer
            fillLayer
            sunRing
            if isFull { rayTicks }
        }
        // The LAYOUT footprint stays the avatar circle; ring, halo and
        // rays draw beyond it (≤ 1.35× avatar) without pushing siblings.
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottom) {
            if hasStory { baseGlyph }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: clamped)
    }

    /// The soft warm halo — a radial glow held inside the 114pt
    /// footprint, growing and warming with the day.
    private var haloLayer: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.40),
                        .init(color: core.opacity(0.12 + 0.26 * clamped + (isFull ? 0.10 : 0)), location: 0.68),
                        .init(color: Theme.sunOuter.opacity(0.05 + 0.14 * clamped), location: 0.85),
                        .init(color: .clear, location: 1.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: haloDiameter / 2
                )
            )
            .frame(width: haloDiameter, height: haloDiameter)
            .opacity(reduceMotion ? 1 : (shimmer ? 1 : 0.92))
    }

    @ViewBuilder
    private var fillLayer: some View {
        Group {
            if showsPreview, let url = storyPreviewURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { photoOrInitials }
            } else {
                photoOrInitials
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 3 * s))
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
                .font(.serif(diameter * 0.4, weight: .light))
                .foregroundStyle(Theme.textCream.opacity(0.95))
        }
    }

    /// The 3pt sun-ring at 96pt. Continuous normally; when a story is
    /// live it splits into one segment per story unit with 2pt gaps cut
    /// into the stroke itself — viewed segments dim to 40%.
    @ViewBuilder
    private var sunRing: some View {
        let base = 0.55 + 0.45 * clamped
        if hasStory {
            let n = max(1, storyUnitCount)
            // 2pt gaps expressed as a fraction of the ring circumference.
            let gapFrac = min(0.05, (2 * s) / (.pi * ringDiameter))
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .trim(
                            from: CGFloat(i) / CGFloat(n) + gapFrac / 2,
                            to: CGFloat(i + 1) / CGFloat(n) - gapFrac / 2
                        )
                        .stroke(
                            ringGradient,
                            style: StrokeStyle(lineWidth: ringStroke, lineCap: .butt)
                        )
                        .opacity(base * (i < viewedUnitCount ? 0.4 : 1.0))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: ringDiameter - ringStroke, height: ringDiameter - ringStroke)
        } else {
            Circle()
                .strokeBorder(ringGradient, lineWidth: ringStroke)
                .opacity(base)
                .frame(width: ringDiameter, height: ringDiameter)
                .shadow(color: core.opacity(isFull ? 0.45 : 0.2), radius: isFull ? 4 : 2)
        }
    }

    private var ringGradient: LinearGradient {
        LinearGradient(colors: [core, warm], startPoint: .top, endPoint: .bottom)
    }

    /// Rays at a full day only — short 2pt ticks on the ring, ≤ 10pt
    /// long, keeping the total footprint inside the 116pt hard cap.
    private var rayTicks: some View {
        ForEach(0..<8, id: \.self) { i in
            Capsule()
                .fill(core.opacity(0.85))
                .frame(width: 2 * s, height: rayLength)
                .offset(y: -(ringDiameter / 2 + rayLength / 2))
                .rotationEffect(.degrees(Double(i) * 45))
        }
    }

    /// The 22pt glass play glyph at the ring's base center.
    private var baseGlyph: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            Circle().fill(Color.black.opacity(0.32))
            Image(systemName: allViewed ? "checkmark" : "play.fill")
                .font(.system(size: 8 * s, weight: .bold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 22 * s, height: 22 * s)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        // Centered on the ring's lowest point (5pt below the avatar frame).
        .offset(y: 11 * s + 5 * s)
    }
}

// MARK: - Glass corner control

/// A 38pt circular translucent-dark blurred control for the header
/// corners (icon 15pt).
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
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(
                        ZStack {
                            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            Circle().fill(Color.black.opacity(0.32))
                        }
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                if badge {
                    Circle().fill(Theme.alertRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                        .offset(x: -1, y: 1)
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
/// season. The fixed scrim is a bottom-anchored 190pt gradient
/// (transparent → 52% warm-black at 55% → 72% at the bottom) so ANY
/// photo keeps text legible.
struct MirrorHeaderBackground: View {
    let headerURL: URL?
    let accent: Color
    /// The owner's day (0…1) — a soft golden lift on strong days.
    var strength: Double = 0.5

    private var clampedStrength: Double { min(1, max(0, strength)) }
    private var warmBlack: Color { Color(hex: 0x140D06) }

    var body: some View {
        ZStack(alignment: .bottom) {
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

            // The always-on 190pt bottom scrim.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: warmBlack.opacity(0.52), location: 0.55),
                    .init(color: warmBlack.opacity(0.72), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Status line + season pill

/// The single merged status slot — user-set or witness-authored, always
/// identical styling (italic serif 15.5). The 12pt pencil affordance
/// only appears when editable.
struct MirrorStatusLine: View {
    let text: String
    var editable: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            Text("“\(text)”")
                .font(.serifItalic(15.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if editable, let onEdit {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.sans(12, weight: .semibold))
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

/// The quiet 28pt season pill — a 7pt category-colored dot, the season
/// name, and the season's day count (season info, never a task
/// denominator).
struct MirrorSeasonPill: View {
    let seasonName: String
    let dayNumber: Int?
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(dayNumber != nil ? "\(seasonName) · day \(dayNumber!)" : seasonName)
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(Theme.textPrimary.opacity(0.08)))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.05), lineWidth: 0.5))
    }
}

// MARK: - The day block (sun + qualitative line + seven-sun horizon)

/// The single rounded day card (r18, 15pt v / 16pt h padding): today's
/// sun (≤ 52×44 incl. glow, its own hairline underneath), a qualitative
/// line (never a count), and the seven-sun horizon strip.
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
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                todaySunGlyph

                VStack(alignment: .leading, spacing: 4) {
                    Text(qualitativeDayLine(ratio: ratio))
                        .font(.serif(16.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("\(weekday) · \(seasonName)")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            SevenSunHorizon(ratios: horizonRatios, accent: accent, onTapDay: onTapDay)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mirrorCard()
    }

    /// Today's sun — total footprint including glow capped at 52×44,
    /// with the hairline only under the glyph.
    private var todaySunGlyph: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.18))
                .frame(width: 52, height: 1)
            CenteredSunView(ratio: ratio, maxDiameter: 22)
                .frame(width: 52, height: 44)
                .offset(y: 6)
        }
        .frame(width: 52, height: 45, alignment: .bottom)
        .clipped()
    }
}

/// The iconic strip — the last 7 days as mini suns above ONE continuous
/// shared hairline (1pt @ 16%) running the full card width. Each sun's
/// bottom offset above the hairline is ratio-scaled 2pt (empty) → 22pt
/// (full) — a skyline, not a row. Today is 16pt with a 1.5pt outline.
struct SevenSunHorizon: View {
    /// Oldest first, ending today. Up to 7.
    let ratios: [Double]
    let accent: Color
    var onTapDay: (Int) -> Void

    private var shown: [Double] { Array(ratios.suffix(7)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .bottom) {
                // The ONE shared hairline, full card width.
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.16))
                    .frame(height: 1)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { idx, r in
                        let daysAgo = (shown.count - 1) - idx
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onTapDay(daysAgo)
                        } label: {
                            HorizonMiniSun(ratio: r, isToday: daysAgo == 0)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52, alignment: .bottom)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(daysAgo == 0 ? "Today's sun" : "\(daysAgo) days ago")
                    }
                }
            }
            .frame(height: 52)

            Text("last 7 days")
                .font(.sans(9.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.42))
        }
    }
}

/// One mini sun of the horizon — 13–16pt, glow scaled with its ratio,
/// micro-rays (≤ 3pt) only at a full day, lifted 2→22pt above the
/// shared hairline by its ratio.
private struct HorizonMiniSun: View {
    let ratio: Double
    let isToday: Bool

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var isFull: Bool { ratio >= 1.0 }
    private var size: CGFloat { isToday ? 16 : 13 + 2 * clamped }
    /// Bottom offset above the hairline: 2pt empty → 22pt full.
    private var lift: CGFloat { 2 + 20 * clamped }

    private var warm: Color { Color.lerpHSL(Color(hex: 0x9A6E33), Theme.sunWarm, t: clamped) }
    private var core: Color { Color.lerpHSL(Color(hex: 0xC79A55), Theme.sunCore, t: clamped) }

    var body: some View {
        ZStack {
            // Glow scaled with the day.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: core.opacity(0.10 + 0.35 * clamped), location: 0.25),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 1.1
                    )
                )
                .frame(width: size * 2.2, height: size * 2.2)

            // Micro-rays only at a full day, ≤ 3pt.
            if isFull {
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(core.opacity(0.8))
                        .frame(width: 1.2, height: 3)
                        .offset(y: -(size / 2 + 2.5))
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }

            // The disc.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [core, warm],
                        center: UnitPoint(x: 0.45, y: 0.42),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)
                .opacity(0.55 + 0.45 * clamped)

            // Today's 1.5pt outline.
            if isToday {
                Circle()
                    .strokeBorder(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                    .frame(width: size + 7, height: size + 7)
            }
        }
        .frame(width: size, height: size)
        .offset(y: -lift)
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

// MARK: - Task rows (shared by the today board)

/// One task row on the board.
struct MirrorTaskRow: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isDone: Bool
}

/// One 40pt task row — 22pt rounded-square check (r7), 13.5pt label,
/// 11pt check→label gap, 14pt side padding. Done rows fill the check
/// in the category color and strike the label at 55% opacity.
struct MirrorTaskRowView: View {
    let row: MirrorTaskRow
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            checkbox
            Text(row.title)
                .font(.sans(13.5, weight: row.isDone ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(row.isDone ? 0.55 : 0.88))
                .strikethrough(row.isDone, color: Theme.textPrimary.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .accessibilityLabel("\(row.title), \(row.isDone ? "done" : "open")")
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(row.isDone ? tint : Color.clear)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(row.isDone ? Color.clear : Theme.textPrimary.opacity(0.22), lineWidth: 1.5)
            )
            .overlay {
                if row.isDone {
                    Image(systemName: "checkmark")
                        .font(.sans(11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

// MARK: - Action row pieces

/// The dark 44pt primary pill in the action row (Edit profile /
/// Friends / Add) — 13pt semibold label, full remaining width.
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
            HStack(spacing: 7) {
                if isWorking {
                    ProgressView().controlSize(.small)
                        .tint(filled ? Theme.textCream : Theme.textPrimary)
                } else if let icon {
                    Image(systemName: icon).font(.sans(11, weight: .bold))
                }
                Text(title).font(.sans(13, weight: .semibold))
            }
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
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

/// The 38pt round dark glass companion button in the action row
/// (paint / chat), with an 8pt unread dot inside its top-right.
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
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Theme.textPrimary.opacity(0.92))
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                if badge {
                    Circle().fill(Theme.alertRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color(hex: 0xFFFBF1), lineWidth: 1.2))
                        .offset(x: -2, y: 2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}


