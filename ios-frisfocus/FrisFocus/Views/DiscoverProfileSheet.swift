//
//  DiscoverProfileSheet.swift
//  FrisFocus
//
//  A small profile preview for someone you haven't added yet — opened
//  by tapping a discover suggestion. Shows their avatar, name, handle,
//  bio, when they joined, and the mutual count, with the same one-tap
//  Add (flipping to Pending) as the row. Bio and join date are fetched
//  lazily since the suggestion list doesn't carry them.
//

import SwiftUI
import UIKit
import Supabase

/// The extra profile columns the preview fetches on demand.
private nonisolated struct ProfileDetailRow: Codable, Sendable {
    let bio: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case bio
        case createdAt = "created_at"
    }
}

struct DiscoverProfileSheet: View {
    let suggestion: DiscoverSuggestion
    /// The shared friend graph — relationship state and the Add action
    /// both run through it so the row underneath stays in sync.
    let graph: FriendGraphService

    @Environment(AuthManager.self) private var auth
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(\.dismiss) private var dismiss

    @State private var bio: String?
    @State private var joinedDate: Date?
    @State private var isSending = false

    private var profile: RemoteProfile { suggestion.profile }
    private var myId: String? { auth.user?.id }

    private var relationship: FriendRelationship {
        myId.map { graph.relationship(to: profile.id, myUserId: $0) } ?? .none
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBanner

                    avatar
                        .padding(4)
                        .background(Circle().fill(Theme.warmWheat))
                        .offset(y: -44)
                        .padding(.bottom, -44)

                    VStack(spacing: 14) {
                        identity
                        if let bio, !bio.isEmpty {
                            Text(bio)
                                .font(.sans(14, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        metaRow
                        actionButton
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }

            closeButton
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task { await loadDetail() }
    }

    // MARK: - Pieces

    private var closeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.warmWheat.opacity(0.92)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    /// Their header photo behind the top of the card — signature color
    /// underneath so nothing flashes empty while it loads (and as the
    /// default band when no photo is set).
    private var headerBanner: some View {
        profile.signatureColor
            .frame(height: 118)
            .overlay {
                if let url = profile.headerURL {
                    CachedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        profile.signatureColor
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                LinearGradient(
                    colors: [Color.black.opacity(0.18), .clear, Theme.warmWheat.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
            .clipped()
    }

    private var avatar: some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc
                }
            } else {
                initialsDisc
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
    }

    private var initialsDisc: some View {
        ZStack {
            Theme.textPrimary
            Text(profile.initials)
                .font(.serif(30, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    private var identity: some View {
        VStack(spacing: 3) {
            Text(profile.displayName)
                .font(.serif(24, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let handle = profile.handle {
                Text(handle)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            if suggestion.mutualCount > 0 {
                metaChip(
                    icon: "person.2.fill",
                    text: "\(suggestion.mutualCount) mutual friend\(suggestion.mutualCount == 1 ? "" : "s")"
                )
            }
            if let joinedDate {
                metaChip(
                    icon: "sparkles",
                    text: "Joined \(joinedDate.formatted(.dateTime.month(.wide).year()))"
                )
            }
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Theme.paperCream)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        switch relationship {
        case .none:
            Button {
                guard let myId, !isSending else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isSending = true
                Task {
                    await graph.sendRequest(to: profile, myUserId: myId)
                    socialSync.pokeEngine(trigger: "friend")
                    isSending = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView().tint(Theme.textCream)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Add friend")
                        .font(.sans(15, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)
        case .requestSent:
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                Text("Request sent")
                    .font(.sans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        case .friends:
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Friends")
                    .font(.sans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
        case .requestReceived, .isMe:
            EmptyView()
        }
    }

    // MARK: - Data

    private func loadDetail() async {
        do {
            let rows: [ProfileDetailRow] = try await supabase
                .from("profiles")
                .select("bio, created_at")
                .eq("id", value: profile.id)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            bio = row.bio?.trimmingCharacters(in: .whitespacesAndNewlines)
            joinedDate = row.createdAt.flatMap(Self.parseTimestamp)
        } catch {
            print("[Discover] profile detail failed: \(error)")
        }
    }

    /// Supabase timestamps come back ISO8601, with or without
    /// fractional seconds depending on the column's precision.
    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
