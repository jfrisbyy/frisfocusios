//
//  ColdStartCoachBanner.swift
//  FrisFocus
//
//  Screen 3's quiet coaching — shown only in the session right after the
//  cold-start board lands on home. Before the first check it nudges the
//  person to begin; the instant they check a task the sun rises (handled
//  by the live SunView) and this line celebrates it: "The sun's rising."
//  Clears itself once the day's board is complete, or on tap.
//

import SwiftUI

struct ColdStartCoachBanner: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if store.coldStartCoaching {
            let progress = store.coldStartProgress
            let started = progress.done > 0

            Button {
                if progress.total > 0 && progress.done >= progress.total {
                    dismiss()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: started ? "sun.max.fill" : "hand.tap.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(started ? Theme.sunOuter : Theme.textCream)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(started ? "The sun's rising." : "Check your first task")
                            .font(.sans(13.5, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                        Text(subtitle(started: started, progress: progress))
                            .font(.sans(11.5, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.8))
                    }

                    Spacer(minLength: 0)

                    if started {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textCream.opacity(0.7))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.92))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.sunWarm.opacity(started ? 0.5 : 0.0), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: started)
            .onChange(of: progress.done) { _, done in
                // Once the whole board is done, retire the coaching gently.
                if progress.total > 0 && done >= progress.total {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { dismiss() }
                }
            }
        }
    }

    private func subtitle(started: Bool, progress: (done: Int, total: Int)) -> String {
        if !started {
            return "Watch the sun rise as your day fills."
        }
        if progress.total > 0 {
            return "\(progress.done) of \(progress.total) today · keep going"
        }
        return "keep going"
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.35)) {
            store.coldStartCoaching = false
        }
    }
}
