//
//  TaskTalkSheet.swift
//  FrisFocus
//
//  The scoped "talk it through" — a two-minute conversation about ONE
//  slipping task or milestone, in place of the full season conversation
//  the home used to route neglect into. The coach opens by naming what
//  it sees, proposes concrete moves as tappable chips, and applying one
//  changes the real item right here — reschedule, shrink, reprice,
//  pause, drop; push a date or add a step for a milestone.
//
//  Nothing applies without a tap. Closing mid-thought costs nothing.
//

import SwiftUI
import UIKit

/// What the conversation is about.
enum TaskTalkSubject: Identifiable, Equatable {
    case task(UUID)
    case milestone(UUID)

    var id: String {
        switch self {
        case .task(let id): return "task-\(id.uuidString)"
        case .milestone(let id): return "milestone-\(id.uuidString)"
        }
    }
}

struct TaskTalkSheet: View {
    let subject: TaskTalkSubject

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// One transcript line. Applied confirmations render as quiet
    /// system lines, not as things the person "said".
    private struct Bubble: Identifiable {
        enum Role { case coach, me, applied }
        let id = UUID()
        let role: Role
        let text: String
    }

    @State private var bubbles: [Bubble] = []
    @State private var history: [AIMessage] = []
    @State private var proposals: [TaskTuneProposal] = []
    @State private var appliedIds: Set<String> = []
    @State private var isThinking: Bool = false
    @State private var errorText: String?
    @State private var input: String = ""
    @State private var conversationDone: Bool = false
    @FocusState private var inputFocused: Bool

    private var subjectName: String {
        switch subject {
        case .task(let id):
            return store.tasks.first(where: { $0.id == id })?.title ?? "This task"
        case .milestone(let id):
            return store.currentSeason.milestones.first(where: { $0.id == id })?.title ?? "This milestone"
        }
    }

    /// The item still exists — a drop proposal can remove it mid-chat,
    /// after which the sheet should wind down rather than error.
    private var subjectExists: Bool {
        switch subject {
        case .task(let id): return store.tasks.contains { $0.id == id }
        case .milestone(let id): return store.currentSeason.milestones.contains { $0.id == id }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                header

                                ForEach(bubbles) { bubble in
                                    bubbleView(bubble)
                                }

                                if isThinking {
                                    thinkingRow
                                }

                                if !proposals.isEmpty, !isThinking {
                                    proposalChips
                                }

                                if let errorText {
                                    Text(errorText)
                                        .font(.sans(12.5, weight: .regular))
                                        .foregroundStyle(Theme.alertRed)
                                        .padding(.horizontal, 4)
                                }

                                Color.clear.frame(height: 1).id("tail")
                            }
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                        }
                        .onChange(of: bubbles.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("tail", anchor: .bottom)
                            }
                        }
                        .onChange(of: isThinking) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("tail", anchor: .bottom)
                            }
                        }
                    }

                    if !conversationDone, subjectExists {
                        inputBar
                    } else {
                        closingBar
                    }
                }
            }
            .navigationTitle("Talk it through")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
        .task { await openConversation() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ABOUT ONE THING")
                .font(.sans(9.5, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text(subjectName)
                .font(.serif(21, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Adjust it, shrink it, pause it, or let it go — your season stays as it is.")
                .font(.serifItalic(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func bubbleView(_ bubble: Bubble) -> some View {
        switch bubble.role {
        case .coach:
            Text(bubble.text)
                .font(.sans(14.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 34)
        case .me:
            Text(bubble.text)
                .font(.sans(14.5, weight: .regular))
                .foregroundStyle(Theme.textCream)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.9))
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 34)
        case .applied:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.alertGreen)
                Text(bubble.text)
                    .font(.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Theme.textPrimary.opacity(0.5))
            Text("thinking…")
                .font(.serifItalic(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .padding(.horizontal, 4)
    }

    private var proposalChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(proposals) { proposal in
                let applied = appliedIds.contains(proposal.id)
                Button {
                    apply(proposal)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: applied ? "checkmark.circle.fill" : iconName(for: proposal.change))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(applied ? Theme.alertGreen : Theme.sunOuter)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(proposal.label)
                                .font(.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if !proposal.detail.isEmpty {
                                Text(proposal.detail)
                                    .font(.sans(12, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(applied ? Theme.alertGreen.opacity(0.08) : Theme.sunWarm.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                applied ? Theme.alertGreen.opacity(0.35) : Theme.sunWarm.opacity(0.4),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(applied || isThinking)
            }
        }
    }

    private func iconName(for change: TaskTuneChange) -> String {
        switch change {
        case .reschedule: return "calendar"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .reprice: return "number"
        case .pause: return "moon.zzz"
        case .drop: return "xmark.circle"
        case .pushDate: return "calendar.badge.clock"
        case .addStep: return "plus.circle"
        case .unsupported: return "questionmark"
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Say what's actually in the way…", text: $input, axis: .vertical)
                .font(.sans(14.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3)
                .focused($inputFocused)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                )
            Button {
                sendCurrentInput()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.textPrimary))
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking ? 0.4 : 1)
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.vertical, 10)
        .background(Theme.warmWheat)
    }

    private var closingBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Text(subjectExists ? "Done here" : "All settled")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Theme.textPrimary)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Conversation

    private var currentItem: TaskTuneItem? {
        switch subject {
        case .task(let id): return store.tuneItem(forTaskId: id)
        case .milestone(let id): return store.tuneItem(forMilestoneId: id)
        }
    }

    private func openConversation() async {
        guard bubbles.isEmpty, let item = currentItem else { return }
        await exchange(item: item, sending: nil)
    }

    private func sendCurrentInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let item = currentItem else { return }
        input = ""
        Task { await exchange(item: item, sending: text) }
    }

    /// One round trip: optionally append the person's words, call the
    /// coach, land the reply + fresh proposals.
    private func exchange(item: TaskTuneItem, sending text: String?) async {
        if let text {
            bubbles.append(Bubble(role: .me, text: text))
            history.append(.user(text))
        }
        isThinking = true
        errorText = nil
        defer { isThinking = false }
        do {
            let reply = try await TaskTuneAI.send(item: item, history: history)
            history.append(.assistant(reply.raw))
            bubbles.append(Bubble(role: .coach, text: reply.message))
            proposals = reply.actionable
            appliedIds.removeAll()
            if reply.done { conversationDone = true }
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// The tap that actually changes something. Applies through the
    /// Store, drops a confirmation line, and lets the coach acknowledge.
    private func apply(_ proposal: TaskTuneProposal) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let confirmation: String?
        switch subject {
        case .task(let id):
            confirmation = store.applyTune(proposal.change, toTaskId: id)
        case .milestone(let id):
            confirmation = store.applyTune(proposal.change, toMilestoneId: id)
        }

        guard let confirmation else {
            errorText = "That change couldn't be applied."
            return
        }

        appliedIds.insert(proposal.id)
        bubbles.append(Bubble(role: .applied, text: confirmation))
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // A drop ends the item — wind down without another model call.
        if case .drop = proposal.change {
            conversationDone = true
            proposals = []
            return
        }

        // Let the coach see what was chosen so its next words match
        // reality. Refresh the item snapshot — it just changed.
        history.append(.user("(I applied: \(proposal.label). \(confirmation))"))
        if let refreshed = currentItem {
            Task { await exchange(item: refreshed, sending: nil) }
        }
    }
}
