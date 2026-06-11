//
//  SignalZoneView.swift
//  FrisFocus
//
//  Zone 4 — dusk gradient background. The social feed peek, built from
//  the real synced graph: friends' live story posts lead, with a calm
//  empty state before anyone has shared today.
//

import SwiftUI
import UIKit

struct SignalZoneView: View {
    @Environment(Store.self) private var store

    /// Find-friends doorway — a sheet straight into the Friends hub,
    /// reachable from the no-friend quiet card and the footer line.
    @State private var showFindFriends: Bool = false

    /// Up to three of the freshest friend stories, shaped into the
    /// card model this zone has always rendered.
    private var entries: [CircleEntry] {
        store.activeFriendStories
            .filter { $0.authorId != store.currentUserId }
            .prefix(3)
            .compactMap { post -> CircleEntry? in
                guard let friend = store.friend(by: post.authorId) else { return nil }
                return CircleEntry(
                    initial: friend.initials,
                    avatarColor: Color(hex: friend.accentColorHex),
                    name: friend.displayName,
                    dayScore: store.likes(for: post.id).count,
                    season: relativeTime(post.createdAt),
                    hasFlame: !store.viewedStoryPostIds.contains(post.id),
                    status: post.caption ?? "shared a moment"
                )
            }
    }

    private var sublineText: String {
        let authors = Set(store.activeFriendStories.map { $0.authorId }).subtracting([store.currentUserId])
        switch authors.count {
        case 0: return "your friends' moments land here"
        case 1: return "one of yours showed up today"
        default: return "\(spelled(authors.count)) of yours showed up today"
        }
    }

    private func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return n < words.count ? words[n] : "\(n)"
    }

    private func relativeTime(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 60 { return "\(max(1, minutes))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.duskLight, location: 0.0),
                    .init(color: Theme.duskMid, location: 0.6),
                    .init(color: Theme.duskDeep, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 20) {
                ZoneHeaderView(
                    title: "The signal",
                    eyebrowRight: "Zone 4 of 4",
                    subline: sublineText,
                    textColor: Theme.textCream,
                    dim: 0.65
                )
                .padding(.top, 28)

                if entries.isEmpty {
                    quietCard
                } else {
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            CircleEntryCardView(entry: entry)
                        }
                    }
                }

                EncouragementChipView()
                    .padding(.top, 2)

                // Footer row
                HStack {
                    if store.friends.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showFindFriends = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Add friends to light this zone up")
                                    .font(.sans(11, weight: .medium))
                                    .underline()
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(Theme.textCream.opacity(0.85))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add friends")
                    } else {
                        Text("\(store.friends.count) friend\(store.friends.count == 1 ? "" : "s") connected")
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.75))
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("open Circles")
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Theme.textCream)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textCream)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
        }
        .sheet(isPresented: $showFindFriends) {
            NavigationStack {
                FriendsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFindFriends = false }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
    }

    /// The empty-feed card. With friends it stays the calm one-liner;
    /// with zero friends it becomes actionable — suggested real people
    /// to add right here, plus the find-friends doorway.
    private var quietCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.friends.isEmpty ? "No one out there yet." : "Quiet out there for now.")
                    .font(.serifItalic(15))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                Text(store.friends.isEmpty
                     ? "Add a friend or two and their moments will light this zone up."
                     : "When friends post a moment, it shows up here.")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.6))
            }

            if store.friends.isEmpty {
                PeopleSuggestionsCard(palette: .dusk, maxCount: 3, showsSeeMore: false)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showFindFriends = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "person.badge.plus")
                            .font(.sans(12, weight: .semibold))
                        Text("Find friends")
                            .font(.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.duskDeep)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .continuous).fill(Theme.textCream))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Find friends")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.textCream.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    SignalZoneView()
        .environment(Store())
}
