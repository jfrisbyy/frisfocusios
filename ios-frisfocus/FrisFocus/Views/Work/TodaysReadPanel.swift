//
//  TodaysReadPanel.swift
//  FrisFocus
//
//  The three states of the once-daily "Today's Read" that lives at the
//  bottom of Needs You:
//    1. RestingReadPrompt   — a quiet dashed "get a read" invitation.
//    2. ThinkingReadPanel   — the sun pulses while the real call runs.
//    3. TodaysReadPanelView — the warm, tone-tinted read + one CTA.
//

import SwiftUI
import UIKit

// MARK: - Sun glyph

/// The small warm sun used across all three read states. Optionally pulses
/// (with a glow ring) while the read is being generated.
private struct ReadSun: View {
    var size: CGFloat = 22
    var pulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate: Bool = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .stroke(Theme.sunOuter.opacity(0.5), lineWidth: 2)
                    .frame(width: size * 1.9, height: size * 1.9)
                    .scaleEffect(animate && !reduceMotion ? 1.25 : 0.85)
                    .opacity(animate && !reduceMotion ? 0 : 0.6)
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunCore, Theme.sunWarm, Theme.sunOuter],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Theme.sunOuter.opacity(0.55), radius: pulsing ? 10 : 4)
                .scaleEffect(pulsing && animate && !reduceMotion ? 1.06 : 1)
        }
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - 1 · Resting prompt

/// Shown only when a read could plausibly help. Its mere presence is a soft
/// signal worth noticing.
struct RestingReadPrompt: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 12) {
                ReadSun(size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feeling scattered?")
                        .font(.sans(13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Get a read on today \u{2192}")
                        .font(.sans(11.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.sunWarm.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.sunOuter.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2 · Thinking

struct ThinkingReadPanel: View {
    var body: some View {
        VStack(spacing: 16) {
            ReadSun(size: 46, pulsing: true)
                .padding(.top, 8)
            Text("Reading your day\u{2026}")
                .font(.serifItalic(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.sunWarm.opacity(0.16), Theme.sunCore.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
}

// MARK: - 3 · The read

struct TodaysReadPanelView: View {
    let read: TodaysRead
    let canThinkAgain: Bool
    let onPrimaryCTA: () -> Void
    let onQuickAdd: () -> Void
    let onThinkAgain: () -> Void

    private var tone: ReadTone { read.payload.tone }

    /// Cooler/softer for rest & calm; warmer for focus & encourage.
    private var panelColors: [Color] {
        switch tone {
        case .rest, .calm:
            return [Theme.duskLight.opacity(0.22), Theme.paperCream.opacity(0.5)]
        case .focus, .encourage:
            return [Theme.sunWarm.opacity(0.22), Theme.sunCore.opacity(0.08)]
        }
    }

    private var borderColor: Color {
        switch tone {
        case .rest, .calm: return Theme.duskMid.opacity(0.35)
        case .focus, .encourage: return Theme.sunOuter.opacity(0.32)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                ReadSun(size: 18)
                Text("TODAY\u{2019}S READ")
                    .font(.sans(10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Text(read.payload.read)
                .font(.serif(15.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if read.payload.ctaType != .none, let label = read.payload.ctaLabel {
                HStack(spacing: 10) {
                    primaryButton(label)
                    if tone == .focus || tone == .encourage {
                        quickAddButton
                    }
                }
            }

            if canThinkAgain {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onThinkAgain()
                } label: {
                    HStack(spacing: 4) {
                        Text("Things changed?")
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        Text("Think again")
                            .foregroundStyle(Theme.alertAmber)
                    }
                    .font(.sans(11.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius + 2, style: .continuous)
                .fill(
                    LinearGradient(colors: panelColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius + 2, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.8)
        )
    }

    // MARK: - Buttons

    private func primaryButton(_ label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPrimaryCTA()
        } label: {
            Text(label)
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(tone == .rest ? Theme.textCream : Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(tone == .rest || tone == .calm ? Theme.duskDeep : Theme.textPrimary)
                )
        }
        .buttonStyle(.plain)
    }

    private var quickAddButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onQuickAdd()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.textPrimary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}
