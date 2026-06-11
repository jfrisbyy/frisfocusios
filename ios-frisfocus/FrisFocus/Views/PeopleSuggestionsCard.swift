//
//  PeopleSuggestionsCard.swift
//  FrisFocus
//
//  The reusable "People you may know" card — a compact strip of
//  suggested real accounts (friends-of-friends first, then newest
//  members) with one-tap Add buttons that flip to Pending in place.
//  Dropped into every surface a zero-friend user would otherwise hit a
//  dead end: the Friends story page, the signal zone, circle creation,
//  and more. Self-contained: it owns its own graph + discover services
//  so hosts only choose a palette and a row budget.
//
//  Renders nothing while signed out or when there is genuinely no one
//  to suggest, so hosts can embed it unconditionally.
//

import SwiftUI
import UIKit

struct PeopleSuggestionsCard: View {
    /// Visual family: warm parchment for the cream pages, dusk for the
    /// signal zone's dark gradient.
    enum Palette {
        case parchment
        case dusk
    }

    var palette: Palette = .parchment
    /// How many suggestion rows to show inline.
    var maxCount: Int = 4
    var title: String = "PEOPLE YOU MAY KNOW"
    /// Whether the header offers the full Discover screen.
    var showsSeeMore: Bool = true

    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync

    /// The app-wide friend graph — shared so relationship state here
    /// matches the Friends page, banners, and dots in real time.
    @Environment(FriendGraphService.self) private var graph
    @State private var discover = DiscoverService()
    @State private var preview: DiscoverSuggestion?
    @State private var showAllPeople = false
    @State private var appeared = false

    private var myId: String? { auth.user?.id }

    /// Suggestions worth showing here: blocked accounts hidden, people
    /// who became friends (or sent us a request) dropped — freshly
    /// added rows stay visible as Pending.
    private var visibleSuggestions: [DiscoverSuggestion] {
        guard let myId else { return [] }
        return discover.suggestions.filter { suggestion in
            guard !moderation.isBlocked(suggestion.profile.id) else { return false }
            switch graph.relationship(to: suggestion.profile.id, myUserId: myId) {
            case .none, .requestSent: return true
            case .friends, .requestReceived, .isMe: return false
            }
        }
    }

    // MARK: - Palette

    private var primaryText: Color {
        palette == .dusk ? Theme.textCream : Theme.textPrimary
    }

    private var secondaryText: Color {
        palette == .dusk ? Theme.textCream.opacity(0.6) : Theme.textSecondary
    }

    private var containerFill: Color {
        palette == .dusk ? Theme.textCream.opacity(0.06) : Theme.textPrimary.opacity(0.04)
    }

    private var rowFill: Color {
        palette == .dusk ? Theme.textCream.opacity(0.08) : Theme.paperCream
    }

    private var pillFill: Color {
        palette == .dusk ? Theme.textCream : Theme.textPrimary
    }

    private var pillText: Color {
        palette == .dusk ? Theme.duskDeep : Theme.textCream
    }

    // MARK: - Body

    var body: some View {
        Group {
            if myId != nil, !visibleSuggestions.isEmpty {
                card
            }
        }
        .task {
            guard let myId else { return }
            if !discover.hasLoaded {
                if graph.friends.isEmpty && graph.incoming.isEmpty && graph.outgoing.isEmpty {
                    await graph.load(myUserId: myId)
                }
                await discover.refresh(myUserId: myId, graph: graph)
            }
            withAnimation { appeared = true }
        }
        .sheet(item: $preview) { suggestion in
            DiscoverProfileSheet(suggestion: suggestion, graph: graph)
        }
        .sheet(isPresented: $showAllPeople) {
            NavigationStack {
                DiscoverPeopleView(graph: graph, discover: discover)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showAllPeople = false }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: 8) {
                ForEach(Array(visibleSuggestions.prefix(maxCount).enumerated()), id: \.element.id) { index, suggestion in
                    row(suggestion)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 7)
                        .animation(
                            .easeOut(duration: 0.35).delay(Double(index) * 0.07),
                            value: appeared
                        )
                }
            }
        }
        .padding(12)
        .background(containerFill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sans(10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(primaryText.opacity(0.55))

            Spacer()

            if showsSeeMore {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAllPeople = true
                } label: {
                    HStack(spacing: 3) {
                        Text("See more")
                            .font(.sans(12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(primaryText.opacity(0.6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See more people")
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Row

    private func row(_ suggestion: DiscoverSuggestion) -> some View {
        let profile = suggestion.profile
        let relationship = myId.map { graph.relationship(to: profile.id, myUserId: $0) } ?? FriendRelationship.none

        return HStack(spacing: 11) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                preview = suggestion
            } label: {
                HStack(spacing: 11) {
                    avatar(profile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.sans(14, weight: .medium))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                        if let secondary = secondaryLine(for: suggestion) {
                            Text(secondary)
                                .font(.sans(11, weight: .regular))
                                .foregroundStyle(secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(profile.displayName)'s profile")

            trailing(for: suggestion, relationship: relationship)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: relationship)
        }
        .padding(10)
        .background(rowFill)
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func secondaryLine(for suggestion: DiscoverSuggestion) -> String? {
        var parts: [String] = []
        let profile = suggestion.profile
        if let handle = profile.handle ?? profile.email, handle != profile.displayName {
            parts.append(handle)
        }
        if suggestion.mutualCount > 0 {
            parts.append("\(suggestion.mutualCount) mutual")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(for suggestion: DiscoverSuggestion, relationship: FriendRelationship) -> some View {
        switch relationship {
        case .none:
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                add(suggestion)
            } label: {
                pill("Add", filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(suggestion.profile.displayName)")
        case .requestSent:
            pill("Pending", filled: false)
                .opacity(0.6)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        case .friends, .requestReceived, .isMe:
            EmptyView()
        }
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.sans(12, weight: .semibold))
            .foregroundStyle(filled ? pillText : primaryText)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(filled ? pillFill : rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(primaryText.opacity(filled ? 0 : 0.18), lineWidth: 1)
            )
    }

    private func avatar(_ profile: RemoteProfile) -> some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc(profile)
                }
            } else {
                initialsDisc(profile)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(Circle().stroke(primaryText.opacity(0.08), lineWidth: 1))
    }

    private func initialsDisc(_ profile: RemoteProfile) -> some View {
        ZStack {
            profile.signatureColor
            Text(profile.initials)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    // MARK: - Actions

    private func add(_ suggestion: DiscoverSuggestion) {
        guard let myId else { return }
        Task {
            await graph.sendRequest(to: suggestion.profile, myUserId: myId)
            socialSync.pokeEngine(trigger: "friend")
        }
    }
}

#Preview {
    ScrollView {
        PeopleSuggestionsCard()
            .padding(20)
    }
    .background(Theme.warmWheat)
    .environment(AuthManager())
    .environment(ModerationService())
    .environment(SocialSyncService())
}
