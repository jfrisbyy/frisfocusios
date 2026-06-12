//
//  DiscoverProfileSheet.swift
//  FrisFocus
//
//  A small profile preview for someone you haven't added yet — opened
//  by tapping a discover suggestion. Wears the same editorial design
//  as the full profiles: their designed header with "CURRENTLY IN"
//  and the season carved in, then the floating identity card with
//  name, lifetime days, intention, mood line, and the dark Add pill.
//  Bio and join date are fetched lazily since the suggestion list
//  doesn't carry them.
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

    private var card: SeasonCard? { profile.card }

    private var relationship: FriendRelationship {
        myId.map { graph.relationship(to: profile.id, myUserId: $0) } ?? .none
    }

    private var accent: Color {
        if let hex = card?.accentHex { return Color(hex: hex) }
        return profile.signatureColor
    }

    private var shortSeasonName: String? {
        guard let full = card?.seasonName else { return nil }
        let trimmed = full.replacingOccurrences(of: " Season", with: "")
        return trimmed.isEmpty ? full : trimmed
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBanner

                    identityCard
                        .padding(.horizontal, 16)
                        .offset(y: -46)
                        .padding(.bottom, -46)

                    VStack(spacing: 14) {
                        if let bio, !bio.isEmpty {
                            Text(bio)
                                .font(.sans(14, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }

            closeButton
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
        .presentationDetents([.medium, .large])
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
                .foregroundStyle(Theme.textCream)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.30)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    /// Their designed header — season cover, header photo, or accent
    /// band — with the season carved in like the full profile.
    private var headerBanner: some View {
        ZStack(alignment: .bottomLeading) {
            ProfilePosterBackground(
                coverId: card?.coverId,
                headerURL: profile.headerURL,
                accent: profile.signatureColor,
                animated: false
            )

            if let seasonName = shortSeasonName {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENTLY IN")
                        .font(.sans(9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.textCream.opacity(0.75))
                    Text(seasonName)
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    if let dayNumber = card?.currentDay {
                        Text(card?.seasonLengthDays.map { "DAY \(dayNumber) OF \($0)" } ?? "DAY \(dayNumber)")
                            .font(.sans(9, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Theme.textCream.opacity(0.85))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 58)
            }
        }
        .frame(height: 196)
        .clipped()
    }

    /// The same floating identity card every profile wears.
    private var identityCard: some View {
        ProfileIdentityCard(
            name: profile.displayName,
            lifetimeDays: card?.lifetimeDays,
            metaLine: metaLine,
            intention: card?.intention,
            moodLine: card?.moodLine
        ) {
            avatar
        } extra: {
            if suggestion.mutualCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    Text("\(suggestion.mutualCount) in common")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        } pills: {
            actionPill
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let handle = profile.handle { parts.append(handle) }
        if let joinedDate {
            parts.append("since \(joinedDate.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.isEmpty ? "On FrisFocus" : parts.joined(separator: " · ")
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
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .padding(5)
        .background(Circle().fill(Color(hex: 0xFFFBF1)))
        .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1))
    }

    private var initialsDisc: some View {
        ZStack {
            Circle().fill(accent)
            Text(profile.initials)
                .font(.serif(23, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var actionPill: some View {
        switch relationship {
        case .none:
            IdentityPill(title: "Add friend", icon: "person.badge.plus", filled: true, isWorking: isSending) {
                guard let myId, !isSending else { return }
                isSending = true
                Task {
                    await graph.sendRequest(to: profile, myUserId: myId)
                    socialSync.pokeEngine(trigger: "friend")
                    isSending = false
                }
            }
        case .requestSent:
            IdentityPill(title: "Request sent", icon: "checkmark", filled: false) { }
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        case .friends:
            IdentityPill(title: "Friends", icon: "person.2.fill", filled: false) { }
                .allowsHitTesting(false)
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
