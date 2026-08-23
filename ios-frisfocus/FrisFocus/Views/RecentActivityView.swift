//
//  RecentActivityView.swift
//  FrisFocus
//
//  The "Recent activity" sheet: every like and comment on your stories
//  plus every cheer you received, one chronological list. Rows that
//  point at a still-live story open your own tape; cheer rows open the
//  cheer history. Opening the sheet clears the unseen badge, but items
//  that were new when it opened keep their amber dot for this viewing.
//

import SwiftUI
import UIKit

struct RecentActivityView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The last-seen stamp captured the moment the sheet opened, so
    /// "new" dots stay visible while the badge itself clears.
    @State private var seenCutoff: Date = .distantFuture
    @State private var showMyStories: Bool = false
    @State private var showCheers: Bool = false

    private var items: [ActivityItem] { store.activityItems }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                activityRow(item)
                                if item.id != items.last?.id {
                                    Rectangle()
                                        .fill(Theme.textPrimary.opacity(0.06))
                                        .frame(height: 0.5)
                                        .padding(.leading, 66)
                                }
                            }
                        }
                        .background(Theme.paperCream)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Theme.warmWheat.ignoresSafeArea())
            .navigationTitle("Recent activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .onAppear {
            if seenCutoff == .distantFuture {
                seenCutoff = store.activityLastSeenAt
            }
            store.markActivitySeen()
        }
        .fullScreenCover(isPresented: $showMyStories) {
            StoryPlayerView(mode: .mine)
                .environment(store)
        }
        .sheet(isPresented: $showCheers) {
            CheerHistoryView()
                .environment(store)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func activityRow(_ item: ActivityItem) -> some View {
        let storyAlive = item.postId.map { id in
            store.storyPosts.contains { $0.id == id }
        } ?? false
        let tappable = item.kind == .cheer || storyAlive

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switch item.kind {
            case .cheer:
                showCheers = true
            case .like, .comment:
                if storyAlive { showMyStories = true }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                initialsDisc(item)

                VStack(alignment: .leading, spacing: 2) {
                    // "Jordan liked your story" / "Sam commented" / "Priya cheered you on"
                    (
                        Text(item.actorName).font(.sans(14, weight: .semibold))
                        + Text(" \(item.verbLine)").font(.sans(14, weight: .regular))
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                    if let detail = item.detail, !detail.isEmpty {
                        Text("“\(detail)”")
                            .font(.serifItalic(13, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        Text(item.date.formatted(.relative(presentation: .named)))
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        if item.kind != .cheer && !storyAlive {
                            Text("story expired")
                                .font(.sans(11, weight: .regular))
                                .foregroundStyle(Theme.textTertiary.opacity(0.8))
                        }
                    }
                }

                Spacer(minLength: 4)

                if item.date > seenCutoff {
                    Circle()
                        .fill(Theme.sunWarm)
                        .frame(width: 8, height: 8)
                }

                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.25))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel("\(item.actorName) \(item.verbLine)")
    }

    private func initialsDisc(_ item: ActivityItem) -> some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text(item.actorInitials)
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 40, height: 40)
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Theme.paperCream)
                Image(systemName: kindGlyph(item.kind))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(kindTint(item.kind))
            }
            .frame(width: 17, height: 17)
            .offset(x: 3, y: 3)
        }
    }

    private func kindGlyph(_ kind: ActivityKind) -> String {
        switch kind {
        case .like: return "heart.fill"
        case .comment: return "bubble.left.fill"
        case .cheer: return "hands.clap.fill"
        }
    }

    private func kindTint(_ kind: ActivityKind) -> Color {
        switch kind {
        case .like: return Theme.alertRed
        case .comment: return Theme.textPrimary
        case .cheer: return Theme.sunWarm
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.haze")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Quiet for now")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("When friends like or comment on your stories, or send you a cheer, it lands here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RecentActivityView()
        .environment(Store())
}
