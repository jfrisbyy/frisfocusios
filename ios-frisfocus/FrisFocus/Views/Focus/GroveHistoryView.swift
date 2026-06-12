//
//  GroveHistoryView.swift
//  FrisFocus
//
//  A calm look back at past grove sessions — who you focused with, when,
//  and for how long — plus any live co-focus streaks. Same warm paper
//  aesthetic as the rest of Focus.
//

import SwiftUI

struct GroveHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.recentGroves.isEmpty {
                        emptyState
                    } else {
                        Text("\(store.totalGroveMinutes) minutes focused together, all time")
                            .font(.sans(11, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        ForEach(store.recentGroves) { block in
                            row(block)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle("Past groves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tree")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text("No groves yet")
                .font(.serif(18, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
            Text("Focus together once and it'll show up here.")
                .font(.serifItalic(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func row(_ block: SharedFocusBlock) -> some View {
        let friendIds = block.participantIds.filter { $0 != store.currentUserId }
        let friends = friendIds.compactMap { id in store.friends.first(where: { $0.id == id }) }
        let names = friends.map(\.displayName)
        let minutes = max(0, Int(block.plannedDuration / 60))

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(friends.prefix(3)) { friend in
                    FriendAvatarView(friend: friend, size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.label ?? "Grove")
                        .font(.serif(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                    Text(withFriendsText(names))
                        .font(.sans(11))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(minutes)m")
                    .font(.serif(18, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }

            HStack(spacing: 8) {
                Text(block.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.sans(11))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                if let fid = friendIds.first {
                    let streak = store.coFocusStreak(with: fid)
                    if streak >= 2 {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xC97B4B))
                            Text("\(streak)-day streak")
                                .font(.sans(11, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.warmWheat)
        )
    }

    private func withFriendsText(_ names: [String]) -> String {
        if names.isEmpty { return "Solo" }
        if names.count == 1 { return "with \(names[0])" }
        if names.count == 2 { return "with \(names[0]) & \(names[1])" }
        return "with \(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
