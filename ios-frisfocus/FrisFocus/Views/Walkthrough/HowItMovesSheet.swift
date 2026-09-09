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

    /// The card whose demo is currently unfolded - one at a time keeps
    /// the sheet readable and only one loop animating.
    @State private var expandedDemo: MoveDemo?

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
                Text("The gestures, and the parts nobody stops to explain.")
                    .font(.serifItalic(13.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    section("YOUR DAY") {
                        gestureRow(
                            icon: "pin",
                            demo: .pinToToday,
                            title: "Pull tasks onto today",
                            line: "Your tasks wait in the season — \u{201C}Add to today\u{201D} builds the day's plan."
                        )
                        gestureRow(
                            icon: "checkmark.circle",
                            demo: .checkOff,
                            title: "Tap a task's circle",
                            line: "Checks it off — your sun rises a little."
                        )
                        gestureRow(
                            icon: "hand.draw",
                            demo: .swipeRow,
                            title: "Swipe a plan row",
                            line: "Right completes it; left takes it off today."
                        )
                        gestureRow(
                            icon: "calendar",
                            demo: .holdToSchedule,
                            title: "Hold a card \u{2192} Pin to days\u{2026}",
                            line: "Sets a rhythm — every day, or the weekdays you choose."
                        )
                        gestureRow(
                            icon: "rectangle.3.group",
                            demo: .agendaBands,
                            title: "AGENDA above the plan",
                            line: "Bands, flexible blocks, and day templates for weekdays."
                        )
                        gestureRow(
                            icon: "sun.max",
                            demo: .sunFills,
                            title: "The sun is your day's shape",
                            line: "It fills toward a strong day — not toward everything you could do."
                        )
                    }

                    // The social half had no reference anywhere. Lessons
                    // teach these one at a time as they become real; this
                    // is where someone looks when they want the whole
                    // picture at once, or arrived before a lesson did.
                    section("YOUR PEOPLE") {
                        gestureRow(
                            icon: "dial.medium",
                            demo: .visibilityDial,
                            title: "You set what each friend sees",
                            line: "Quiet, Open, or Full — per person, and never your numbers."
                        )
                        gestureRow(
                            icon: "circle.dashed",
                            demo: .storyProofCheer,
                            title: "Stories, proofs, and cheers",
                            line: "A story goes to the people you pick; a proof goes to one; a cheer is the whole reply."
                        )
                        gestureRow(
                            icon: "person.3",
                            demo: .circleRoom,
                            title: "Circles are rooms",
                            line: "Everyone in one is doing the work alongside you. Nothing scrolls past."
                        )
                        gestureRow(
                            icon: "sun.horizon",
                            demo: .goldenHour,
                            title: "Golden Hour",
                            line: "A short window, everyone at once. Miss it and the wall stays blurred."
                        )
                        gestureRow(
                            icon: "hands.clap",
                            demo: .pact,
                            title: "Pacts",
                            line: "Two people, one window, both sides visible to each other."
                        )
                        gestureRow(
                            icon: "bell.slash",
                            demo: .muteBlock,
                            title: "Mute, hide, block",
                            line: "Mute quiets someone without them knowing. Block ends it. Both live in the \u{201C}\u{2026}\u{201D} menu."
                        )
                    }

                    section("HIDDEN GESTURES") {
                        gestureRow(
                            icon: "camera",
                            demo: .edgeCamera,
                            title: "Swipe in from the left edge",
                            line: "Opens the camera from Home or Friends."
                        )
                        gestureRow(
                            icon: "video",
                            demo: .holdShutter,
                            title: "Hold the shutter",
                            line: "Records video — slide up while holding to zoom."
                        )
                        gestureRow(
                            icon: "arrow.up.and.down",
                            demo: .railScrub,
                            title: "Hold the right rail",
                            line: "Scrubs the whole page like a scrollbar."
                        )
                        gestureRow(
                            icon: "arrow.uturn.backward",
                            demo: .shakeUndo,
                            title: "Shake your phone",
                            line: "Undoes the last plan change."
                        )
                        gestureRow(
                            icon: "chevron.down",
                            demo: .storyDismiss,
                            title: "Swipe down on a story",
                            line: "Closes the player, wherever you are in it."
                        )
                    }

                    // Real features with no lesson of their own. A line
                    // each is enough to make them findable, which is the
                    // whole job — the alternative was death by coachmark.
                    section("ALSO IN HERE") {
                        gestureRow(
                            icon: "leaf",
                            demo: .focusTree,
                            title: "Focus",
                            line: "A timed block that grows a tree, alone or in a grove with friends."
                        )
                        gestureRow(
                            icon: "flag",
                            demo: .milestoneFlag,
                            title: "Milestones",
                            line: "The wins you named at setup, charted as destinations for the season."
                        )
                        gestureRow(
                            icon: "book.closed",
                            demo: .journal,
                            title: "The journal",
                            line: "Notes, photos and voice memos, in folders and tags. Private, always."
                        )
                        gestureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            demo: .seasonChart,
                            title: "Your season",
                            line: "Weeks and months of your own shape, once there is enough to show."
                        )
                        gestureRow(
                            icon: "bolt",
                            demo: .boosters,
                            title: "Boosters and rhythms",
                            line: "Weekly bonuses and habit trains, set up from a task's own editor."
                        )
                    }
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

    /// One titled group. The sheet used to be a flat list of gestures;
    /// grouping is what lets it also carry the concepts and the long tail
    /// without reading as a wall.
    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: title, opacity: 0.5)
                .padding(.leading, 4)
            content()
        }
    }

    private func gestureRow(icon: String, demo: MoveDemo, title: String, line: String) -> some View {
        let isExpanded = expandedDemo == demo
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                expandedDemo = isExpanded ? nil : demo
            }
        } label: {
            VStack(spacing: 0) {
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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                if isExpanded {
                    MoveDemoStage(demo: demo)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isExpanded ? 0.75 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(line)")
        .accessibilityHint(isExpanded ? "Collapses the demo" : "Plays a short demo of this move")
    }
}

#Preview {
    Color.black.sheet(isPresented: .constant(true)) {
        HowItMovesSheet()
            .environment(Store())
            .environment(WalkthroughManager())
    }
}
