//
//  SunDayCard.swift
//  FrisFocus
//
//  The warm "today" card every profile shares — it replaces the small
//  progress ring + headline strip. It shows the person's actual sun
//  (the same living sun from the home screen), lit and sized to how
//  far into their day's goal they are, beside a quiet "to a productive
//  day" style line. Tapping the card springs it open to reveal a row
//  of small suns — one per recent day — a glanceable history instead of
//  a number grid.
//
//  Privacy: the card only ever renders the *shape* of a day (how lit
//  each sun is). Exact point numbers never appear here, so it is safe
//  to show whatever the friend already shares — their points stay
//  private behind the existing lock → ask → shared flow.
//

import SwiftUI
import UIKit

struct SunDayCard: View {
    /// Today's strength toward goal, 0…1 (already tier-resolved by the
    /// caller). Drives the big sun's size and glow.
    let ratio: Double
    /// The "to a productive day" style line — e.g. "50 to a productive
    /// day", "Strong day so far", or "Day complete".
    let headline: String
    /// The quiet supporting note — e.g. "6 of 8 done · most of the way".
    let subline: String?
    let accent: Color
    /// Recent days, oldest first, ending today (each 0…1). Empty hides
    /// the expand affordance.
    var recentRatios: [Double] = []

    @State private var expanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canExpand: Bool { recentRatios.count >= 2 }

    /// A small sky for the sun to glow against, following the hour so it
    /// feels like the home landscape rather than a flat swatch.
    private var sky: SkyPalette {
        let hour = Calendar.current.component(.hour, from: Date())
        let progress = max(0, min(1, (Double(hour) - 6) / 14))
        return SkyPalette.interpolated(progress: progress)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded, canExpand {
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
                RecentSunsStrip(ratios: recentRatios, sky: sky, accent: accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

    private var header: some View {
        Button {
            guard canExpand else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 16) {
                sunWell
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.serif(19, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    if let subline, !subline.isEmpty {
                        Text(subline)
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if canExpand {
                    Image(systemName: "chevron.down")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(headline). \(subline ?? "")")
        .accessibilityHint(canExpand ? (expanded ? "Hide recent days" : "Show recent days") : "")
    }

    /// The big sun, glowing against a small slice of sky.
    private var sunWell: some View {
        ZStack {
            LinearGradient(colors: sky.skyStops, startPoint: .top, endPoint: .bottom)
            SunStateMarkView(ratio: ratio, diameter: 44)
                .offset(y: 4)
        }
        .frame(width: 78, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }
}

// MARK: - Recent suns

/// A row of small suns — one per recent day, each lit and sized to how
/// that day went — over little slices of sky, with a quiet day label
/// under each. The most recent reads as today.
private struct RecentSunsStrip: View {
    let ratios: [Double]
    let sky: SkyPalette
    let accent: Color

    /// Up to the last ten days, oldest first.
    private var days: [Double] { Array(ratios.suffix(10)) }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, value in
                let daysAgo = (days.count - 1) - index
                let isToday = daysAgo == 0
                VStack(spacing: 6) {
                    ZStack {
                        LinearGradient(colors: sky.skyStops, startPoint: .top, endPoint: .bottom)
                        SunStateMarkView(ratio: value, diameter: 13)
                            .offset(y: 2)
                    }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isToday ? accent.opacity(0.65) : Color.white.opacity(0.08),
                                          lineWidth: isToday ? 1.4 : 0.6)
                    )

                    Text(label(daysAgo: daysAgo))
                        .font(.sans(9, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? accent : Theme.textPrimary.opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent days, each sun lit to how that day went")
    }

    private func label(daysAgo: Int) -> String {
        if daysAgo == 0 { return "Today" }
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

#Preview {
    ZStack {
        Theme.warmWheat.ignoresSafeArea()
        VStack(spacing: 20) {
            SunDayCard(
                ratio: 0.8,
                headline: "12 to a productive day",
                subline: "6 of 8 done · most of the way",
                accent: Color(hex: 0x639922),
                recentRatios: [0.2, 0.9, 1.0, 0.5, 0.0, 0.7, 0.85]
            )
            SunDayCard(
                ratio: 0.3,
                headline: "Getting going",
                subline: "2 of 8 done · early yet",
                accent: Color(hex: 0xC9602A)
            )
        }
        .padding()
    }
}
