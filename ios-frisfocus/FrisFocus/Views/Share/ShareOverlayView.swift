//
//  ShareOverlayView.swift
//  FrisFocus
//
//  The full-frame day-overlay — rendered live on the viewfinder AND
//  composited into the export by ShareCardRenderer, so what you see is
//  exactly what leaves the app.
//
//  Anatomy (bottom-left cluster, quiet and premium):
//   1. The sun-state mark (always present — it's the mark)
//   2. Season name — serif italic, toggleable
//   3. Completed-task chips — individually tappable on the viewfinder;
//      tapped-off chips render dimmed/dashed with a ✕ while composing
//      and are EXCLUDED from the export
//   4. Numbers — the percent (never raw points), off by default
//   5. Attribution — orb glyph + "@USERNAME · FRISFOCUS". Mandatory on
//      anything leaving the app; absent on in-app shares.
//
//  `layer` lets the video compositor render the chrome and the sun as
//  two separate transparent frames (identical layout) so the sun can
//  animate its rise over the clip's first ~1.2 s.
//

import SwiftUI

// MARK: - Modes

enum ShareOverlayMode: Equatable {
    /// Live on the viewfinder — chips tappable, off-chips visible
    /// (dimmed/dashed), attribution previewed.
    case composing
    /// Flattened for export. `attributed` adds the identity line —
    /// true for anything leaving the app, false for in-app shares.
    case render(attributed: Bool)
}

/// Which layer of the overlay to draw. Layout is identical across
/// cases — hidden parts keep their space — so the compositor's chrome
/// and sun frames align pixel-perfectly.
enum ShareOverlayLayer: Equatable {
    case all
    case chrome
    case sunOnly
}

// MARK: - Overlay

struct ShareOverlayView: View {
    let context: ShareDayContext
    let options: ShareOverlayOptions
    let mode: ShareOverlayMode
    let username: String
    var layer: ShareOverlayLayer = .all
    var showChipHint: Bool = false
    var onToggleChip: ((UUID) -> Void)? = nil
    var bottomPadding: CGFloat = 20

    private var isComposing: Bool { mode == .composing }

    private var sunVisible: Bool { layer != .chrome }
    private var chromeVisible: Bool { layer != .sunOnly }

    private var attributionVisible: Bool {
        switch mode {
        case .composing: return true
        case .render(let attributed): return attributed
        }
    }

    /// Chips to draw: while composing every chip stays visible (off
    /// ones dimmed); in a render the hidden ones are excluded entirely.
    private var drawnChips: [ShareTaskChip] {
        guard options.showTasks else { return [] }
        if isComposing { return context.chips }
        return context.chips.filter { !options.hiddenChipIds.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-day extra — a faint golden radial wash over the frame.
            if context.ratio >= 1.0 {
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFC668).opacity(0.16), location: 0.0),
                        .init(color: Color(hex: 0xFFC668).opacity(0.05), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ],
                    center: UnitPoint(x: 0.28, y: 0.82),
                    startRadius: 0,
                    endRadius: 520
                )
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(false)
            }

            // Soft bottom scrim under the text for legibility — subtle,
            // never a heavy band.
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.18), location: 0.55),
                        .init(color: Color.black.opacity(0.42), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(false)

            cluster
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - Cluster

    private var cluster: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sun + season name
            HStack(alignment: .center, spacing: 13) {
                sunMark
                    .opacity(sunVisible ? 1 : 0)

                if options.showSeasonName {
                    Text(context.seasonName)
                        .font(.serifItalic(22, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.97))
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                        .lineLimit(2)
                        .opacity(chromeVisible ? 1 : 0)
                }
            }
            .allowsHitTesting(false)

            // Completed-task chips — tappable while composing.
            if !drawnChips.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(drawnChips) { chip in
                        ShareChipView(
                            chip: chip,
                            isOff: options.hiddenChipIds.contains(chip.id),
                            interactive: isComposing,
                            onTap: { onToggleChip?(chip.id) }
                        )
                    }
                }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(isComposing && chromeVisible)
                .animation(.easeOut(duration: 0.25), value: options.hiddenChipIds)
            }

            // Numbers — the percent, opt-in only.
            if options.showNumbers {
                Text("\(context.percent)%")
                    .font(.sans(13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.88))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }

            // First-use hint while composing.
            if isComposing && showChipHint && !context.chips.isEmpty && options.showTasks {
                Text("tap a task to hide it from the share")
                    .font(.serifItalic(12, weight: .regular))
                    .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.62))
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Attribution — identity, never a toggle.
            if attributionVisible {
                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0xFFE2A6), Color(hex: 0xF0A340)],
                                center: UnitPoint(x: 0.4, y: 0.35),
                                startRadius: 0,
                                endRadius: 6
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: Color(hex: 0xF0A340).opacity(0.7), radius: 3)

                    Text("@\(username.uppercased()) · FRISFOCUS")
                        .font(.sans(10.5, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.75))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .padding(.top, 2)
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.bottom, bottomPadding)
    }

    @ViewBuilder
    private var sunMark: some View {
        switch context.sun {
        case .day(let ratio):
            SunStateMarkView(ratio: ratio, diameter: 44)
        case .week(let ratios):
            WeekSunsMarkView(ratios: ratios)
        }
    }
}

// MARK: - Chip

private struct ShareChipView: View {
    let chip: ShareTaskChip
    let isOff: Bool
    let interactive: Bool
    let onTap: () -> Void

    var body: some View {
        if interactive {
            Button {
                onTap()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOff ? "\(chip.label), hidden from share" : chip.label)
            .accessibilityHint(isOff ? "Tap to show on the share" : "Tap to hide from the share")
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Text(chip.label)
                .font(.sans(11, weight: .medium))
                .lineLimit(1)

            if isOff {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(Color(hex: 0xFFF2DC).opacity(isOff ? 0.62 : 0.95))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.white.opacity(isOff ? 0.04 : 0.14))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    Color(hex: 0xFFE9C4).opacity(isOff ? 0.3 : 0.38),
                    style: StrokeStyle(lineWidth: 1, dash: isOff ? [4, 3] : [])
                )
        )
        .opacity(isOff ? 0.55 : 1)
        .contentShape(Capsule())
    }
}

#Preview("Composing") {
    ZStack {
        Color(hex: 0x2B2218).ignoresSafeArea()
        ShareOverlayView(
            context: ShareDayContext(
                sun: .day(ratio: 1.04),
                ratio: 1.04,
                percent: 104,
                seasonName: "Keeping Up, Not Drowning",
                chips: [
                    ShareTaskChip(id: UUID(), label: "Lifted"),
                    ShareTaskChip(id: UUID(), label: "Built · 3 hrs"),
                    ShareTaskChip(id: UUID(), label: "Read")
                ]
            ),
            options: ShareOverlayOptions(),
            mode: .composing,
            username: "jordan",
            showChipHint: true
        )
    }
}
