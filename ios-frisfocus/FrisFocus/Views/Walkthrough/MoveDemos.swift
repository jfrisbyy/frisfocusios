//
//  MoveDemos.swift
//  FrisFocus
//
//  The looping mini-demos behind every "How FrisFocus moves" card. Tap
//  a card and it unfolds a small stage where the gesture performs
//  itself — a ghost finger swipes the mock row, the circle checks, the
//  sun ticks up — on repeat, self-contained, nothing navigating away.
//
//  Everything draws as a pure function of a looping phase 0…1 from
//  `TimelineView(.animation)`: no state machines to desync, and Reduce
//  Motion simply pins the phase to the scene's resolved end-frame.
//

import SwiftUI

// MARK: - Demo catalogue

/// Every card's demo, one case per taught move or concept.
enum MoveDemo: String, CaseIterable, Identifiable {
    case pinToToday, checkOff, swipeRow, holdToSchedule, agendaBands, sunFills
    case visibilityDial, storyProofCheer, circleRoom, goldenHour, pact, muteBlock
    case edgeCamera, holdShutter, railScrub, shakeUndo, storyDismiss
    case focusTree, milestoneFlag, journal, seasonChart, boosters

    var id: String { rawValue }

    /// Seconds per loop — enough to read, short enough to invite a rewatch.
    var loopSeconds: Double {
        switch self {
        case .swipeRow, .storyProofCheer: return 4.2
        default: return 3.0
        }
    }
}

// MARK: - Stage

/// The little theatre a card unfolds into.
struct MoveDemoStage: View {
    let demo: MoveDemo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                scene(t: 0.85)
            } else {
                TimelineView(.animation) { context in
                    let raw = context.date.timeIntervalSinceReferenceDate
                    let t = (raw.truncatingRemainder(dividingBy: demo.loopSeconds)) / demo.loopSeconds
                    scene(t: t)
                }
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.warmWheat.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.07), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scene(t: Double) -> some View {
        switch demo {
        case .pinToToday:     PinToTodayScene(t: t)
        case .checkOff:       CheckOffScene(t: t)
        case .swipeRow:       SwipeRowScene(t: t)
        case .holdToSchedule: HoldToScheduleScene(t: t)
        case .agendaBands:    AgendaBandsScene(t: t)
        case .sunFills:       SunFillsScene(t: t)
        case .visibilityDial: VisibilityDialScene(t: t)
        case .storyProofCheer: StoryProofCheerScene(t: t)
        case .circleRoom:     CircleRoomScene(t: t)
        case .goldenHour:     GoldenHourScene(t: t)
        case .pact:           PactScene(t: t)
        case .muteBlock:      MuteBlockScene(t: t)
        case .edgeCamera:     EdgeCameraScene(t: t)
        case .holdShutter:    HoldShutterScene(t: t)
        case .railScrub:      RailScrubScene(t: t)
        case .shakeUndo:      ShakeUndoScene(t: t)
        case .storyDismiss:   StoryDismissScene(t: t)
        case .focusTree:      FocusTreeScene(t: t)
        case .milestoneFlag:  MilestoneFlagScene(t: t)
        case .journal:        JournalScene(t: t)
        case .seasonChart:    SeasonChartScene(t: t)
        case .boosters:       BoostersScene(t: t)
        }
    }
}

// MARK: - Timing helpers

/// Progress of `t` through the window [a, b], clamped 0…1 and eased.
private func seg(_ t: Double, _ a: Double, _ b: Double) -> Double {
    guard b > a else { return t >= b ? 1 : 0 }
    let x = min(1, max(0, (t - a) / (b - a)))
    // Smoothstep — every movement in these demos wants soft ends.
    return x * x * (3 - 2 * x)
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat {
    a + (b - a) * CGFloat(x)
}

// MARK: - Shared props

/// The ghost finger that performs each gesture.
private struct GhostFinger: View {
    var pressed: Bool = false

    var body: some View {
        Circle()
            .fill(Theme.textPrimary.opacity(pressed ? 0.34 : 0.22))
            .frame(width: pressed ? 22 : 26, height: pressed ? 22 : 26)
            .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }
}

/// A stand-in plan row — circle, title bar, value chip.
private struct MockRow: View {
    var checked: Bool = false
    var checkProgress: Double = 0
    var width: CGFloat = 190

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                Circle()
                    .fill(Theme.alertGreen)
                    .scaleEffect(checked ? 1 : CGFloat(checkProgress))
                    .opacity(checked ? 1 : checkProgress)
                if checked || checkProgress > 0.6 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textCream)
                }
            }
            .frame(width: 20, height: 20)

            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.textPrimary.opacity(0.25))
                .frame(width: width * 0.45, height: 7)

            Spacer(minLength: 0)

            Text("+3")
                .font(.sans(10, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// Small labeled pill used for buttons/menus inside demos.
private struct MockChip: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.sans(9.5, weight: .semibold))
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? Theme.textPrimary : Theme.textPrimary.opacity(0.08))
            )
    }
}

// MARK: - Your day

private struct PinToTodayScene: View {
    let t: Double

    var body: some View {
        let press = seg(t, 0.15, 0.3)
        let hop = seg(t, 0.35, 0.7)
        ZStack {
            VStack(spacing: 8) {
                HStack {
                    Text("SEASON").font(.sans(8, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    Spacer()
                    Text("TODAY").font(.sans(8, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.textPrimary.opacity(hop > 0.9 ? 0.8 : 0.4))
                }
                .frame(width: 216)
                HStack(spacing: 0) {
                    MockRow(width: 128)
                        .overlay(alignment: .bottomTrailing) {
                            MockChip(text: "Add to today", filled: press > 0.5)
                                .offset(x: 8, y: 12)
                        }
                        .offset(x: lerp(0, 92, hop), y: lerp(0, 8, hop))
                        .scaleEffect(lerp(1, 0.92, hop))
                    Spacer()
                }
                .frame(width: 216)
            }
            GhostFinger(pressed: press > 0.4 && hop < 0.2)
                .offset(x: lerp(18, 66, hop), y: lerp(22, 26, hop))
                .opacity(seg(t, 0.05, 0.15) - seg(t, 0.75, 0.9))
        }
    }
}

private struct CheckOffScene: View {
    let t: Double

    var body: some View {
        let press = seg(t, 0.25, 0.4)
        let sunRise = seg(t, 0.45, 0.8)
        ZStack {
            MockRow(checkProgress: press)
                .offset(y: 10)
            // The sun answering the check.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunWarm, Theme.sunWarm.opacity(0.0)],
                        center: .center, startRadius: 2, endRadius: 22
                    )
                )
                .frame(width: 40, height: 40)
                .offset(x: 88, y: lerp(-8, -26, sunRise))
                .opacity(0.4 + 0.6 * sunRise)
            GhostFinger(pressed: press > 0.5 && press < 1)
                .offset(x: -85, y: 10)
                .opacity(seg(t, 0.1, 0.25) - seg(t, 0.6, 0.75))
        }
    }
}

private struct SwipeRowScene: View {
    let t: Double

    var body: some View {
        // First half: swipe right completes. Second half: swipe left removes.
        let right = seg(t, 0.1, 0.32)
        let settle = seg(t, 0.32, 0.42)
        let left = seg(t, 0.55, 0.8)
        let x = lerp(0, 46, right) * (1 - settle) + lerp(0, -70, left)
        ZStack {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                    .foregroundStyle(Theme.alertGreen)
                    .opacity(right * (1 - left))
                Spacer()
                Image(systemName: "minus.circle").font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .opacity(left)
            }
            .frame(width: 200)
            MockRow(checked: settle > 0.6 && left < 0.1)
                .offset(x: x)
                .opacity(1 - 0.85 * seg(t, 0.78, 0.9))
            GhostFinger(pressed: (right > 0 && right < 1) || (left > 0 && left < 1))
                .offset(x: x + 20, y: 16)
                .opacity(seg(t, 0.02, 0.1) - seg(t, 0.82, 0.95))
        }
    }
}

private struct HoldToScheduleScene: View {
    let t: Double

    var body: some View {
        let hold = seg(t, 0.1, 0.35)
        let menu = seg(t, 0.38, 0.5)
        let days = seg(t, 0.55, 0.9)
        ZStack {
            MockRow()
                .scaleEffect(1 + 0.03 * hold * (1 - menu))
                .offset(y: -12)
            MockChip(text: "Pin to days…", filled: true)
                .offset(y: 12)
                .opacity(menu)
            HStack(spacing: 5) {
                ForEach(0..<5) { i in
                    let lit = days > Double(i + 1) / 6.0
                    Circle()
                        .fill(lit ? Theme.sunWarm : Theme.textPrimary.opacity(0.12))
                        .frame(width: 8, height: 8)
                }
            }
            .offset(y: 32)
            .opacity(menu)
            GhostFinger(pressed: hold > 0.2 && menu < 0.6)
                .offset(x: 40, y: -12)
                .opacity(seg(t, 0.02, 0.1) - seg(t, 0.75, 0.9))
        }
    }
}

private struct AgendaBandsScene: View {
    let t: Double

    var body: some View {
        let reveal = seg(t, 0.15, 0.75)
        VStack(spacing: 5) {
            ForEach(0..<3) { i in
                let bandIn = seg(reveal, Double(i) * 0.3, Double(i) * 0.3 + 0.35)
                HStack(spacing: 7) {
                    Text(["MORNING", "AFTERNOON", "EVENING"][i])
                        .font(.sans(7.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .frame(width: 62, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.sunWarm.opacity(0.18 + 0.1 * Double(i % 2)))
                        .frame(width: lerp(0, 110, bandIn), height: 16)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.textPrimary.opacity(0.25))
                                .frame(width: 40 * bandIn, height: 5)
                                .padding(.leading, 6)
                        }
                    Spacer(minLength: 0)
                }
                .frame(width: 216)
                .opacity(0.25 + 0.75 * bandIn)
            }
        }
    }
}

private struct SunFillsScene: View {
    let t: Double

    var body: some View {
        let fill = seg(t, 0.1, 0.8)
        ZStack {
            // Horizon line
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.15))
                .frame(width: 190, height: 1)
                .offset(y: 22)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunWarm, Theme.sunShadow.opacity(0.7)],
                        center: .init(x: 0.38, y: 0.34), startRadius: 2, endRadius: 20
                    )
                )
                .frame(width: 34, height: 34)
                .offset(y: lerp(20, -14, fill))
                .shadow(color: Theme.sunWarm.opacity(0.5 * fill), radius: 10)
            Text("a strong day, not everything")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .offset(y: 34)
        }
    }
}

// MARK: - Your people

private struct VisibilityDialScene: View {
    let t: Double

    var body: some View {
        let sweep = seg(t, 0.15, 0.85)
        let idx = sweep < 0.34 ? 0 : (sweep < 0.67 ? 1 : 2)
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    MockChip(text: ["Quiet", "Open", "Full"][i], filled: i == idx)
                }
            }
            Text("per person — never your numbers")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}

private struct StoryProofCheerScene: View {
    let t: Double

    var body: some View {
        let step = seg(t, 0.05, 0.9)
        let idx = step < 0.34 ? 0 : (step < 0.67 ? 1 : 2)
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    HStack(spacing: 4) {
                        Image(systemName: ["circle.dashed", "camera", "hands.clap"][i])
                            .font(.system(size: 10, weight: .medium))
                        Text(["Story", "Proof", "Cheer"][i])
                            .font(.sans(9.5, weight: .semibold))
                    }
                    .foregroundStyle(i == idx ? Theme.textCream : Theme.textPrimary.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(i == idx ? Theme.textPrimary : Theme.textPrimary.opacity(0.07)))
                }
            }
            Text(["to the people you pick", "to one person", "the whole reply"][idx])
                .font(.serifItalic(10.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .contentTransition(.opacity)
        }
    }
}

private struct CircleRoomScene: View {
    let t: Double

    var body: some View {
        HStack(spacing: -6) {
            ForEach(0..<4) { i in
                let pulse = 0.5 + 0.5 * sin((t * 2 * .pi) + Double(i) * 1.4)
                Circle()
                    .fill(Theme.textPrimary.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(Theme.sunWarm, lineWidth: 1.5)
                            .opacity(0.35 + 0.65 * pulse)
                    )
                    .overlay(
                        Text(["A", "J", "M", "R"][i])
                            .font(.sans(10, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                    )
                    .scaleEffect(1 + 0.05 * pulse)
                    .zIndex(Double(4 - i))
            }
        }
        .overlay(alignment: .bottom) {
            Text("everyone doing the work, together")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .fixedSize()
                .offset(y: 24)
        }
    }
}

private struct GoldenHourScene: View {
    let t: Double

    var body: some View {
        let clear = seg(t, 0.35, 0.75)
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.sunWarm.opacity(0.35))
                        .frame(width: 40, height: 30)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        )
                        .blur(radius: lerp(5, 0, seg(clear, Double(i) * 0.25, Double(i) * 0.25 + 0.5)))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            Text(clear > 0.5 ? "you posted — the wall opens" : "post yours to see theirs")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
    }
}

private struct PactScene: View {
    let t: Double

    var body: some View {
        let mine = seg(t, 0.1, 0.45)
        let theirs = seg(t, 0.45, 0.85)
        VStack(spacing: 8) {
            ForEach(0..<2) { i in
                let p = i == 0 ? mine : theirs
                HStack(spacing: 8) {
                    Text(i == 0 ? "You" : "Sam")
                        .font(.sans(9.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(width: 30, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.textPrimary.opacity(0.08))
                        .frame(width: 120, height: 9)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.alertGreen.opacity(0.8))
                                .frame(width: 120 * p)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.alertGreen)
                        .opacity(p >= 1 ? 1 : 0)
                }
            }
            Text("both sides visible to each other")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}

private struct MuteBlockScene: View {
    let t: Double

    var body: some View {
        let open = seg(t, 0.15, 0.35)
        let pick = seg(t, 0.5, 0.65)
        ZStack {
            HStack {
                Circle().fill(Theme.textPrimary.opacity(0.7)).frame(width: 22, height: 22)
                RoundedRectangle(cornerRadius: 3).fill(Theme.textPrimary.opacity(0.2))
                    .frame(width: 70, height: 6)
                Spacer()
                Text("…").font(.sans(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .frame(width: 190, height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.85)))
            .offset(y: -18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mute").font(.sans(10, weight: pick > 0.5 ? .bold : .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(pick > 0.5 ? 0.95 : 0.7))
                Text("Hide their stories").font(.sans(10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Text("Block").font(.sans(10, weight: .medium))
                    .foregroundStyle(Theme.alertRed.opacity(0.8))
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
            .offset(x: 52, y: 18)
            .opacity(open)
            .scaleEffect(0.8 + 0.2 * open, anchor: .topTrailing)
        }
    }
}

// MARK: - Hidden gestures

private struct EdgeCameraScene: View {
    let t: Double

    var body: some View {
        let drag = seg(t, 0.15, 0.6)
        ZStack {
            // Camera layer beneath
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.textPrimary.opacity(0.85))
                .frame(width: 150, height: 64)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textCream.opacity(0.9))
                )
            // Page sliding away
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.paperCream)
                .overlay(
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.textPrimary.opacity(0.2)).frame(width: 70, height: 5)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.textPrimary.opacity(0.12)).frame(width: 100, height: 5)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.textPrimary.opacity(0.12)).frame(width: 84, height: 5)
                    }
                    .padding(.leading, 12), alignment: .leading
                )
                .frame(width: 150, height: 64)
                .offset(x: lerp(0, 120, drag))
                .shadow(color: .black.opacity(0.18 * drag), radius: 8)
            GhostFinger(pressed: drag > 0 && drag < 1)
                .offset(x: lerp(-70, 40, drag), y: 0)
                .opacity(seg(t, 0.05, 0.15) - seg(t, 0.65, 0.8))
        }
    }
}

private struct HoldShutterScene: View {
    let t: Double

    var body: some View {
        let hold = seg(t, 0.15, 0.8)
        let zoomSlide = seg(t, 0.45, 0.75)
        ZStack {
            Circle()
                .strokeBorder(Theme.textCream, lineWidth: 3)
                .background(Circle().fill(Color.white.opacity(0.25)))
                .frame(width: 40, height: 40)
            Circle()
                .trim(from: 0, to: hold)
                .stroke(Theme.alertRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 46, height: 46)
            Text("REC")
                .font(.sans(8, weight: .bold)).tracking(1)
                .foregroundStyle(Theme.alertRed)
                .opacity(hold > 0.05 ? 0.5 + 0.5 * sin(t * 6 * .pi) : 0)
                .offset(y: -34)
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .offset(x: 56, y: lerp(6, -18, zoomSlide))
                .opacity(zoomSlide > 0 ? 1 : 0)
            GhostFinger(pressed: hold > 0 && hold < 1)
                .offset(x: 0, y: lerp(2, -20, zoomSlide))
        }
        .frame(width: 200, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.textPrimary.opacity(0.8))
        )
    }
}

private struct RailScrubScene: View {
    let t: Double

    var body: some View {
        let scrub = seg(t, 0.15, 0.85)
        // Finger goes down the rail; content flies up.
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                let widths: [CGFloat] = [70, 110, 90, 120, 80, 100, 60, 115]
                ForEach(0..<8) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.textPrimary.opacity(0.14))
                        .frame(width: widths[i], height: 5)
                }
            }
            .frame(height: 70)
            .offset(y: lerp(24, -24, scrub))
            .frame(width: 130, height: 66, alignment: .top)
            .clipped()

            VStack(spacing: 7) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(Theme.textPrimary.opacity(abs(scrub * 3 - Double(i)) < 0.6 ? 0.7 : 0.2))
                        .frame(width: 14, height: 3)
                }
            }
            .overlay(
                GhostFinger(pressed: scrub > 0 && scrub < 1)
                    .offset(x: 4, y: lerp(-24, 24, scrub))
            )
        }
    }
}

private struct ShakeUndoScene: View {
    let t: Double

    var body: some View {
        let wiggle = sin(seg(t, 0.1, 0.4) * .pi * 5) * (1 - seg(t, 0.35, 0.45))
        let pill = seg(t, 0.5, 0.65)
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.textPrimary.opacity(0.5), lineWidth: 2)
                .frame(width: 38, height: 66)
                .rotationEffect(.degrees(wiggle * 9))
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .semibold))
                Text("Undone — removed from today").font(.sans(9.5, weight: .medium))
            }
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.92)))
            .offset(y: lerp(46, 30, pill))
            .opacity(pill)
        }
        .offset(y: -8)
    }
}

private struct StoryDismissScene: View {
    let t: Double

    var body: some View {
        let drop = seg(t, 0.3, 0.7)
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(colors: [Theme.sunShadow.opacity(0.85), Theme.textPrimary.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 52, height: 80)
                .overlay(alignment: .top) {
                    Capsule().fill(Theme.textCream.opacity(0.8))
                        .frame(width: 30, height: 2.5).padding(.top, 5)
                }
                .offset(y: lerp(0, 60, drop))
                .opacity(1 - 0.7 * drop)
                .scaleEffect(1 - 0.15 * drop)
            GhostFinger(pressed: drop > 0 && drop < 1)
                .offset(y: lerp(-14, 34, drop))
                .opacity(seg(t, 0.15, 0.3) - seg(t, 0.72, 0.85))
        }
    }
}

// MARK: - Also in here

private struct FocusTreeScene: View {
    let t: Double

    var body: some View {
        let grow = seg(t, 0.1, 0.8)
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // Trunk
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.sunShadow.opacity(0.8))
                    .frame(width: 4, height: lerp(4, 26, grow))
                // Canopy
                Circle()
                    .fill(Theme.alertGreen.opacity(0.75))
                    .frame(width: lerp(4, 30, seg(grow, 0.4, 1)), height: lerp(4, 30, seg(grow, 0.4, 1)))
                    .offset(y: lerp(0, -20, seg(grow, 0.4, 1)))
            }
            .frame(height: 48, alignment: .bottom)
            Text("25:00 → 0:00")
                .font(.sans(9.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}

private struct MilestoneFlagScene: View {
    let t: Double

    var body: some View {
        let walk = seg(t, 0.1, 0.75)
        let plant = seg(t, 0.78, 0.9)
        ZStack(alignment: .leading) {
            // Path
            Capsule().fill(Theme.textPrimary.opacity(0.12)).frame(width: 170, height: 4)
            Capsule().fill(Theme.sunWarm).frame(width: 170 * walk, height: 4)
            // Steps
            ForEach(0..<3) { i in
                Circle()
                    .fill(walk > Double(i + 1) * 0.25 ? Theme.sunWarm : Theme.textPrimary.opacity(0.2))
                    .frame(width: 9, height: 9)
                    .offset(x: CGFloat(30 + i * 45) - 4)
            }
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(walk > 0.98 ? Theme.alertGreen : Theme.textPrimary.opacity(0.4))
                .scaleEffect(1 + 0.4 * plant * (1 - plant) * 4)
                .offset(x: 165, y: -12)
        }
        .frame(width: 178)
    }
}

private struct JournalScene: View {
    let t: Double

    var body: some View {
        let write = seg(t, 0.1, 0.85)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed").font(.system(size: 10))
                Text("Private, always").font(.sans(9, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.45))
            let widths: [CGFloat] = [120, 150, 90]
            ForEach(0..<3) { i in
                let lineIn = seg(write, Double(i) * 0.3, Double(i) * 0.3 + 0.4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.textPrimary.opacity(0.25))
                    .frame(width: lerp(0, widths[i], lineIn), height: 5)
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.85)))
    }
}

private struct SeasonChartScene: View {
    let t: Double

    var body: some View {
        let draw = seg(t, 0.1, 0.85)
        ZStack {
            ChartLine()
                .trim(from: 0, to: draw)
                .stroke(Theme.sunWarm, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 170, height: 54)
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.15))
                .frame(width: 178, height: 1)
                .offset(y: 28)
        }
    }

    private struct ChartLine: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            // Unit-space samples, scaled in a plain loop — the one-liner
            // literal-plus-map version sent the type-checker past its
            // time budget.
            let xs: [CGFloat] = [0, 0.18, 0.34, 0.52, 0.7, 0.86, 1.0]
            let ys: [CGFloat] = [0.9, 0.65, 0.75, 0.4, 0.5, 0.2, 0.28]
            var pts: [CGPoint] = []
            for i in xs.indices {
                pts.append(CGPoint(x: xs[i] * rect.width, y: ys[i] * rect.height))
            }
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            return p
        }
    }
}

private struct BoostersScene: View {
    let t: Double

    var body: some View {
        let light = seg(t, 0.1, 0.8)
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<5) { i in
                    let on = light > Double(i + 1) / 6.0
                    Circle()
                        .fill(on ? Theme.sunWarm : Theme.textPrimary.opacity(0.12))
                        .frame(width: 11, height: 11)
                        .scaleEffect(on ? 1 : 0.8)
                }
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(light > 0.95 ? Theme.sunWarm : Theme.textPrimary.opacity(0.25))
                    .padding(.leading, 3)
            }
            Text("3 gym days → the bonus lands")
                .font(.serifItalic(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}
