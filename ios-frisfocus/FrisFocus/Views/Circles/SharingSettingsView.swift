//
//  SharingSettingsView.swift
//  FrisFocus
//
//  The dial that sets what THIS friend gets to see of ME — three
//  levels of trust: Quiet (a little), Open (the shape), Full (the real
//  day). Visibility is always the owner's choice, shown honestly; the
//  app never exposes more than the chosen tier allows.
//
//  Full carries a deliberate, clearly-explained sub-choice: share the
//  whole list (open items included) or only what was finished — so
//  picking Full never silently over-shares the unfinished list.
//
//  The live preview runs the real `SignalEngine` against the current
//  user's facts using the candidate clearance, so the string previewed
//  is exactly what this friend would see.
//

import SwiftUI
import UIKit

struct SharingSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(\.dismiss) private var dismiss

    let friendId: UUID

    @State private var clearance: SharingSettings = SharingSettings()
    @State private var loaded: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    tierPicker
                    if clearance.tier == .full {
                        fullOptionsCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    previewCard
                    footerNote
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !loaded, let friend = store.friend(by: friendId) else { return }
            clearance = friend.theirClearanceToMyData
            loaded = true
        }
    }

    // MARK: - Header

    private var friend: Friend? { store.friend(by: friendId) }
    private var displayName: String { friend?.displayName ?? "Friend" }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.sans(15, weight: .medium))
                        Text(displayName).font(.sans(14, weight: .regular))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(displayName)")
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SHARING WITH")
                    .font(.sans(10, weight: .medium)).tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("What \(displayName) sees")
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your dial, not theirs. They can always reach you the same ways — this only changes how much of your day they witness.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Tier picker

    private var tierPicker: some View {
        VStack(spacing: 10) {
            ForEach(VisibilityTier.allCases, id: \.self) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: VisibilityTier) -> some View {
        let selected = clearance.tier == tier
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                clearance = SharingSettings.from(tier: tier, showOpenItemsAtFull: clearance.showOpenItemsAtFull)
            }
            store.updateFriendClearance(friendId: friendId, clearance: clearance)
            // Server-side too: the chosen tier trims the season card THEY
            // receive at the data layer, not just in rendering.
            if let remote = socialSync.remoteId(forLocal: friendId) {
                Task { await socialSync.setShareTier(forRemote: remote, tier: tier) }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Theme.alertGreen : Theme.textPrimary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(Theme.alertGreen).frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tier.shareVerb)
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(tier.tag)
                            .font(.sans(9, weight: .bold)).tracking(1)
                            .foregroundStyle(selected ? Theme.textCream : Theme.textPrimary.opacity(0.55))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(selected ? Theme.alertGreen : Theme.textPrimary.opacity(0.08)))
                    }
                    Text(tier.detail)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(selected ? Theme.alertGreen.opacity(0.08) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.alertGreen.opacity(0.45) : Theme.textPrimary.opacity(0.08),
                                  lineWidth: selected ? 1 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.shareVerb). \(tier.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Full sub-choice

    private var fullOptionsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show open items too")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(clearance.showOpenItemsAtFull
                         ? "\(displayName) sees your whole list — finished and still-open."
                         : "\(displayName) sees only what you finished. Open items stay private.")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { clearance.showOpenItemsAtFull },
                    set: { newValue in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            clearance.showOpenItemsAtFull = newValue
                        }
                        store.updateFriendClearance(friendId: friendId, clearance: clearance)
                    }
                ))
                .labelsHidden()
                .tint(Theme.alertGreen)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Live preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(displayName.uppercased()) SEES YOUR DAY AS")
                .font(.sans(10, weight: .medium)).tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.alertGreen)
                    .padding(.top, 2)
                Text(previewText)
                    .font(.serifItalic(17, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.18), value: previewText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.alertGreen.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.alertGreen.opacity(0.22), lineWidth: 0.5)
            )

            Text("Updates live as you choose.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private var previewText: String {
        SignalEngine.headline(
            for: store.currentUserId,
            facts: store.signalFacts,
            clearance: clearance
        )
    }

    private var footerNote: some View {
        Text("Full visibility is witnessing, not surveillance — your finished things read warm, anything open reads gentle. Never judgment.")
            .font(.sans(12, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Aaron — full") {
    let store = Store()
    return NavigationStack {
        if let aaron = store.friends.first {
            SharingSettingsView(friendId: aaron.id)
        }
    }
    .environment(store)
}
