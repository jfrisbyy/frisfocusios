//
//  SetupBeginView.swift
//  FrisFocus
//
//  Screen 1 of the season setup flow — no input fields. A dawn hero
//  with the orb low on the arc, the warm framing line, the honest
//  expectation-set, and a single "Begin →" that opens straight into
//  the conversation.
//

import SwiftUI
import UIKit

struct SetupBeginView: View {
    let onBegin: () -> Void
    var onResume: () -> Void = {}
    let onClose: () -> Void

    @State private var saved: SetupConversationSnapshot? = SeasonSetupResumeStore.load()
    @State private var confirmFresh: Bool = false

    var body: some View {
        ZStack {
            SetupSky.dawn(lift: 0).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textCream.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)

                Spacer()

                SetupHeroSun(diameter: 92)
                    .padding(.bottom, 36)

                EyebrowText(text: "FrisFocus", opacity: 0.75, color: Theme.textCream)
                    .padding(.bottom, 14)

                Text("Let's set\nyour season.")
                    .font(.serif(36, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textCream)
                    .padding(.bottom, 16)

                Text("We'll just talk for a bit — about who you're trying to become. I'll build the rest from there.")
                    .font(.serifItalic(15, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textCream.opacity(0.78))
                    .padding(.horizontal, 52)

                Spacer()
                Spacer()

                if let saved {
                    resumeCard(saved)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if saved != nil {
                        confirmFresh = true
                    } else {
                        onBegin()
                    }
                } label: {
                    Text(saved == nil ? "Begin →" : "Start fresh instead")
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(saved == nil ? Theme.textCream : Theme.textPrimary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Group {
                                if saved == nil {
                                    Capsule().fill(Theme.textPrimary.opacity(0.92))
                                } else {
                                    Capsule().strokeBorder(Theme.textPrimary.opacity(0.25), lineWidth: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

                Text("about 10–15 minutes · it's worth it")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .padding(.bottom, 18)
            }
        }
        .confirmationDialog(
            "Start fresh?",
            isPresented: $confirmFresh,
            titleVisibility: .visible
        ) {
            Button("Start fresh", role: .destructive) {
                saved = nil
                onBegin()
            }
            Button("Keep my saved conversation", role: .cancel) {}
        } message: {
            Text("This replaces the conversation you saved earlier.")
        }
    }

    /// The calm, secondary "continue where you left off" card.
    private func resumeCard(_ snapshot: SetupConversationSnapshot) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onResume()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 40, height: 40)
                    .background(Theme.sunShadow)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue where you left off")
                        .font(.sans(14.5, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                    Text(snapshot.hint)
                        .font(.serifItalic(12.5, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textCream.opacity(0.5))
            }
            .padding(14)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SetupBeginView(onBegin: {}, onClose: {})
}
