//
//  SeasonCoverArt.swift
//  FrisFocus
//
//  The atmospheric season covers behind the poster profile pages. Each
//  `SeasonCoverKind` renders as a hand-tuned scene — gradient sky,
//  silhouettes, stars / waves / field bands drawn in Canvas — with a
//  slow drifting light glow when motion is allowed.
//
//  `ProfilePosterBackground` is the one hero background every profile
//  surface shares: chosen cover → custom header photo → accent band,
//  always with the same readability scrims on top.
//

import SwiftUI

// MARK: - Accent palette

/// The accents a person can claim for their season. The first eight
/// match the auto-assigned account palette so an un-customised profile
/// never looks foreign next to a customised one.
enum SeasonAccentPalette {
    static let options: [String] = [
        "C97B4B", "7B9E6B", "5B8AA6", "B5838D",
        "8E7CC3", "C9A227", "6B8F71", "A6674B",
        "8A4F2D", "3F8E8E", "72243E", "2C4A6E"
    ]
}

// MARK: - Cover palettes

extension SeasonCoverKind {
    /// Sky gradient, top → bottom.
    var skyColors: [Color] {
        switch self {
        case .firstLight: return [Color(hex: 0x4E5D78), Color(hex: 0xC98D7A), Color(hex: 0xF2CFA3)]
        case .goldenHour: return [Color(hex: 0x6E3B1F), Color(hex: 0xC1652A), Color(hex: 0xEFAF4E)]
        case .harvest:    return [Color(hex: 0x8A5A22), Color(hex: 0xC08A35), Color(hex: 0xD9A84E)]
        case .deepWinter: return [Color(hex: 0x2B3B4E), Color(hex: 0x5C7286), Color(hex: 0xAEC2CC)]
        case .nightSky:   return [Color(hex: 0x0B1026), Color(hex: 0x1B2440), Color(hex: 0x33406B)]
        case .coastline:  return [Color(hex: 0x1F5564), Color(hex: 0x3A8294), Color(hex: 0x9FCBC5)]
        case .forest:     return [Color(hex: 0x0F2802), Color(hex: 0x1F4407), Color(hex: 0x639922)]
        }
    }

    /// The drifting light glow's color.
    var glowColor: Color {
        switch self {
        case .firstLight: return Color(hex: 0xFFE2B8)
        case .goldenHour: return Color(hex: 0xFFD27A)
        case .harvest:    return Color(hex: 0xFFE3A1)
        case .deepWinter: return Color(hex: 0xDDEBF5)
        case .nightSky:   return Color(hex: 0xBFC8FF)
        case .coastline:  return Color(hex: 0xCFEDE2)
        case .forest:     return Color(hex: 0xD8E8A8)
        }
    }

    /// Silhouette / foreground ink for ridges, trees, waves.
    var inkColor: Color {
        switch self {
        case .firstLight: return Color(hex: 0x3A3550)
        case .goldenHour: return Color(hex: 0x4A2410)
        case .harvest:    return Color(hex: 0x5C3A12)
        case .deepWinter: return Color(hex: 0x243140)
        case .nightSky:   return Color(hex: 0x070B1A)
        case .coastline:  return Color(hex: 0x153E4A)
        case .forest:     return Color(hex: 0x0A1C02)
        }
    }

    /// The accent this cover suggests when the owner hasn't chosen one.
    var suggestedAccentHex: String {
        switch self {
        case .firstLight: return "B5838D"
        case .goldenHour: return "C97B4B"
        case .harvest:    return "C9A227"
        case .deepWinter: return "5B8AA6"
        case .nightSky:   return "8E7CC3"
        case .coastline:  return "3F8E8E"
        case .forest:     return "7B9E6B"
        }
    }
}

// MARK: - Seeded randomness

/// Tiny deterministic LCG so star fields and speckles are stable
/// across renders (no twinkle-on-every-layout).
private struct CoverRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }
}

// MARK: - Cover view

/// One atmospheric season scene. `animated` adds the slow drifting
/// glow; thumbnails pass false for a perfectly static mini poster.
/// `strength` (0…1) is the owner's day so far — a strong day glows
/// brighter and warmer, a quiet day settles calmer and dimmer.
struct SeasonCoverView: View {
    let kind: SeasonCoverKind
    var animated: Bool = true
    var strength: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift: Bool = false

    private var clampedStrength: Double { min(1, max(0, strength)) }

    var body: some View {
        ZStack {
            LinearGradient(colors: kind.skyColors, startPoint: .top, endPoint: .bottom)

            glow

            Canvas { context, size in
                drawScene(in: context, size: size)
            }
            .allowsHitTesting(false)

            // Day-strength wash: warm lift on strong days, a calm
            // dusk settle on quiet ones.
            if clampedStrength > 0.55 {
                LinearGradient(
                    colors: [kind.glowColor.opacity(0.16 * (clampedStrength - 0.55) / 0.45), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .blendMode(.screen)
                .allowsHitTesting(false)
            } else if clampedStrength < 0.45 {
                Color.black.opacity(0.13 * (0.45 - clampedStrength) / 0.45)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .accessibilityHidden(true)
    }

    /// The slow-breathing light source — a radial wash that drifts a
    /// touch sideways and brightens, like light moving through the day.
    /// A strong day breathes wider and brighter; a quiet day dims it.
    private var glow: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lift = 0.55 + 0.6 * clampedStrength
            RadialGradient(
                colors: [kind.glowColor.opacity((drift ? 0.55 : 0.38) * lift), .clear],
                center: .center,
                startRadius: 0,
                endRadius: max(w, h) * (0.45 + 0.18 * clampedStrength)
            )
            .frame(width: w * 1.4, height: w * 1.4)
            .position(x: w * (drift ? 0.62 : 0.42), y: glowYFraction * h)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }

    private var glowYFraction: CGFloat {
        switch kind {
        case .nightSky: return 0.22
        case .deepWinter: return 0.3
        case .coastline: return 0.45
        default: return 0.6
        }
    }

    // MARK: Scene drawing

    private func drawScene(in context: GraphicsContext, size: CGSize) {
        switch kind {
        case .firstLight:
            drawCloudBands(in: context, size: size, seed: 11)
            drawRidge(in: context, size: size, baseline: 0.86, amplitude: 0.10, opacity: 0.85, seed: 3)
        case .goldenHour:
            drawSunDisc(in: context, size: size, center: CGPoint(x: size.width * 0.5, y: size.height * 0.52), radius: size.width * 0.13)
            drawRidge(in: context, size: size, baseline: 0.80, amplitude: 0.12, opacity: 0.55, seed: 7)
            drawRidge(in: context, size: size, baseline: 0.90, amplitude: 0.09, opacity: 0.9, seed: 9)
        case .harvest:
            drawSunDisc(in: context, size: size, center: CGPoint(x: size.width * 0.72, y: size.height * 0.34), radius: size.width * 0.08)
            drawFieldBands(in: context, size: size)
        case .deepWinter:
            drawSpeckles(in: context, size: size, count: 70, seed: 21, color: .white, maxRadius: 1.6, opacity: 0.7)
            drawMoonHalo(in: context, size: size, center: CGPoint(x: size.width * 0.3, y: size.height * 0.26))
            drawRidge(in: context, size: size, baseline: 0.88, amplitude: 0.07, opacity: 0.5, seed: 13)
        case .nightSky:
            drawSpeckles(in: context, size: size, count: 90, seed: 5, color: Color(hex: 0xEFF2FF), maxRadius: 1.4, opacity: 0.9)
            drawCrescent(in: context, size: size)
            drawRidge(in: context, size: size, baseline: 0.92, amplitude: 0.06, opacity: 0.95, seed: 17)
        case .coastline:
            drawHorizonGlint(in: context, size: size)
            drawWaves(in: context, size: size)
        case .forest:
            drawTreeline(in: context, size: size, baseline: 0.74, scale: 0.10, opacity: 0.45, seed: 31)
            drawTreeline(in: context, size: size, baseline: 0.86, scale: 0.14, opacity: 0.85, seed: 37)
            drawMist(in: context, size: size)
        }
    }

    private func drawRidge(in context: GraphicsContext, size: CGSize, baseline: CGFloat, amplitude: CGFloat, opacity: Double, seed: UInt64) {
        var rng = CoverRandom(seed: seed)
        var path = Path()
        let steps = 14
        path.move(to: CGPoint(x: 0, y: size.height))
        var y = baseline - amplitude * CGFloat(rng.next())
        path.addLine(to: CGPoint(x: 0, y: size.height * y))
        for i in 1...steps {
            let x = size.width * CGFloat(i) / CGFloat(steps)
            y = baseline - amplitude * CGFloat(rng.next())
            path.addLine(to: CGPoint(x: x, y: size.height * y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(kind.inkColor.opacity(opacity)))
    }

    private func drawSunDisc(in context: GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat) {
        let halo = Path(ellipseIn: CGRect(x: center.x - radius * 2.2, y: center.y - radius * 2.2, width: radius * 4.4, height: radius * 4.4))
        context.fill(halo, with: .color(kind.glowColor.opacity(0.28)))
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(kind.glowColor.opacity(0.95)))
    }

    private func drawMoonHalo(in context: GraphicsContext, size: CGSize, center: CGPoint) {
        let r = size.width * 0.06
        let halo = Path(ellipseIn: CGRect(x: center.x - r * 2.4, y: center.y - r * 2.4, width: r * 4.8, height: r * 4.8))
        context.fill(halo, with: .color(.white.opacity(0.14)))
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .color(Color(hex: 0xF2F6FA).opacity(0.92)))
    }

    private func drawCrescent(in context: GraphicsContext, size: CGSize) {
        let r = size.width * 0.055
        let center = CGPoint(x: size.width * 0.74, y: size.height * 0.22)
        var moon = context
        moon.clip(to: Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)))
        moon.fill(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .color(Color(hex: 0xF4EBD3).opacity(0.95))
        )
        moon.fill(
            Path(ellipseIn: CGRect(x: center.x - r * 0.55, y: center.y - r * 1.15, width: r * 2, height: r * 2)),
            with: .color(kind.skyColors[0])
        )
    }

    private func drawSpeckles(in context: GraphicsContext, size: CGSize, count: Int, seed: UInt64, color: Color, maxRadius: CGFloat, opacity: Double) {
        var rng = CoverRandom(seed: seed)
        for _ in 0..<count {
            let x = CGFloat(rng.next()) * size.width
            let y = CGFloat(rng.next()) * size.height * 0.85
            let r = 0.4 + CGFloat(rng.next()) * maxRadius
            let a = (0.25 + rng.next() * 0.75) * opacity
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(color.opacity(a))
            )
        }
    }

    private func drawCloudBands(in context: GraphicsContext, size: CGSize, seed: UInt64) {
        var rng = CoverRandom(seed: seed)
        for i in 0..<4 {
            let y = size.height * (0.2 + CGFloat(i) * 0.12 + CGFloat(rng.next()) * 0.04)
            let w = size.width * (0.3 + CGFloat(rng.next()) * 0.45)
            let x = CGFloat(rng.next()) * (size.width - w)
            let h = size.height * 0.012
            let band = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: h / 2)
            context.fill(band, with: .color(.white.opacity(0.12 + rng.next() * 0.1)))
        }
    }

    private func drawFieldBands(in context: GraphicsContext, size: CGSize) {
        let bands: [(baseline: CGFloat, opacity: Double)] = [
            (0.66, 0.25), (0.76, 0.45), (0.86, 0.7), (0.95, 0.9)
        ]
        for (i, band) in bands.enumerated() {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height * band.baseline))
            path.addQuadCurve(
                to: CGPoint(x: size.width, y: size.height * (band.baseline + (i.isMultiple(of: 2) ? -0.04 : 0.04))),
                control: CGPoint(x: size.width * 0.5, y: size.height * (band.baseline - 0.05))
            )
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(kind.inkColor.opacity(band.opacity * 0.8)))
        }
    }

    private func drawHorizonGlint(in context: GraphicsContext, size: CGSize) {
        let y = size.height * 0.62
        let band = Path(roundedRect: CGRect(x: size.width * 0.18, y: y - 1, width: size.width * 0.64, height: 2.4), cornerRadius: 1.2)
        context.fill(band, with: .color(kind.glowColor.opacity(0.65)))
    }

    private func drawWaves(in context: GraphicsContext, size: CGSize) {
        var rng = CoverRandom(seed: 41)
        // The sea below the horizon.
        var sea = Path()
        sea.addRect(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))
        context.fill(sea, with: .color(kind.inkColor.opacity(0.35)))
        for i in 0..<6 {
            let y = size.height * (0.66 + CGFloat(i) * 0.055)
            let w = size.width * (0.18 + CGFloat(rng.next()) * 0.4)
            let x = CGFloat(rng.next()) * (size.width - w)
            var wave = Path()
            wave.move(to: CGPoint(x: x, y: y))
            wave.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - 3))
            context.stroke(wave, with: .color(.white.opacity(0.22 + rng.next() * 0.14)), lineWidth: 1.2)
        }
    }

    private func drawTreeline(in context: GraphicsContext, size: CGSize, baseline: CGFloat, scale: CGFloat, opacity: Double, seed: UInt64) {
        var rng = CoverRandom(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height * baseline))
        var x: CGFloat = 0
        while x < size.width {
            let treeWidth = size.width * (0.05 + CGFloat(rng.next()) * 0.05)
            let treeHeight = size.height * scale * (0.6 + CGFloat(rng.next()) * 0.8)
            let baseY = size.height * baseline
            path.addLine(to: CGPoint(x: x + treeWidth * 0.5, y: baseY - treeHeight))
            path.addLine(to: CGPoint(x: x + treeWidth, y: baseY))
            x += treeWidth
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(kind.inkColor.opacity(opacity)))
    }

    private func drawMist(in context: GraphicsContext, size: CGSize) {
        let band = Path(roundedRect: CGRect(x: -10, y: size.height * 0.78, width: size.width + 20, height: size.height * 0.06), cornerRadius: size.height * 0.03)
        context.fill(band, with: .color(.white.opacity(0.10)))
    }
}

// MARK: - Poster background

/// The shared hero background for every profile surface. Resolution
/// order: a chosen season cover → the custom header photo → the
/// signature accent band. Readability scrims are baked in so identity
/// text always reads cream on top.
struct ProfilePosterBackground: View {
    let coverId: String?
    let headerURL: URL?
    let accent: Color
    var animated: Bool = true
    /// The owner's day so far (0…1) — drives the living-light
    /// treatment on skies and photos alike.
    var strength: Double = 0.5

    private var cover: SeasonCoverKind? {
        coverId.flatMap(SeasonCoverKind.init(rawValue:))
    }

    private var clampedStrength: Double { min(1, max(0, strength)) }

    var body: some View {
        ZStack {
            if let cover {
                SeasonCoverView(kind: cover, animated: animated, strength: clampedStrength)
            } else if let headerURL {
                accent
                Color.clear
                    .overlay {
                        CachedImage(url: headerURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            accent
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)

                // The photo breathes with the day — a golden lift on
                // strong days, a calm dim on quiet ones.
                if clampedStrength > 0.55 {
                    RadialGradient(
                        colors: [Color(hex: 0xFFD27A).opacity(0.30 * (clampedStrength - 0.55) / 0.45), .clear],
                        center: .init(x: 0.7, y: 0.25),
                        startRadius: 0,
                        endRadius: 360
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                } else if clampedStrength < 0.45 {
                    Color.black.opacity(0.14 * (0.45 - clampedStrength) / 0.45)
                        .allowsHitTesting(false)
                }
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.92), accent, accent.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if clampedStrength > 0.55 {
                    RadialGradient(
                        colors: [Color(hex: 0xFFE2B8).opacity(0.24 * (clampedStrength - 0.55) / 0.45), .clear],
                        center: .init(x: 0.7, y: 0.3),
                        startRadius: 0,
                        endRadius: 320
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
            }

            // Readability scrims — slightly deeper over imagery.
            LinearGradient(
                colors: (cover != nil || headerURL != nil)
                    ? [Color.black.opacity(0.42), Color.black.opacity(0.16), Color.black.opacity(0.34)]
                    : [Color.black.opacity(0.34), Color.black.opacity(0.04), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Warm cream lift at the bottom so the hero melts into the page.
            LinearGradient(
                colors: [.clear, .clear, Theme.warmWheat.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Mini chapter poster

/// A small chapter card for one past season — its cover (or accent)
/// with the name and a couple of quiet facts. Used by the "Past
/// chapters" rail on profile pages.
struct PastSeasonChapterCard: View {
    let chapter: PastSeasonSummary
    /// Whether milestone counts may be shown (tier-gated by callers).
    var showsMilestones: Bool = true

    private var accent: Color {
        if let hex = chapter.accentHex { return Color(hex: hex) }
        if let cover = chapter.coverId.flatMap(SeasonCoverKind.init(rawValue:)) {
            return Color(hex: cover.suggestedAccentHex)
        }
        return Theme.duskMid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover = chapter.coverId.flatMap(SeasonCoverKind.init(rawValue:)) {
                        SeasonCoverView(kind: cover, animated: false)
                    } else {
                        LinearGradient(
                            colors: [accent, accent.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .frame(height: 78)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(chapter.name)
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.ranDescription.uppercased())
                    .font(.sans(8.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                if showsMilestones, chapter.milestonesReached > 0 {
                    Text(chapter.milestonesReached == 1
                        ? "1 milestone reached"
                        : "\(chapter.milestonesReached) milestones reached")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                } else {
                    Text(chapter.startDate.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.6))
        }
        .frame(width: 148)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chapter.name), \(chapter.ranDescription)")
    }
}

#Preview("Covers") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(SeasonCoverKind.allCases) { kind in
                SeasonCoverView(kind: kind)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomLeading) {
                        Text(kind.displayName)
                            .font(.serif(16, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(10)
                    }
            }
        }
        .padding()
    }
    .background(Theme.warmWheat)
}
