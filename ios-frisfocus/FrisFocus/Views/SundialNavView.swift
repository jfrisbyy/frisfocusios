//
//  SundialNavView.swift
//  FrisFocus
//
//  The app's primary bottom navigation chrome. A custom engraved
//  half-disc sundial:
//   • Outer/inner etched arcs and a dashed inner sweep arc
//   • Cardinal tick marks at 0° (right), 45°, 90° (top), 135°, 180°
//     (left), with minor tick dots interleaved
//   • Faint brass filigree lines from the pivot to each cardinal
//   • A tapered black dial hand with a brass-tipped diamond at its
//     tip and a small counterweight ball just below the pivot
//   • A brass pivot disc anchoring the hand
//   • The central "sun" capture button — a fully rendered glowing sun
//     with halo, core, highlight, and "+" symbol
//   • Two icon buttons (Home, Circles) sitting at the lower-left and
//     lower-right of the dial face
//
//  The hand swings between three positions based on the active
//  destination — Home (upper-left ≈ 45°), Capture (straight up ≈ 90°),
//  Circles (upper-right ≈ 135°). On sub-pages the hand is hidden but
//  the rest of the chrome remains so the user can still capture or
//  return home from anywhere.
//
//  The view is stateless: the parent owns the active destination and
//  the three tap callbacks. Light haptics fire on every tap (medium
//  for the capture sun).
//

import SwiftUI
import UIKit

/// Where the sundial currently points.
enum SundialDestination: Equatable {
    case home
    case capture
    case circles
    /// Used by sub-pages — keeps the dial face visible but hides the
    /// swinging hand so the user knows they're off the main rotation.
    case subPage
}

struct SundialNavView: View {
    let active: SundialDestination
    let onCaptureTap: () -> Void
    let onHomeTap: () -> Void
    let onCirclesTap: () -> Void

    // MARK: - Scrub state

    /// Live hand angle while the user is dragging across the dial.
    /// `nil` whenever the hand is parked on its fixed destination.
    @State private var scrubAngle: Double?
    @State private var isScrubbing: Bool = false
    @State private var lastScrubDestination: SundialDestination?
    @State private var engageHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var boundaryHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Discreet rest / brighten-on-touch / bloom state

    /// True whenever a finger is resting on the dial chrome. Drives the
    /// "brighten when you reach for it" behaviour — the whole dial lifts
    /// to full opacity while touched, then eases back to its quiet rest.
    @State private var isTouched: Bool = false
    /// Transient scale applied to the whole dial. Pops to `bloomPeak`
    /// the moment the user taps a destination, then springs back to 1.
    @State private var bloomScale: CGFloat = 1.0
    /// Guards the delayed rest-fade so a fresh touch cancels a pending one.
    @State private var fadeToken: UUID = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Discreet appearance constants

    /// Resting opacity — the dial recedes while you scroll and read,
    /// but stays high enough that the sun "+" remains findable at a glance.
    private let restOpacity: Double = 0.62
    /// How large the dial briefly grows on a navigation tap.
    private let bloomPeak: CGFloat = 1.3

    // MARK: - Layout constants

    /// Angle in degrees (0 = right pole of dial, 90 = top, 180 = left).
    /// Hand swings to these positions.
    private let handAngleHome: Double = 45      // upper-left of pivot
    private let handAngleCapture: Double = 90   // straight up
    private let handAngleCircles: Double = 135  // upper-right of pivot

    /// Icon angles — sit low on the dial face, just inside the arc
    /// where it meets the diameter line.
    private let iconAngleHome: Double = 18      // lower-left of dial
    private let iconAngleCircles: Double = 162  // lower-right of dial

    var body: some View {
        GeometryReader { geo in
            ZStack {
                dialFace(in: geo.size)

                // Dial hand — only visible on top-level destinations.
                if active != .subPage {
                    dialHand(in: geo.size)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.95))
                        )
                }

                brassPivot(in: geo.size)

                homeIconButton(in: geo.size)
                circlesIconButton(in: geo.size)
                sunCaptureButton(in: geo.size)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: active)
            .contentShape(Rectangle())
            // Brighten the instant a finger lands anywhere on the chrome,
            // then ease back to the quiet rest state on release. Runs
            // simultaneously so it never steals taps from the buttons or
            // the scrub gesture.
            .simultaneousGesture(touchGesture)
            .gesture(scrubGesture(in: geo.size))
            // Quiet at rest, full strength while touched / scrubbing.
            .opacity(isBright ? 1.0 : restOpacity)
            // Bloom from the pivot/sun (y ≈ 0.72) so the dial pops out
            // around the sun rather than sliding up from the screen edge.
            .scaleEffect(bloomScale, anchor: UnitPoint(x: 0.5, y: 0.72))
            .animation(.easeInOut(duration: 0.40), value: isTouched)
            .animation(.easeInOut(duration: 0.30), value: isScrubbing)
        }
        .frame(height: 104)
        .allowsHitTesting(true)
    }

    /// The dial is at full strength whenever the user is interacting with
    /// it — a resting touch, an in-flight scrub, or mid-bloom after a tap.
    private var isBright: Bool {
        isTouched || isScrubbing || bloomScale > 1.001
    }

    // MARK: - Touch (brighten-on-reach) gesture

    /// Zero-distance drag used purely to detect that a finger is on the
    /// dial. It never commits navigation; the separate `scrubGesture`
    /// owns that. `simultaneousGesture` keeps the buttons fully tappable.
    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                if !isTouched { isTouched = true }
            }
            .onEnded { _ in
                scheduleRestFade()
            }
    }

    /// Eases the dial back to its quiet resting opacity a beat after the
    /// finger lifts, unless another touch arrives first.
    private func scheduleRestFade() {
        let token = UUID()
        fadeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard fadeToken == token, !isScrubbing else { return }
            isTouched = false
        }
    }

    // MARK: - Bloom

    /// Quick "pop" the whole dial gives when the user taps a destination:
    /// it grows to `bloomPeak`, then springs back to its small rest size.
    /// Under Reduce Motion the size pop is skipped — the brightness lift
    /// alone carries the feedback.
    private func bloom() {
        guard !reduceMotion else { return }
        // Higher damping keeps the pop calm — it grows cleanly with no
        // jittery overshoot, then settles smoothly back to rest size.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            bloomScale = bloomPeak
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
                bloomScale = 1.0
            }
        }
    }

    // MARK: - Scrub gesture

    /// Lets the user drag along the dial arc and the hand follows the
    /// finger; navigation commits the moment the finger crosses into
    /// a home or circles zone. Capture stays a tap-only action so a
    /// scrub never accidentally opens the capture sheet.
    private func scrubGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let angle = angleFor(point: value.location, size: size)
                if !isScrubbing {
                    isScrubbing = true
                    engageHaptic.prepare()
                    engageHaptic.impactOccurred()
                    boundaryHaptic.prepare()
                }
                scrubAngle = angle
                let dest = destinationForAngle(angle)
                if dest != lastScrubDestination {
                    if lastScrubDestination != nil {
                        boundaryHaptic.impactOccurred()
                        boundaryHaptic.prepare()
                    }
                    lastScrubDestination = dest
                    switch dest {
                    case .home where active != .home:
                        onHomeTap()
                    case .circles where active != .circles:
                        onCirclesTap()
                    default:
                        break
                    }
                }
            }
            .onEnded { _ in
                isScrubbing = false
                scrubAngle = nil
                lastScrubDestination = nil
            }
    }

    /// Converts a finger position (in the dial's local space) into a
    /// hand angle in degrees, using the same convention as `arcPoint`
    /// — 0° sits on the left pole, 90° straight up, 180° on the right
    /// pole. Clamped to the hand's travel range (45°–135°).
    private func angleFor(point: CGPoint, size: CGSize) -> Double {
        let dx = Double(point.x - centerX(size))
        let dy = Double(centerY(size) - point.y)
        var deg = atan2(dy, -dx) * 180 / .pi
        deg = max(handAngleHome, min(handAngleCircles, deg))
        return deg
    }

    private func destinationForAngle(_ angle: Double) -> SundialDestination {
        let homeToCapture = (handAngleHome + handAngleCapture) / 2     // 67.5°
        let captureToCircles = (handAngleCapture + handAngleCircles) / 2 // 112.5°
        if angle < homeToCapture { return .home }
        if angle < captureToCircles { return .capture }
        return .circles
    }

    // MARK: - Geometry helpers

    private func centerX(_ size: CGSize) -> CGFloat { size.width / 2 }

    /// Pivot sits ~72 % down the frame so the sun can extend just past
    /// the dial's flat edge without falling off-screen.
    private func centerY(_ size: CGSize) -> CGFloat { size.height * 0.72 }

    /// Half-disc radius. Height-constrained on narrow screens, width-
    /// constrained on wider devices.
    private func arcRadius(_ size: CGSize) -> CGFloat {
        min(size.width * 0.40, size.height * 0.66)
    }

    /// `(centerX - r·cos, centerY - r·sin)` — anchored at the pivot,
    /// 0° points right, 90° points up, 180° points left.
    private func arcPoint(
        angleDegrees: Double,
        radius: CGFloat,
        size: CGSize
    ) -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(
            x: centerX(size) - radius * CGFloat(cos(rad)),
            y: centerY(size) - radius * CGFloat(sin(rad))
        )
    }

    // MARK: - Dial face (etched half-disc)

    @ViewBuilder
    private func dialFace(in size: CGSize) -> some View {
        Canvas { context, _ in
            let cx = centerX(size)
            let cy = centerY(size)
            let r = arcRadius(size)

            // Outer arc — almost-invisible interior wash + a thin edge.
            let outerArc = Path { p in
                p.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false
                )
                p.addLine(to: CGPoint(x: cx + r, y: cy))
                p.closeSubpath()
            }
            context.fill(
                outerArc,
                with: .color(Theme.textPrimary.opacity(0.025))
            )
            context.stroke(
                Path { p in
                    p.addArc(
                        center: CGPoint(x: cx, y: cy),
                        radius: r,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                },
                with: .color(Theme.textPrimary.opacity(0.22)),
                lineWidth: 0.8
            )

            // Inner companion arc — the double-line engraving.
            context.stroke(
                Path { p in
                    p.addArc(
                        center: CGPoint(x: cx, y: cy),
                        radius: r - 6,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                },
                with: .color(Theme.textPrimary.opacity(0.12)),
                lineWidth: 0.5
            )

            // Inner sweep arc — where the hand visually tracks, dashed.
            let dashedStyle = StrokeStyle(lineWidth: 0.5, dash: [0.5, 2])
            context.stroke(
                Path { p in
                    p.addArc(
                        center: CGPoint(x: cx, y: cy),
                        radius: r * 0.6,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                },
                with: .color(Theme.textPrimary.opacity(0.08)),
                style: dashedStyle
            )

            // Cardinal tick marks — slightly past the outer arc.
            let cardinalAngles: [Double] = [180, 135, 90, 45, 0]
            for angle in cardinalAngles {
                let rad = angle * .pi / 180
                let inner = CGPoint(
                    x: cx - r * CGFloat(cos(rad)),
                    y: cy - r * CGFloat(sin(rad))
                )
                let outer = CGPoint(
                    x: cx - (r + 5) * CGFloat(cos(rad)),
                    y: cy - (r + 5) * CGFloat(sin(rad))
                )
                context.stroke(
                    Path { p in
                        p.move(to: inner)
                        p.addLine(to: outer)
                    },
                    with: .color(Theme.textPrimary.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                )
            }

            // Minor tick dots — between the cardinals.
            let minorAngles: [Double] = [165, 150, 120, 105, 75, 60, 30, 15]
            for angle in minorAngles {
                let rad = angle * .pi / 180
                let pt = CGPoint(
                    x: cx - r * CGFloat(cos(rad)),
                    y: cy - r * CGFloat(sin(rad))
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: pt.x - 0.75,
                        y: pt.y - 0.75,
                        width: 1.5,
                        height: 1.5
                    )),
                    with: .color(Theme.textPrimary.opacity(0.32))
                )
            }

            // Brass filigree — faint warm lines from the pivot to each
            // cardinal, almost invisible but adds the engraved feel.
            for angle in cardinalAngles {
                let rad = angle * .pi / 180
                let target = CGPoint(
                    x: cx - r * 0.75 * CGFloat(cos(rad)),
                    y: cy - r * 0.75 * CGFloat(sin(rad))
                )
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: cx, y: cy))
                        p.addLine(to: target)
                    },
                    with: .color(Theme.sunShadow.opacity(0.08)),
                    lineWidth: 0.5
                )
            }
        }
    }

    // MARK: - Dial hand (tapered, brass-tipped)

    @ViewBuilder
    private func dialHand(in size: CGSize) -> some View {
        let cx = centerX(size)
        let cy = centerY(size)
        let r = arcRadius(size)

        let angle: Double = {
            if let scrubAngle { return scrubAngle }
            switch active {
            case .home: return handAngleHome
            case .capture: return handAngleCapture
            case .circles: return handAngleCircles
            case .subPage: return handAngleCapture
            }
        }()
        let rad = angle * .pi / 180
        let tipX = cx - r * CGFloat(cos(rad))
        let tipY = cy - r * CGFloat(sin(rad))

        ZStack {
            // Tapered body — narrows toward the tip.
            Path { p in
                let pivotWidth: CGFloat = 2.0
                let tipWidth: CGFloat = 0.8
                let perp = rad + .pi / 2

                let pivotDX = pivotWidth * CGFloat(cos(perp))
                let pivotDY = pivotWidth * CGFloat(sin(perp))
                let tipDX = tipWidth * CGFloat(cos(perp))
                let tipDY = tipWidth * CGFloat(sin(perp))

                p.move(to: CGPoint(x: cx + pivotDX, y: cy + pivotDY))
                p.addLine(to: CGPoint(x: tipX + tipDX, y: tipY + tipDY))
                p.addLine(to: CGPoint(x: tipX - tipDX, y: tipY - tipDY))
                p.addLine(to: CGPoint(x: cx - pivotDX, y: cy - pivotDY))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.12, blue: 0.11),
                        Color(red: 0.23, green: 0.23, blue: 0.22)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(0.92)

            // Tip diamond — black with a brass jewel.
            Circle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.11))
                .frame(width: 4.4, height: 4.4)
                .position(x: tipX, y: tipY)
            Circle()
                .fill(Theme.sunShadow)
                .frame(width: 1.9, height: 1.9)
                .position(x: tipX, y: tipY)

            // Counterweight — small ball just below the pivot.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.11),
                            Color(red: 0.23, green: 0.23, blue: 0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 3.2, height: 3.2)
                .opacity(0.92)
                .position(x: cx, y: cy + 5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Brass pivot

    @ViewBuilder
    private func brassPivot(in size: CGSize) -> some View {
        let cx = centerX(size)
        let cy = centerY(size)

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.sunCore,
                            Theme.sunShadow,
                            Color(red: 0.26, green: 0.14, blue: 0.01)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 7
                    )
                )
                .frame(width: 7, height: 7)

            // Tiny cream highlight — light hitting the brass.
            Circle()
                .fill(Theme.sunCore.opacity(0.6))
                .frame(width: 2.4, height: 2.4)
                .offset(x: -1.2, y: -1.2)
        }
        .position(x: cx, y: cy)
        .allowsHitTesting(false)
    }

    // MARK: - Home icon button (lower-left)

    @ViewBuilder
    private func homeIconButton(in size: CGSize) -> some View {
        let pt = arcPoint(
            angleDegrees: iconAngleHome,
            radius: arcRadius(size) * 0.86,
            size: size
        )
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bloom()
            onHomeTap()
        } label: {
            Image(systemName: "sun.max")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .opacity(active == .home ? 1.0 : 0.38)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: pt.x, y: pt.y)
        .accessibilityLabel("Home")
        .accessibilityAddTraits(active == .home ? .isSelected : [])
    }

    // MARK: - Circles icon button (lower-right)

    @ViewBuilder
    private func circlesIconButton(in size: CGSize) -> some View {
        let pt = arcPoint(
            angleDegrees: iconAngleCircles,
            radius: arcRadius(size) * 0.86,
            size: size
        )
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bloom()
            onCirclesTap()
        } label: {
            Image(systemName: "person.2")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .opacity(active == .circles ? 1.0 : 0.38)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: pt.x, y: pt.y)
        .accessibilityLabel("Circles")
        .accessibilityAddTraits(active == .circles ? .isSelected : [])
    }

    // MARK: - Sun capture button (center, always present)

    @ViewBuilder
    private func sunCaptureButton(in size: CGSize) -> some View {
        let cx = centerX(size)
        let cy = centerY(size)
        let isPressed = active == .capture
        let coreSize: CGFloat = isPressed ? 56 : 50
        let haloSize: CGFloat = isPressed ? 120 : 100

        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            bloom()
            onCaptureTap()
        } label: {
            ZStack {
                // Atmospheric bleed — soft warmth around the sun.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.sunOuter.opacity(0.16),
                                Theme.sunShadow.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Halo — the visible glow.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.sunWarm.opacity(isPressed ? 0.78 : 0.6),
                                Theme.sunWarm.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: haloSize / 2
                        )
                    )
                    .frame(width: haloSize, height: haloSize)

                // Core — the solid disc.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.96, blue: 0.84),
                                Theme.sunCore,
                                Theme.sunWarm,
                                Theme.sunOuter
                            ],
                            center: UnitPoint(x: 0.4, y: 0.4),
                            startRadius: 0,
                            endRadius: coreSize / 2
                        )
                    )
                    .frame(width: coreSize, height: coreSize)

                // Upper-left highlight — light direction cue.
                Circle()
                    .fill(Color.white.opacity(0.24))
                    .frame(
                        width: coreSize * 0.32,
                        height: coreSize * 0.32
                    )
                    .offset(
                        x: -coreSize * 0.13,
                        y: -coreSize * 0.13
                    )

                // The "+" itself.
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 160, height: 160)
            // Tap area is restricted to the visible sun, not the full
            // 160 pt halo bleed — otherwise the user accidentally
            // captures when reaching for nearby content.
            .contentShape(Circle().inset(by: 52))
            .scaleEffect(isPressed ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .position(x: cx, y: cy)
        .accessibilityLabel("Capture")
        .accessibilityHint("Add a Task, To-do, or Note")
    }
}

#Preview("Home active") {
    VStack {
        Spacer()
        SundialNavView(
            active: .home,
            onCaptureTap: {},
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}

#Preview("Capture pressed") {
    VStack {
        Spacer()
        SundialNavView(
            active: .capture,
            onCaptureTap: {},
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}

#Preview("Circles active") {
    VStack {
        Spacer()
        SundialNavView(
            active: .circles,
            onCaptureTap: {},
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}

#Preview("Sub-page (hand hidden)") {
    VStack {
        Spacer()
        SundialNavView(
            active: .subPage,
            onCaptureTap: {},
            onHomeTap: {},
            onCirclesTap: {}
        )
    }
    .background(Theme.warmWheat)
}
