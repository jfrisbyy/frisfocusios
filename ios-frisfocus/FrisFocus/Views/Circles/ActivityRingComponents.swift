//
//  ActivityRingComponents.swift
//  FrisFocus
//
//  Shared, presentational building blocks for the task-focused activity
//  look introduced in the profile revamp:
//
//   • `DayProgressRing` — a calm progress ring in a person's signature
//     color, wrapping any center content (a readout, a glyph, or an
//     avatar). Used large on the friend profile's "day at a glance" and
//     small around member / friend avatars so the whole app reads with
//     one consistent visual language. No ranking, no comparison — just a
//     warm sense of how full someone's day has been.
//   • `FlowLayout` — a lightweight wrapping layout so completed-task
//     chips flow naturally onto multiple lines.
//
//  Both are pure layout/visual types with no Store dependency, so any
//  surface can drop them in.
//

import SwiftUI

/// A rounded progress ring with arbitrary center content. The track is a
/// faint wash of `tint`; the filled arc is `tint` itself, drawn from the
/// top clockwise. Pass an avatar, a serif readout, or a glyph as `center`.
struct DayProgressRing<Center: View>: View {
    /// 0...1 — clamped internally, so callers can pass raw ratios.
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 9
    var trackOpacity: Double = 0.14
    @ViewBuilder var center: () -> Center

    private var clamped: Double { max(0, min(1, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                // A hairline minimum so a zero-progress ring still reads
                // as a ring (and a faint dot anchors the start), never a
                // hard empty gap.
                .trim(from: 0, to: max(0.0001, clamped))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.65), tint]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}

extension DayProgressRing where Center == EmptyView {
    /// Ring with no center content — for overlaying on top of an existing
    /// avatar rather than wrapping it.
    init(fraction: Double, tint: Color, lineWidth: CGFloat = 9, trackOpacity: Double = 0.14) {
        self.init(fraction: fraction, tint: tint, lineWidth: lineWidth, trackOpacity: trackOpacity) {
            EmptyView()
        }
    }
}

/// A minimal wrapping layout: lays subviews left-to-right, breaking onto
/// a new line whenever the next subview would overflow the proposed
/// width. Used for completed-task chips on the profile.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                widestRow = max(widestRow, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, x - spacing)

        let width = maxWidth == .infinity ? max(0, widestRow) : maxWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
