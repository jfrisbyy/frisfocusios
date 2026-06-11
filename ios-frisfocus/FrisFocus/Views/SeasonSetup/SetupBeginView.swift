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
    let onClose: () -> Void

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

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onBegin()
                } label: {
                    Text("Begin →")
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.textPrimary.opacity(0.92))
                        .clipShape(Capsule())
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
    }
}

#Preview {
    SetupBeginView(onBegin: {}, onClose: {})
}
