//
//  PactClosingView.swift
//  FrisFocus
//
//  The closing of a pact. A pact is the one thing in this app with a
//  hard end date, and until now it simply stopped: the window ran out,
//  the row went quiet, and nothing ever said it was over or what the
//  two of you had done. A commitment that never resolves teaches people
//  that commitments here don't mean anything.
//
//  Deliberately not a scoreboard. The model has no winner field and
//  neither does this: two counts, side by side, in the order "you" then
//  "them" because that is the order of the pact header everywhere else
//  — never sorted by who did more. The closing line adapts to what
//  actually happened, and the honest cases are allowed to be honest.
//  A pact where both people fell off says so; pretending otherwise is
//  how a celebration screen becomes something people dismiss unread.
//

import SwiftUI
import UIKit

struct PactClosingView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let pact: Pact

    private var partner: Friend? { store.partnerFriend(forPact: pact) }
    private var summary: (mine: Int, theirs: Int, window: Int) {
        store.pactClosingSummary(pact)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Text("THE WINDOW CLOSED")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))

            Text(pact.title)
                .font(.serif(26, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            Text(windowLine)
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .padding(.top, 4)

            pairBlock
                .padding(.top, 30)

            Text(closingLine)
                .font(.serifItalic(16, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
                .padding(.top, 28)

            Spacer(minLength: 20)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Close")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule(style: .continuous).fill(Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.warmWheat)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // Acknowledgement lives in the presenter, on dismissal — a
        // closing swiped away has still been seen, and doing it in one
        // place means the ordering of onDisappear against onDismiss can
        // never re-raise the closing that was just read.
    }

    // MARK: - Pieces

    /// Two counts, equal weight, no comparison drawn between them.
    private var pairBlock: some View {
        let s = summary
        return HStack(alignment: .top, spacing: 0) {
            countColumn(
                avatar: AnyView(
                    Circle()
                        .fill(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text("You")
                                .font(.sans(11, weight: .semibold))
                                .foregroundStyle(Theme.textCream)
                        )
                ),
                name: "You",
                days: s.mine,
                window: s.window
            )

            Rectangle()
                .fill(Theme.textPrimary.opacity(0.12))
                .frame(width: 1, height: 74)

            countColumn(
                avatar: AnyView(FriendAvatarView(friend: partner, size: 44)),
                name: partner?.displayName ?? "Them",
                days: s.theirs,
                window: s.window
            )
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
    }

    private func countColumn(avatar: AnyView, name: String, days: Int, window: Int) -> some View {
        VStack(spacing: 8) {
            avatar
            Text(name)
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .lineLimit(1)
            Text("\(days)")
                .font(.serif(30, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(days == 1 ? "day kept" : "days kept")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(days) of \(window) days kept")
    }

    private var windowLine: String {
        let days = pact.durationDays
        return days == 1 ? "One day, together." : "\(days) days, together."
    }

    /// What to say about how it went. Every branch is true of the two
    /// numbers above it — no branch congratulates a pact nobody kept.
    private var closingLine: String {
        let s = summary
        let name = partner?.displayName ?? "They"
        let both = min(s.mine, s.theirs)

        if s.mine == 0 && s.theirs == 0 {
            return "Neither of you got to this one. That happens — the window was the wrong shape, or the week was. Worth proposing again with a smaller ask."
        }
        if s.mine == 0 {
            return "\(name) kept \(s.theirs) \(s.theirs == 1 ? "day" : "days") of this. You didn't get to it — which is worth knowing, and worth saying to them."
        }
        if s.theirs == 0 {
            return "You kept \(s.mine) \(s.mine == 1 ? "day" : "days") of this on your own. That still counts. \(name) may have had a week."
        }
        if both >= s.window {
            return "Every day, both of you. That is the whole idea of a pact, and it is rarer than it sounds."
        }
        if s.mine == s.theirs {
            return "\(s.mine) \(s.mine == 1 ? "day" : "days") each — the same number, without either of you seeing the other's. That's the part worth noticing."
        }
        return "You showed up \(s.mine) \(s.mine == 1 ? "day" : "days"), \(name) \(s.theirs). Neither of you did it alone."
    }
}
