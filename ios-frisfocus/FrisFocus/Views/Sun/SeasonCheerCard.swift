//
//  SeasonCheerCard.swift
//  FrisFocus
//
//  The frosted-glass card that lands inbound cheers on the homepage
//  Sun zone. The three most recent cheers stack vertically — no pager,
//  so a horizontal swipe always means "dismiss this row". Tapping a
//  cheer unfolds a small inline action row beneath it: a few reaction
//  emojis plus a "Cheer back" button. A quiet "all cheers" line at the
//  bottom (with an "and N more" prefix when extras exist) opens the
//  full history page.
//

import SwiftUI
import UIKit

struct SeasonCheerCard: View {
    @Environment(Store.self) private var store
    @Environment(WalkthroughManager.self) private var walkthrough

    let cheers: [Cheer]

    /// The "a cheer is the whole reply" lesson, raised once — the first
    /// time one is actually sitting on the card.
    @State private var lesson: WalkthroughLesson?

    /// At most this many rows render on the home card; the rest live
    /// on the history page behind the "all cheers" line.
    private static let maxVisible = 3

    /// The inline reaction palette — one tap each, mirrored on the
    /// history page so reacting feels the same everywhere.
    static let reactionEmojis: [String] = ["\u{2764}\u{FE0F}", "\u{1F525}", "\u{1F64C}", "\u{1F60A}"]

    /// Per-row horizontal drag offset, keyed by cheer id. Lets us
    /// animate the row out before persisting the dismiss.
    @State private var dragOffsets: [UUID: CGFloat] = [:]
    /// The cheer whose inline action row is currently unfolded.
    @State private var expandedCheerId: UUID?
    /// Cheer-back target — opens the composer addressed to the sender.
    @State private var replyTarget: Friend?
    @State private var showHistory: Bool = false

    private var visible: [Cheer] { Array(cheers.prefix(Self.maxVisible)) }
    private var overflowCount: Int { max(0, cheers.count - Self.maxVisible) }

    var body: some View {
        if visible.isEmpty {
            EmptyView()
        } else {
            card
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .sheet(item: $replyTarget) { friend in
                    CheerComposerView(friend: friend)
                }
                .sheet(isPresented: $showHistory) {
                    CheerHistoryView()
                        .environment(store)
                }
                .walkthroughLessonSheet($lesson) { walkthrough.markSeen($0); walkthrough.release($0) }
                // This branch only renders with a cheer on screen, so
                // appearing IS the first cheer received. A second one
                // landing while the card is up re-runs the check for
                // the session in which teaching was still available.
                .onAppear { maybeFireCheerLesson() }
                .onChange(of: visible.count) { _, _ in maybeFireCheerLesson() }
        }
    }

    /// The brevity of a cheer is the design: there is no comment box
    /// under one, so without a word said an inbound cheer reads as a
    /// message you have somehow failed to answer.
    private func maybeFireCheerLesson() {
        guard lesson == nil, walkthrough.claim(.cheersAreTheReply) else { return }
        lesson = .cheersAreTheReply
    }

    // MARK: - Card

    /// One frosted card holding the stacked rows + the history line.
    /// The cream wash + ultraThinMaterial blur + cream hairline is what
    /// makes it read as part of the sky rather than a feed row.
    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visible) { cheer in
                cheerRow(cheer)
                hairline
            }

            historyLine
                // Overlaid, not appended: the "all cheers" line is
                // centered, and a sibling in the row would shove it off.
                .overlay(alignment: .trailing) {
                    if walkthrough.seen.contains(WalkthroughLesson.cheersAreTheReply.id) {
                        WalkthroughHelpButton(tint: Theme.textCream.opacity(0.55)) {
                            lesson = .cheersAreTheReply
                        }
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.textCream.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.25), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expandedCheerId)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: visible.map(\.id))
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.textCream.opacity(0.18))
            .frame(height: 0.5)
    }

    // MARK: - Row

    private func cheerRow(_ cheer: Cheer) -> some View {
        let offset = dragOffsets[cheer.id] ?? 0
        let isExpanded = expandedCheerId == cheer.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.markCheerRead(cheer.id)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    expandedCheerId = isExpanded ? nil : cheer.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    FriendAvatarView(
                        friend: store.friend(forCheer: cheer),
                        size: 28,
                        fallbackInitials: cheer.fromInitials,
                        fallbackColor: Color(hex: cheer.fromColorHex)
                    )
                    .overlay(
                        Circle().strokeBorder(Theme.textCream.opacity(0.35), lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\u{201C}\(cheer.message)\u{201D}")
                            .font(.serifItalic(14, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(cheer.fromName) cheered you on \u{00B7} tap to react")
                            .font(.sans(10, weight: .regular))
                            .tracking(0.3)
                            .foregroundStyle(Theme.textCream.opacity(0.65))
                    }

                    Spacer(minLength: 0)

                    if let reaction = cheer.reaction {
                        Text(reaction)
                            .font(.system(size: 15))
                            .padding(.top, 2)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else if cheer.readAt == nil {
                        Circle()
                            .fill(Color(hex: 0xED93B1))
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                actionRow(cheer)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .offset(x: offset)
        .opacity(1 - min(abs(offset) / 240, 0.7))
        // Simultaneous so the drag is recognized even though the row's
        // Button claims the touch — a plain `.gesture` here always lost
        // to the tap, which made cheers clickable but never swipeable.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Lock to horizontal: once a drag starts sideways it
                    // drives the swipe; vertical motion stays with the
                    // page scroll and never moves the row.
                    if dragOffsets[cheer.id] == nil {
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    }
                    dragOffsets[cheer.id] = value.translation.width
                }
                .onEnded { value in
                    guard dragOffsets[cheer.id] != nil else { return }
                    let width = value.translation.width
                    if abs(width) > 110 || abs(value.predictedEndTranslation.width) > 260 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffsets[cheer.id] = width > 0 ? 600 : -600
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                store.dismissCheer(cheer.id)
                            }
                            dragOffsets[cheer.id] = nil
                            if expandedCheerId == cheer.id { expandedCheerId = nil }
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            dragOffsets[cheer.id] = 0
                        }
                    }
                }
        )
        .accessibilityLabel("Cheer from \(cheer.fromName): \(cheer.message)")
        .accessibilityHint("Tap to react or cheer back. Swipe to dismiss.")
        .accessibilityAction(named: "Dismiss") {
            store.dismissCheer(cheer.id)
        }
        .accessibilityAction(named: "Send cheer back") {
            if let sender = store.friend(forCheer: cheer) {
                replyTarget = sender
            }
        }
    }

    // MARK: - Inline actions

    /// The little row that unfolds beneath a tapped cheer: reaction
    /// emojis plus "Cheer back". Cream-on-glass like the card itself.
    private func actionRow(_ cheer: Cheer) -> some View {
        HStack(spacing: 8) {
            ForEach(Self.reactionEmojis, id: \.self) { emoji in
                let isChosen = cheer.reaction == emoji
                Button {
                    react(cheer, with: emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 17))
                        .frame(width: 38, height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isChosen ? 0.32 : 0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.textCream.opacity(isChosen ? 0.6 : 0.25), lineWidth: 0.5)
                        )
                        .scaleEffect(isChosen ? 1.12 : 1)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React \(emoji) to \(cheer.fromName)'s cheer")
            }

            Spacer(minLength: 4)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let sender = store.friend(forCheer: cheer) {
                    replyTarget = sender
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hands.clap.fill")
                        .font(.sans(11, weight: .semibold))
                    Text("Cheer back")
                        .font(.sans(12, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.textCream.opacity(0.35), lineWidth: 0.5)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.friend(forCheer: cheer) == nil)
            .accessibilityLabel("Send \(cheer.fromName) a cheer back")
        }
        .padding(.top, 10)
        .padding(.leading, 40)
    }

    /// One tap, a pop, done — the row keeps the chosen emoji and the
    /// action row folds away a beat later.
    private func react(_ cheer: Cheer, with emoji: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            store.reactToCheer(cheer, emoji: emoji)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if expandedCheerId == cheer.id { expandedCheerId = nil }
            }
        }
    }

    // MARK: - History line

    private var historyLine: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showHistory = true
        } label: {
            HStack(spacing: 5) {
                Text(overflowCount > 0 ? "and \(overflowCount) more \u{00B7} all cheers" : "all cheers")
                    .font(.sans(9, weight: .medium))
                    .tracking(1.4)
                    .textCase(.uppercase)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream.opacity(0.6))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(overflowCount > 0
            ? "View all cheers, \(overflowCount) more not shown"
            : "View all cheers")
    }
}

#Preview {
    let store = Store()
    return ZStack {
        LinearGradient(colors: [Color(hex: 0x1A1830), Color(hex: 0x5A4868)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        SeasonCheerCard(cheers: store.activeCheersToday)
            .environment(store)
            .environment(WalkthroughManager())
    }
}
