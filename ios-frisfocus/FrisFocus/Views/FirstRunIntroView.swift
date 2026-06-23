//
//  FirstRunIntroView.swift
//  FrisFocus
//
//  The first-launch welcome. A short, swipeable story that introduces
//  the app's rhythm, then a confident final screen with two choices:
//  start a clean personal season, or explore the fully-seeded sample
//  sandbox. Shown only while the Store sits in `.uninitialized`.
//

import SwiftUI

struct FirstRunIntroView: View {
    /// Begin a clean, empty personal journey → guided season setup.
    let onStartClean: () -> Void
    /// Load the fully-lived-in sample sandbox.
    let onStartDemo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int = 0
    @State private var appeared: Bool = false

    private static let pages: [IntroPage] = [
        IntroPage(
            symbol: "sun.max.fill",
            tint: Theme.sunOuter,
            eyebrow: "WELCOME TO FRISFOCUS",
            title: "Live by seasons,\nnot to-do lists.",
            body: "A season is a chapter of your life with a purpose — a few weeks pointed at what matters most right now."
        ),
        IntroPage(
            symbol: "checklist",
            tint: Theme.categoryWork,
            eyebrow: "EACH DAY",
            title: "A plan that\nscores your day.",
            body: "Pin the habits and tasks that count. Earn points as you go, and watch the day fill with light from sunrise to dusk."
        ),
        IntroPage(
            symbol: "circle.hexagongrid.fill",
            tint: Theme.categorySpiritual,
            eyebrow: "TOGETHER",
            title: "Circles of\nfriends who show up.",
            body: "Share your rhythm with people you trust. Cheer each other on, keep small pacts, and never grind alone."
        )
    ]

    private var isLastPage: Bool { page == Self.pages.count }

    var body: some View {
        ZStack {
            backdrop

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, item in
                    IntroPageView(page: item)
                        .tag(index)
                        .padding(.horizontal, 32)
                }

                IntroChoiceView(onStartClean: onStartClean, onStartDemo: onStartDemo)
                    .tag(Self.pages.count)
                    .padding(.horizontal, 28)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                Spacer()
                footer
                    .padding(.bottom, 44)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { appeared = true }
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.warmWheat, Theme.paperCream],
                startPoint: .top,
                endPoint: .bottom
            )

            // A soft sun glow that drifts with the page, anchoring the
            // sundial motif behind every panel.
            RadialGradient(
                colors: [Theme.sunCore.opacity(0.55), Theme.sunWarm.opacity(0.0)],
                center: .center,
                startRadius: 8,
                endRadius: 320
            )
            .frame(width: 520, height: 520)
            .offset(y: -180 + CGFloat(page) * 18)
            .blur(radius: 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: page)
        }
        .ignoresSafeArea()
    }

    // MARK: Footer (dots + skip)

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0...Self.pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.textPrimary : Theme.textPrimary.opacity(0.18))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: page)
                }
            }

            if !isLastPage {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.4)) {
                        page = Self.pages.count
                    }
                } label: {
                    Text("Skip")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            } else {
                // Keep the footer height stable on the choice screen.
                Color.clear.frame(height: 18)
            }
        }
    }
}

// MARK: - Page model

private struct IntroPage {
    let symbol: String
    let tint: Color
    let eyebrow: String
    let title: String
    let body: String
}

// MARK: - Single story page

private struct IntroPageView: View {
    let page: IntroPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.14))
                    .frame(width: 116, height: 116)
                Image(systemName: page.symbol)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(page.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(shown ? 1 : 0.8)
            .opacity(shown ? 1 : 0)
            .padding(.bottom, 34)

            EyebrowText(text: page.eyebrow, opacity: 0.5)
                .padding(.bottom, 14)

            Text(page.title)
                .font(.serif(34, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            Text(page.body)
                .font(.serifItalic(17, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            shown = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) {
                shown = true
            }
        }
    }
}

// MARK: - Final choice screen

private struct IntroChoiceView: View {
    let onStartClean: () -> Void
    let onStartDemo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            EyebrowText(text: "READY WHEN YOU ARE", opacity: 0.5)
                .padding(.bottom, 14)

            Text("How do you\nwant to begin?")
                .font(.serif(34, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Text("Start your own season now, or wander a fully lived-in demo first to see how it all feels.")
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 30)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStartClean()
            } label: {
                primaryLabel
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onStartDemo()
            } label: {
                secondaryLabel
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 16)
        .onAppear {
            shown = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shown = true }
        }
    }

    private var primaryLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.and.horizon.fill")
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Start my season")
                    .font(.sans(17, weight: .semibold))
                Text("A clean slate, built around you")
                    .font(.sans(12.5, weight: .regular))
                    .opacity(0.7)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .opacity(0.7)
        }
        .foregroundStyle(Theme.textCream)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.textPrimary)
        )
        .shadow(color: Theme.textPrimary.opacity(0.22), radius: 14, y: 6)
    }

    private var secondaryLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 16, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("Explore a demo first")
                    .font(.sans(16, weight: .semibold))
                Text("A sample life you can leave anytime")
                    .font(.sans(12.5, weight: .regular))
                    .opacity(0.7)
            }
            Spacer()
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    FirstRunIntroView(onStartClean: {}, onStartDemo: {})
}
