//
//  MilestoneShareOverlayView.swift
//  FrisFocus
//
//  The milestone card's full-frame overlay — rendered live on the
//  viewfinder AND composited into the export by ShareCardRenderer, so
//  what you see is exactly what leaves the app.
//
//  Anatomy (bottom-left cluster, same warm share language as the day
//  card, instantly different at a glance):
//   1. Journey strip — tiny rounded thumbnails of the documented
//      process, toggleable
//   2. The flag mark (always present — it's this card's glyph) beside
//      a tracking-spaced MILESTONE eyebrow
//   3. The milestone title — big serif centerpiece, never toggleable
//   4. Progress ("3 OF 5 STEPS") or the LANDED stamp, plus points —
//      each toggleable
//   5. Season name — serif italic, toggleable
//   6. Timeline — "WEEK 2 → LANDED JUN 11", toggleable
//   7. Attribution — orb glyph + "@USERNAME · FRISFOCUS". Mandatory on
//      anything leaving the app; absent on in-app shares.
//
//  `layer` mirrors the day overlay: the chrome and the flag mark render
//  as two separate transparent frames (identical layout) so the flag
//  can ride the signature rise over a clip's first ~1.2 s.
//

import SwiftUI

struct MilestoneShareOverlayView: View {
    let context: ShareMilestoneContext
    let options: MilestoneShareOptions
    let mode: ShareOverlayMode
    let username: String
    var layer: ShareOverlayLayer = .all
    var bottomPadding: CGFloat = 20

    private var markVisible: Bool { layer != .chrome }
    private var chromeVisible: Bool { layer != .sunOnly }

    private var attributionVisible: Bool {
        switch mode {
        case .composing: return true
        case .render(let attributed): return attributed
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Landed extra — the same faint golden radial wash a full
            // day earns, anchoring the celebration.
            if context.isLanded {
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

            // Soft bottom scrim under the text for legibility.
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
                .frame(height: 300)
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(false)

            cluster
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Cluster

    private var cluster: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Journey strip — the documented process at a glance.
            if options.showJourneyStrip && !context.journeyThumbs.isEmpty {
                journeyStrip
                    .opacity(chromeVisible ? 1 : 0)
            }

            // Flag mark + eyebrow.
            HStack(alignment: .center, spacing: 10) {
                MilestoneFlagMarkView(isLanded: context.isLanded, diameter: 36)
                    .opacity(markVisible ? 1 : 0)

                Text("MILESTONE")
                    .font(.sans(10.5, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.7))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .opacity(chromeVisible ? 1 : 0)
            }

            // The title — the point of the card, never toggleable.
            Text(context.title)
                .font(.serif(28, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.97))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(chromeVisible ? 1 : 0)

            // Progress / LANDED stamp + points.
            if options.showProgress || options.showPoints {
                HStack(spacing: 12) {
                    if options.showProgress {
                        if context.isLanded {
                            landedStamp
                        } else {
                            Text(context.progressText)
                                .font(.sans(11.5, weight: .semibold))
                                .tracking(1.8)
                                .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.85))
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }

                    if options.showPoints && context.pointValue > 0 {
                        Text("\(context.pointValue) PTS")
                            .font(.sans(11.5, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0xFFD98A).opacity(0.92))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
                .opacity(chromeVisible ? 1 : 0)
            }

            // Season name — serif italic, family resemblance.
            if options.showSeasonName {
                Text(context.seasonName)
                    .font(.serifItalic(16, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.82))
                    .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 1)
                    .lineLimit(2)
                    .opacity(chromeVisible ? 1 : 0)
            }

            // Timeline — the journey in one quiet line.
            if options.showTimeline {
                Text(context.timelineText)
                    .font(.sans(10, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.6))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .opacity(chromeVisible ? 1 : 0)
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
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.bottom, bottomPadding)
    }

    // MARK: - Pieces

    /// The proud landed mark — tracking-spaced gold text in a thin
    /// stamped capsule, tilted just a touch.
    private var landedStamp: some View {
        Text("LANDED")
            .font(.sans(11, weight: .bold))
            .tracking(3.0)
            .foregroundStyle(Color(hex: 0xFFD98A))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule()
                    .strokeBorder(Color(hex: 0xFFD98A).opacity(0.75), lineWidth: 1.2)
            )
            .rotationEffect(.degrees(-2.5))
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    /// Tiny rounded thumbnails of the journey photos, oldest first.
    private var journeyStrip: some View {
        HStack(spacing: 6) {
            ForEach(context.journeyThumbs) { thumb in
                Color.clear
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(uiImage: thumb.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color(hex: 0xFFF6E6).opacity(0.4), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
            }
        }
    }
}

#Preview("Landed") {
    ZStack {
        Color(hex: 0x2B2218).ignoresSafeArea()
        MilestoneShareOverlayView(
            context: ShareMilestoneContext(
                title: "Launch the studio site",
                isLanded: true,
                stepsDone: 5,
                stepsTotal: 5,
                pointValue: 250,
                seasonName: "Keeping Up, Not Drowning",
                weekNumber: 2,
                completedDate: Date(),
                journeyThumbs: []
            ),
            options: MilestoneShareOptions(),
            mode: .composing,
            username: "jordan"
        )
    }
}

#Preview("In motion") {
    ZStack {
        Color(hex: 0x2B2218).ignoresSafeArea()
        MilestoneShareOverlayView(
            context: ShareMilestoneContext(
                title: "Run the half marathon",
                isLanded: false,
                stepsDone: 3,
                stepsTotal: 5,
                pointValue: 400,
                seasonName: "Body of Work",
                weekNumber: 6,
                completedDate: nil,
                journeyThumbs: []
            ),
            options: MilestoneShareOptions(),
            mode: .composing,
            username: "jordan"
        )
    }
}
