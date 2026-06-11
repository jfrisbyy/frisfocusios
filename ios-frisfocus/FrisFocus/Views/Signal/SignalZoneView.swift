//
//  SignalZoneView.swift
//  FrisFocus
//
//  Zone 4 — dusk gradient background. The social feed peek, built from
//  the real synced graph: friends' live story posts lead, with a calm
//  empty state before anyone has shared today.
//

import SwiftUI

struct SignalZoneView: View {
    @Environment(Store.self) private var store

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quiet out there for now.")
                            .font(.serifItalic(15))
                            .foregroundStyle(Theme.textCream.opacity(0.85))
                        Text("When friends post a moment, it shows up here.")
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Theme.textCream.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
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
                    Text(store.friends.isEmpty
                         ? "Add friends to light this zone up"
                         : "\(store.friends.count) friend\(store.friends.count == 1 ? "" : "s") connected")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.75))

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
    }
}

#Preview {
    SignalZoneView()
        .environment(Store())
}
