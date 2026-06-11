//
//  GoldenHourComponents.swift
//  FrisFocus
//
//  The shared visual language of the Golden Hour module — a warm gold
//  look used nowhere else in the app, so the user always knows which
//  world they're in. Holds the palette, the draining-time primitives,
//  and the orb/banner entry point that appears on Home and Circles only
//  while a moment is live or its wall is still viewable.
//

import SwiftUI
import UIKit

// MARK: - Palette

enum GoldenTheme {
    /// The signature gold — buttons, rings, countdowns.
    static let gold = Color(hex: 0xE9B544)
    /// Brighter highlight gold for pulses and gradients.
    static let goldBright = Color(hex: 0xF6D27A)
    /// Deep amber for pressed states and strokes.
    static let goldDeep = Color(hex: 0xB07F1F)
    /// The module's near-black warm backdrop.
    static let ink = Color(hex: 0x191205)
    /// Slightly lifted surface on top of the ink.
    static let inkRaised = Color(hex: 0x241A09)
    /// Cream text on dark golden surfaces.
    static let cream = Color(hex: 0xFBF3DF)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x2A1D06), Color(hex: 0x191205)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var goldGradient: LinearGradient {
        LinearGradient(
            colors: [goldBright, gold, goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Identifiable target

/// Wraps a circle id so `.fullScreenCover(item:)` can present the
/// Golden Hour surface for one circle.
struct GoldenHourTarget: Identifiable {
    let circleId: UUID
    var id: UUID { circleId }
}

// MARK: - Draining ring

/// A golden ring that drains clockwise as time runs out — the module's
/// core "scarcity" primitive. `remaining` is 1 → full, 0 → gone.
struct GoldenDrainRing: View {
    let remaining: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(GoldenTheme.gold.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, remaining)))
                .stroke(
                    GoldenTheme.goldGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A thin horizontal bar that drains as the wall's hour runs out.
struct GoldenDrainBar: View {
    let remaining: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GoldenTheme.gold.opacity(0.18))
                Capsule()
                    .fill(GoldenTheme.goldGradient)
                    .frame(width: max(0, min(1, remaining)) * proxy.size.width)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Orb / banner entry point

/// The Golden Hour entry point for Home and Circles. It only exists
/// while a moment is relevant:
///  • live (5-minute window)   → a pulsing golden takeover banner with
///    the capture countdown.
///  • viewing (the hour)       → a compact chip with a draining ring.
///  • the rest of the day      → nothing at all. Absence is the design.
struct GoldenHourBanner: View {
    @Environment(GoldenHourService.self) private var service
    let onOpen: (UUID) -> Void

    @State private var pulsing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            if let active = service.mostUrgentActive(now: now) {
                banner(for: active.moment, phase: active.phase, now: now)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func banner(for moment: GoldenHourMoment, phase: GoldenHourPhase, now: Date) -> some View {
        let circleName = service.circle(moment.circleId)?.name ?? "Your circle"
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onOpen(moment.circleId)
        } label: {
            if phase == .live {
                liveBanner(circleName: circleName, moment: moment, now: now)
            } else {
                viewingChip(circleName: circleName, moment: moment, now: now)
            }
        }
        .buttonStyle(.plain)
        .onAppear { pulsing = true }
        .accessibilityLabel(
            phase == .live
                ? "Golden Hour is live in \(circleName). Tap to capture."
                : "Golden Hour wall for \(circleName) is open. Tap to view."
        )
    }

    private func liveBanner(circleName: String, moment: GoldenHourMoment, now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GoldenTheme.ink)
                .scaleEffect(pulsing ? 1.12 : 0.94)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)

            VStack(alignment: .leading, spacing: 1) {
                Text("GOLDEN HOUR · \(circleName.uppercased())")
                    .font(.sans(10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(GoldenTheme.ink.opacity(0.8))
                    .lineLimit(1)
                Text("Capture now — it's happening")
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(GoldenTheme.ink)
            }

            Spacer(minLength: 8)

            Text(GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: now))
                .font(.sans(19, weight: .bold).monospacedDigit())
                .foregroundStyle(GoldenTheme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GoldenTheme.goldGradient)
                .shadow(color: GoldenTheme.gold.opacity(pulsing ? 0.55 : 0.25), radius: pulsing ? 16 : 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(GoldenTheme.goldBright.opacity(0.8), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
        .padding(.horizontal, 16)
    }

    private func viewingChip(circleName: String, moment: GoldenHourMoment, now: Date) -> some View {
        let total = GoldenHourSchedule.viewingWindow
        let remaining = max(0, moment.wallClosesAt.timeIntervalSince(now)) / total
        return HStack(spacing: 10) {
            ZStack {
                GoldenDrainRing(remaining: remaining, lineWidth: 2.5)
                    .frame(width: 26, height: 26)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GoldenTheme.gold)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("GOLDEN HOUR · \(circleName.uppercased())")
                    .font(.sans(9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(GoldenTheme.gold)
                    .lineLimit(1)
                Text("Wall closes in \(GoldenHourSchedule.wallCountdownString(until: moment.wallClosesAt, from: now))")
                    .font(.sans(12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GoldenTheme.cream)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GoldenTheme.gold.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(GoldenTheme.ink.opacity(0.92))
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(GoldenTheme.gold.opacity(0.45), lineWidth: 1)
        )
    }
}
