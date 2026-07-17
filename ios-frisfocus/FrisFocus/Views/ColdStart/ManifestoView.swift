//
//  ManifestoView.swift
//  FrisFocus
//
//  The four-card manifesto shown after "Get started" and before the
//  direction pick. An anchor plus three beliefs — one idea per card,
//  serif copy, the visual carrying the meaning. The dawn sun rises a
//  little further with each card. Streak-neutral, reduced-motion safe,
//  line-icons only, no emoji. Demo and sign-in paths bypass this entirely.
//

import SwiftUI

struct ManifestoView: View {
    /// Into the direction pick.
    let onContinue: () -> Void
    /// Skip straight to the pick from any card.
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int = 0

    private let cardCount = 4

    var body: some View {
        ZStack {
            DawnBackdrop(progress: skyProgress)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: page)

            TabView(selection: $page) {
                AnchorCard().tag(0)
                BeliefCard(
                    icon: "bell.slash",
                    heading: "\u{201C}This isn't a habit tracker.\u{201D}",
                    bodyText: "It's an honest record of your life. A witness, not a taskmaster — it will never nag you, shame you, or beg you to come back. It just shows you, truthfully, what you're building.",
                    visual: { AnyView(NagPillsVisual()) }
                ).tag(1)
                BeliefCard(
                    icon: "sun.max",
                    heading: "\u{201C}Your life isn't a checklist.\u{201D}",
                    bodyText: "Everything you do counts differently — priced by what it costs you. Big efforts lift your sun higher. On the hardest days, the small ones keep it above the horizon.",
                    visual: { AnyView(GhostLiftVisual()) }
                ).tag(2)
                BeliefCard(
                    icon: "sunrise",
                    heading: "\u{201C}No two good days look alike.\u{201D}",
                    bodyText: "You decide what matters — and any combination of it can make a productive day. Nobody does the same things every single day, and you shouldn't have to. What counts is that you keep moving in your direction, season by season.",
                    visual: { AnyView(VariedSunsVisual()) }
                ).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: page)

            VStack {
                topBar
                Spacer()
                bottomControls
            }
        }
    }

    // MARK: Sky

    /// 0 at the anchor → ~0.32 by the last card, so the dawn arc that runs
    /// through the whole cold start begins here.
    private var skyProgress: Double {
        Double(page) / Double(max(1, cardCount - 1)) * 0.32
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSkip()
            } label: {
                Text("Skip")
                    .font(.sans(14.5, weight: .semibold))
                    .foregroundStyle(Theme.textCream.opacity(0.82))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 20) {
            PageDots(count: cardCount, index: page)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if page >= cardCount - 1 {
                    onContinue()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { page += 1 }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(page >= cardCount - 1 ? "Make it yours" : "Next")
                        .font(.sans(17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.textCream)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }
}

// MARK: - Page dots

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.textCream : Theme.textCream.opacity(0.3))
                    .frame(width: i == index ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
            }
        }
    }
}

// MARK: - Card 0 · the anchor

private struct AnchorCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lines = [
        "for the builders.",
        "for the students.",
        "for the believers.",
        "for the athletes.",
        "for the artists.",
        "for the parents.",
        "for the average joe."
    ]
    private let hold = "for you."

    @State private var lineIndex: Int = 0
    @State private var settled: Bool = false

    /// The currently displayed rotating line, or the held final line.
    private var displayed: String {
        settled ? hold : lines[min(lineIndex, lines.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("FrisFocus")
                .font(.serif(46, weight: .semibold))
                .foregroundStyle(Theme.textCream)

            Text(displayed)
                .font(.serifItalic(23, weight: .regular))
                .foregroundStyle(settled ? Theme.sunCore : Theme.textCream.opacity(0.9))
                .id(displayed)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                .padding(.top, 14)
                .animation(.easeInOut(duration: 0.32), value: displayed)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .contentShape(Rectangle())
        .onTapGesture { settleNow() }
        .onAppear { startRotation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FrisFocus. For you.")
    }

    private func startRotation() {
        if reduceMotion {
            settled = true
            return
        }
        rotate()
    }

    private func rotate() {
        guard !settled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard !settled else { return }
            if lineIndex >= lines.count - 1 {
                withAnimation { settled = true }
            } else {
                withAnimation { lineIndex += 1 }
                rotate()
            }
        }
    }

    private func settleNow() {
        guard !settled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { settled = true }
    }
}

// MARK: - Belief card scaffold

private struct BeliefCard: View {
    let icon: String
    let heading: String
    let bodyText: String
    let visual: () -> AnyView

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            visual()
                .frame(height: 210)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 20)

            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.8))

                Text(heading)
                    .font(.serif(29, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bodyText)
                    .font(.serifItalic(16.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card 1 visual · nag pills dissolving

private struct NagPillsVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dissolved: Bool = false

    private let nags = [
        "You haven't logged today!",
        "You're falling behind!",
        "Don't lose your progress!"
    ]

    var body: some View {
        ZStack {
            // The nags fade out.
            VStack(spacing: 12) {
                ForEach(Array(nags.enumerated()), id: \.offset) { idx, nag in
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 12, weight: .regular))
                        Text(nag)
                            .font(.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.72))
                    )
                    .rotationEffect(.degrees(dissolved ? Double(idx - 1) * 6 : 0))
                    .offset(y: dissolved ? -18 : 0)
                    .blur(radius: dissolved ? 6 : 0)
                    .opacity(dissolved ? 0 : 1)
                }
            }

            // The calm horizon + low sun fade in.
            HorizonSun(lift: 0.16)
                .opacity(dissolved ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                dissolved = true
            } else {
                withAnimation(.easeInOut(duration: 1.1).delay(0.5)) { dissolved = true }
            }
        }
    }
}

// MARK: - Card 2 visual · checkboxes → three sun-lifts (interactive)

private struct GhostLiftVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var melted: Bool = false
    @State private var tapped: Bool = false

    var body: some View {
        VStack(spacing: 22) {
            // The three differently-sized lifts the checkboxes become.
            HStack(alignment: .bottom, spacing: 34) {
                HorizonSun(lift: 0.12).frame(width: 74, height: 74)
                    .opacity(melted ? 1 : 0)
                HorizonSun(lift: tapped ? 0.62 : 0.34).frame(width: 74, height: 74)
                    .opacity(melted ? 1 : 0)
                HorizonSun(lift: 0.9).frame(width: 74, height: 74)
                    .opacity(melted ? 1 : 0)
            }
            .overlay {
                // The melting checkboxes sit on top and fade as they melt.
                if !melted {
                    HStack(spacing: 34) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "checkmark.square")
                                .font(.system(size: 34, weight: .regular))
                                .foregroundStyle(Theme.textCream.opacity(0.7))
                        }
                    }
                }
            }

            // The one ghost-task the user taps themselves.
            Button {
                guard !tapped else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) {
                    tapped = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: tapped ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(tapped ? Theme.sunCore : Theme.textCream.opacity(0.6))
                    Text(tapped ? "That lifted your sun" : "Tap to try one")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream.opacity(0.9))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Color.white.opacity(0.14))
                )
                .overlay(
                    Capsule().strokeBorder(Theme.textCream.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 260)
            .opacity(melted ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                melted = true
            } else {
                withAnimation(.easeInOut(duration: 0.8).delay(0.4)) { melted = true }
            }
        }
    }
}

// MARK: - Card 3 visual · a row of unalike suns

private struct VariedSunsVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    private let lifts: [Double] = [0.55, 0.9, 0.08, 0.72, 0.4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(Array(lifts.enumerated()), id: \.offset) { idx, lift in
                HorizonSun(lift: lift)
                    .frame(width: 54, height: 78)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(idx) * 0.08),
                        value: shown
                    )
            }
        }
        .onAppear { shown = true }
    }
}

// MARK: - Shared little sun over a hairline horizon

/// A small sun sitting at `lift` (0 = on the horizon, 1 = high) above a
/// hairline. Even the lowest sun still glows. No numbers, no text.
private struct HorizonSun: View {
    /// 0…1 height above the horizon.
    var lift: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let horizonY = h * 0.82
            let sunY = horizonY - CGFloat(max(0, min(1, lift))) * (h * 0.66)
            let r = w * 0.28

            ZStack {
                // Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.sunCore.opacity(0.9), Theme.sunWarm.opacity(0.2), .clear],
                            center: .center, startRadius: 1, endRadius: r * 2.1
                        )
                    )
                    .frame(width: r * 4, height: r * 4)
                    .position(x: w / 2, y: sunY)
                    .blur(radius: 3)

                // Sun disc
                Circle()
                    .fill(Theme.sunCore)
                    .frame(width: r * 1.6, height: r * 1.6)
                    .position(x: w / 2, y: sunY)

                // Hairline horizon
                Rectangle()
                    .fill(Theme.textCream.opacity(0.45))
                    .frame(height: 1)
                    .position(x: w / 2, y: horizonY)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ManifestoView(onContinue: {}, onSkip: {})
}
