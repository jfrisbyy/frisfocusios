//
//  CheerHistoryView.swift
//  FrisFocus
//
//  Every cheer that ever found you, newest first, grouped by day.
//  Opens as a sheet from the home cheer card's "all cheers" line and
//  from a row on your own profile page. A Received / Sent toggle flips
//  between the cheers that landed on you (with the same inline react /
//  cheer-back actions as the home card) and the ones you sent, where
//  friends' reactions show up.
//
//  The Store only mirrors a rolling ~30-day window; older pages are
//  fetched on scroll via `SocialSyncService.fetchCheerHistory` and
//  held locally by this view, so the ledger reaches all the way back.
//

import SwiftUI
import UIKit

struct CheerHistoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Filter: String, CaseIterable {
        case received = "Received"
        case sent = "Sent"
    }

    @State private var filter: Filter = .received
    /// Pages fetched past the Store's synced window, both directions.
    @State private var olderCheers: [Cheer] = []
    @State private var isLoadingOlder: Bool = false
    @State private var reachedEnd: Bool = false
    @State private var expandedCheerId: UUID?
    @State private var replyTarget: Friend?

    private static let pageSize = 60

    // MARK: - Data

    private var windowCheers: [Cheer] {
        filter == .received ? store.receivedCheers : store.sentCheers
    }

    /// Synced window + paged tail, deduped, filtered to the active
    /// direction, newest first.
    private var allCheers: [Cheer] {
        let windowIds = Set(windowCheers.map(\.id))
        let mine = store.currentUserId
        let tail = olderCheers.filter { cheer in
            !windowIds.contains(cheer.id) &&
            (filter == .received ? cheer.toUserId == mine : cheer.fromFriendId == mine)
        }
        return (windowCheers + tail).sorted { $0.sentAt > $1.sentAt }
    }

    private var daySections: [(day: Date, items: [Cheer])] {
        let grouped = Dictionary(grouping: allCheers) {
            Calendar.current.startOfDay(for: $0.sentAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, (grouped[day] ?? []).sorted { $0.sentAt > $1.sentAt })
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                filterToggle
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.bottom, 4)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if allCheers.isEmpty && !isLoadingOlder {
                            emptyState
                                .padding(.top, 60)
                        } else {
                            ForEach(daySections, id: \.day) { section in
                                dayHeader(section.day)
                                    .padding(.top, 10)
                                ForEach(section.items) { cheer in
                                    row(cheer)
                                        .onAppear {
                                            if cheer.id == allCheers.last?.id {
                                                Task { await loadOlder() }
                                            }
                                        }
                                }
                            }
                        }

                        if isLoadingOlder {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Theme.textPrimary.opacity(0.5))
                                Spacer()
                            }
                            .padding(.vertical, 18)
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 44)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sheet(item: $replyTarget) { friend in
            CheerComposerView(friend: friend)
                .environment(store)
        }
        .task { await loadOlder() }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expandedCheerId)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CHEERS")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text(filter == .received ? "Every word that found you" : "Every word you sent")
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var filterToggle: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases, id: \.self) { option in
                let isActive = filter == option
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        filter = option
                        expandedCheerId = nil
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.textCream : Theme.textPrimary.opacity(0.65))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? Theme.textPrimary : Color.clear)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.rawValue) cheers")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.textPrimary.opacity(0.05))
        )
    }

    private func dayHeader(_ day: Date) -> some View {
        Text(dayLabel(day))
            .font(.sans(10, weight: .medium))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        return day.formatted(
            sameYear
                ? Date.FormatStyle().month(.wide).day()
                : Date.FormatStyle().month(.wide).day().year()
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hands.clap")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            Text(filter == .received
                 ? "No cheers yet \u{2014} they\u{2019}ll gather here as friends send them."
                 : "You haven\u{2019}t sent a cheer yet. A single kind word goes a long way.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ cheer: Cheer) -> some View {
        if filter == .received {
            receivedRow(cheer)
        } else {
            sentRow(cheer)
        }
    }

    private func receivedRow(_ cheer: Cheer) -> some View {
        let isExpanded = expandedCheerId == cheer.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.markCheerRead(cheer.id)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    expandedCheerId = isExpanded ? nil : cheer.id
                }
            } label: {
                rowContent(
                    friend: store.friend(forCheer: cheer),
                    avatarColor: Color(hex: cheer.fromColorHex),
                    initials: cheer.fromInitials,
                    message: cheer.message,
                    attribution: "\(cheer.fromName) \u{00B7} \(cheer.sentAt.formatted(date: .omitted, time: .shortened))",
                    reaction: cheer.reaction
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                actionRow(cheer)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityLabel("Cheer from \(cheer.fromName): \(cheer.message)")
        .accessibilityHint("Tap to react or cheer back")
    }

    private func sentRow(_ cheer: Cheer) -> some View {
        let recipient = store.friend(by: cheer.toUserId)
        let name = recipient?.displayName ?? "a friend"
        let color = recipient.map { Color(hex: $0.accentColorHex) } ?? Theme.textTertiary
        let initials = recipient?.initials ?? "?"
        return rowContent(
            friend: recipient,
            avatarColor: color,
            initials: initials,
            message: cheer.message,
            attribution: "to \(name) \u{00B7} \(cheer.sentAt.formatted(date: .omitted, time: .shortened))",
            reaction: cheer.reaction
        )
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityLabel(
            cheer.reaction.map { "You cheered \(name): \(cheer.message). They reacted \($0)." }
                ?? "You cheered \(name): \(cheer.message)"
        )
    }

    private func rowContent(
        friend: Friend?,
        avatarColor: Color,
        initials: String,
        message: String,
        attribution: String,
        reaction: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FriendAvatarView(
                friend: friend,
                size: 34,
                fallbackInitials: initials,
                fallbackColor: avatarColor
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("\u{201C}\(message)\u{201D}")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text(attribution)
                    .font(.sans(11, weight: .regular))
                    .tracking(0.2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Spacer(minLength: 0)

            if let reaction {
                Text(reaction)
                    .font(.system(size: 16))
                    .padding(.top, 2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }

    /// Same inline palette as the home card, restyled for the wheat
    /// page: reaction emojis + "Cheer back".
    private func actionRow(_ cheer: Cheer) -> some View {
        HStack(spacing: 8) {
            ForEach(SeasonCheerCard.reactionEmojis, id: \.self) { emoji in
                let isChosen = cheer.reaction == emoji
                Button {
                    react(cheer, with: emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 17))
                        .frame(width: 38, height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.textPrimary.opacity(isChosen ? 0.12 : 0.05))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(isChosen ? 0.4 : 0.1), lineWidth: 0.5)
                        )
                        .scaleEffect(isChosen ? 1.12 : 1)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React \(emoji)")
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
                        .fill(Theme.textPrimary)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.friend(forCheer: cheer) == nil)
            .accessibilityLabel("Send a cheer back")
        }
        .padding(.top, 10)
        .padding(.leading, 46)
    }

    private func react(_ cheer: Cheer, with emoji: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let updated: Cheer = withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            store.reactToCheer(cheer, emoji: emoji)
        }
        // Paged rows live outside the Store window — refresh in place.
        if let idx = olderCheers.firstIndex(where: { $0.id == cheer.id }) {
            olderCheers[idx] = updated
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if expandedCheerId == cheer.id { expandedCheerId = nil }
            }
        }
    }

    // MARK: - Paging

    /// Everything loaded so far, both directions — the next page
    /// starts strictly before the oldest of these.
    private var oldestLoaded: Date? {
        (store.cheers + olderCheers).map(\.sentAt).min()
    }

    private func loadOlder() async {
        guard !isLoadingOlder, !reachedEnd, let social = store.social else { return }
        isLoadingOlder = true
        let before = oldestLoaded ?? Date()
        let page = await social.fetchCheerHistory(before: before, limit: Self.pageSize)
        isLoadingOlder = false
        if page.isEmpty {
            reachedEnd = true
            return
        }
        let known = Set((store.cheers + olderCheers).map(\.id))
        olderCheers.append(contentsOf: page.filter { !known.contains($0.id) })
        if page.count < Self.pageSize { reachedEnd = true }
    }
}

#Preview {
    let store = Store()
    return Color.black.opacity(0.2)
        .sheet(isPresented: .constant(true)) {
            CheerHistoryView()
                .environment(store)
        }
}
