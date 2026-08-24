//
//  HowItMovesSheet.swift
//  FrisFocus
//
//  "How FrisFocus moves" — the quiet rediscovery sheet behind the "?"
//  chip on Home. Every taught-once gesture lives here permanently, plus
//  a replay of the interactive tour. Pull-only: nothing in this sheet
//  fires on its own.
//

import SwiftUI
import UIKit

struct HowItMovesSheet: View {
    @Environment(Store.self) private var store
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.dismiss) private var dismiss

    /// The tour teaches on real cards — it needs a board task or a plan
    /// item to exist. (The pin lesson itself covers the empty-plan case.)
    private var canReplayTour: Bool {
        !store.tasks.isEmpty || !store.todaysPlan.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.textPrimary.opacity(0.12))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(spacing: 4) {
                Text("How FrisFocus moves")
                    .font(.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("The hidden gestures, all in one place.")
                    .font(.serifItalic(13.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    gestureRow(
                        icon: "pin",
                        title: "Pull tasks onto today",
                        line: "Your tasks wait in the season — “Add to today” builds the day's plan."
                    )
                    gestureRow(
                        icon: "checkmark.circle",
                        title: "Tap a task's circle",
                        line: "Checks it off — your sun rises a little."
                    )
                    gestureRow(
                        icon: "hand.draw",
                        title: "Swipe a plan row",
                        line: "Right completes it; left takes it off today."
                    )
                    gestureRow(
                        icon: "calendar",
                        title: "Hold a card → Pin to days…",
                        line: "Sets a rhythm — every day, or the weekdays you choose."
                    )
                    gestureRow(
                        icon: "rectangle.3.group",
                        title: "AGENDA above the plan",
                        line: "Bands, flexible blocks, and day templates for weekdays."
                    )
                    gestureRow(
                        icon: "camera",
                        title: "Swipe in from the left edge",
                        line: "Opens the camera from Home or Friends."
                    )
                    gestureRow(
                        icon: "video",
                        title: "Hold the shutter",
                        line: "Records video — slide up while holding to zoom."
                    )
                    gestureRow(
                        icon: "arrow.up.and.down",
                        title: "Hold the right rail",
                        line: "Scrubs the whole page like a scrollbar."
                    )
                    gestureRow(
                        icon: "arrow.uturn.backward",
                        title: "Shake your phone",
                        line: "Undoes the last plan change."
                    )
                    gestureRow(
                        icon: "chevron.down",
                        title: "Swipe down on a story",
                        line: "Closes the player, wherever you are in it."
                    )
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }

            VStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    // Let the sheet settle before the tour scrim rises.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        let hasQuantity = store.todaysPlan.contains { item in
                            if case .task(let task) = item { return task.requiresQuantityLogging }
                            return false
                        }
                        walkthrough.replayMechanicsTour(
                            startsAtPinning: store.todaysPlan.isEmpty,
                            includesQuantity: hasQuantity
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Replay the guided tour")
                            .font(.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(canReplayTour ? Theme.warmWheat : Theme.warmWheat.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.textPrimary.opacity(canReplayTour ? 1 : 0.35))
                    )
                }
                .buttonStyle(.pressableCard)
                .disabled(!canReplayTour)

                if !canReplayTour {
                    Text("Your season needs at least one task first — the tour teaches on your real cards.")
                        .font(.sans(11.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .presentationBackground(Theme.warmWheat)
    }

    private func gestureRow(icon: String, title: String, line: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Theme.sunWarm.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.sunOuter)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sans(14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(line)
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(line)")
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        HowItMovesSheet()
            .environment(Store())
            .environment(WalkthroughManager())
    }
}
