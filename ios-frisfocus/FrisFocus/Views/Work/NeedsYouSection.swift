//
//  NeedsYouSection.swift
//  FrisFocus
//
//  The smart "Needs You" triage surface. Renders the single ranked card
//  list (capped, with a "+N more" expander), the witness-model card
//  actions, the calm "all caught up" empty state, and the once-daily
//  Today's Read at the bottom (resting prompt → thinking → the read).
//

import SwiftUI
import UIKit

struct NeedsYouSection: View {
    @Environment(Store.self) private var store
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.openURL) private var openURL
    /// The "ask for a read" concept lesson, fired once when a read first
    /// becomes available.
    @State private var lesson: WalkthroughLesson?

    /// Start a timed focus block on a task (wired to WorkZoneView's flow).
    let onStartFocus: (FFTask) -> Void
    /// Open the quick-add sheet (the read panel's "+" affordance).
    let onQuickAdd: () -> Void

    @State private var expanded: Bool = false

    private static let visibleCap = 3

    var body: some View {
        Group {
            if store.needsYouSectionVisible {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.bottom, 28)
            } else {
                Spacer().frame(height: 28)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.rankedNeedsYou)
        .walkthroughLessonSheet($lesson) { walkthrough.markSeen($0) }
        .onChange(of: store.canShowReadPrompt) { _, can in
            fireReadLessonIfReady(available: can)
        }
        .onAppear { fireReadLessonIfReady(available: store.canShowReadPrompt) }
    }

    /// Fire the read concept the first time a read can actually be asked
    /// for — in context, never upfront.
    private func fireReadLessonIfReady(available: Bool) {
        guard available, lesson == nil, walkthrough.shouldFire(.theRead) else { return }
        lesson = .theRead
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        let ranked = store.rankedNeedsYou
        let read = store.needsYou.read()

        if case .thinking = store.needsYou.phase {
            header(count: ranked.count)
            skeletons
            ThinkingReadPanel()
        } else if case .shown = store.needsYou.phase, let read {
            header(count: ranked.count)
            readState(ranked: ranked, read: read)
        } else if ranked.isEmpty {
            calmEmptyState
        } else {
            header(count: ranked.count)
            restingState(ranked: ranked)
        }
    }

    // MARK: - Header

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            EyebrowText(text: "Needs You", opacity: 0.6)
            if walkthrough.seen.contains(WalkthroughLesson.theRead.id) {
                WalkthroughHelpButton { lesson = .theRead }
            }
            Spacer()
            if count > 0 {
                Text("\(count) thing\(count == 1 ? "" : "s")")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
        }
    }

    // MARK: - Resting state (cards + prompt)

    @ViewBuilder
    private func restingState(ranked: [NeedsYouItem]) -> some View {
        let visible = expanded ? ranked : Array(ranked.prefix(Self.visibleCap))
        VStack(spacing: 10) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                NeedsYouCard(item: item, isLead: index == 0) { action in
                    handle(action, for: item)
                }
            }
            if ranked.count > Self.visibleCap {
                moreToggle(extra: ranked.count - Self.visibleCap)
            }
        }

        if store.canShowReadPrompt {
            RestingReadPrompt {
                Task { await store.generateTodaysRead() }
            }
            .padding(.top, 2)
        }

        if case .failed(let message) = store.needsYou.phase {
            failedNote(message)
        }
    }

    // MARK: - Read state (collapsed cards + read panel)

    @ViewBuilder
    private func readState(ranked: [NeedsYouItem], read: TodaysRead) -> some View {
        VStack(spacing: 10) {
            if expanded {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                    NeedsYouCard(item: item, isLead: index == 0) { action in
                        handle(action, for: item)
                    }
                }
            } else if let lead = ranked.first {
                compactRow(lead)
                if ranked.count > 1 {
                    moreToggle(extra: ranked.count - 1)
                }
            }
        }

        TodaysReadPanelView(
            read: read,
            canThinkAgain: store.canThinkAgain,
            onPrimaryCTA: { handleReadCTA(read.payload, ranked: ranked) },
            onQuickAdd: onQuickAdd,
            onThinkAgain: { Task { await store.generateTodaysRead() } }
        )
        .padding(.top, 2)
    }

    /// One-line collapsed summary of the lead card in the read state.
    private func compactRow(_ item: NeedsYouItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.tint.opacity(0.14))
                Image(systemName: item.glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tint)
            }
            .frame(width: 30, height: 30)

            Text(item.title)
                .font(.sans(13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if !item.compactSignal.isEmpty {
                Text("\u{00B7} \(item.compactSignal)")
                    .font(.sans(11.5, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(item.tint.opacity(0.30), lineWidth: 0.8)
        )
    }

    // MARK: - More / less toggle

    private func moreToggle(extra: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                expanded.toggle()
            }
        } label: {
            Text(expanded ? "Show less" : "+\(extra) more open \u{203A}")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calm empty state

    private var calmEmptyState: some View {
        Text("You\u{2019}re where you need to be today.")
            .font(.serifItalic(14))
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
            .transition(.opacity)
    }

    // MARK: - Skeletons (thinking)

    private var skeletons: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.06))
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.textPrimary.opacity(0.06))
                            .frame(width: 150, height: 11)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.textPrimary.opacity(0.05))
                            .frame(width: 110, height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Failed note

    private func failedNote(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .regular))
            Text(message)
                .font(.sans(11, weight: .regular))
        }
        .foregroundStyle(Theme.textPrimary.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: - Card action handling

    private func handle(_ action: NeedsYouAction, for item: NeedsYouItem) {
        switch action {
        case .startFocus:
            guard let taskId = item.taskId,
                  let task = store.tasks.first(where: { $0.id == taskId }) else { return }
            onStartFocus(task)
        case .log:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                store.needsYouLog(item)
            }
        case .open:
            if let url = store.needsYouOpenURL(item) {
                openURL(url)
            }
        case .notToday:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                store.needsYouNotToday(item)
            }
        case .snoozeTilEvening:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                store.needsYouSnoozeTilEvening(item)
            }
        }
    }

    // MARK: - Read CTA handling

    private func handleReadCTA(_ payload: ReadPayload, ranked: [NeedsYouItem]) {
        switch payload.ctaType {
        case .startFocus, .openTask:
            if let id = payload.ctaTargetId,
               let task = store.tasks.first(where: { $0.id.uuidString == id }) {
                onStartFocus(task)
            } else if let lead = ranked.first(where: { $0.kind == .task }),
                      let taskId = lead.taskId,
                      let task = store.tasks.first(where: { $0.id == taskId }) {
                onStartFocus(task)
            }
        case .openRoutine:
            if let id = payload.ctaTargetId,
               let link = store.cadenceLinks.first(where: { $0.id.uuidString == id }),
               let url = link.runURL {
                openURL(url)
            }
        case .rest:
            // The read said rest — fold the urgency cards away calmly, no
            // penalty. The read panel stays as earned permission.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                for item in ranked { store.needsYouNotToday(item) }
            }
        case .none:
            break
        }
    }
}
