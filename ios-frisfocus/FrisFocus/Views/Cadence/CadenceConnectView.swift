//
//  CadenceConnectView.swift
//  FrisFocus
//
//  The Cadence link hub, reached from the account screen (only when the
//  account holds both subscriptions). Opt-in: until you connect, it
//  explains the link and offers a single "Connect" action. Once
//  connected it shows your status, your links, a "Link a routine" entry,
//  and the privacy toggle for sleep/focus points.
//
//  FrisFocus is whole without Cadence — this whole surface is gated on
//  the entitlement check in `CadenceLinkService`.
//

import SwiftUI
import UIKit

struct CadenceConnectView: View {
    @Environment(Store.self) private var store
    @Environment(CadenceLinkService.self) private var cadence
    @Environment(AuthManager.self) private var auth

    @State private var showLinkFlow = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if store.cadenceConnected {
                    connectedStatusCard
                    linksSection
                    linkButton
                    privacySection
                    #if DEBUG
                    debugSection
                    #endif
                    disconnectButton
                } else {
                    connectHero
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(Theme.warmWheat.ignoresSafeArea())
        .navigationTitle("Cadence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cadence.refresh(myUserId: auth.user?.id) }
        .sheet(isPresented: $showLinkFlow) {
            LinkCadenceRoutineView()
        }
    }

    // MARK: - Connect (not yet opted in)

    private var connectHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                emblem
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(text: "Esengo link", opacity: 0.9, color: Theme.cadenceLavenderDark)
                    Text("Connect Cadence")
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            Text("You're signed in to the same Esengo account on Cadence. Link your routines so they show up in your day, open in Cadence to run, and earn points the moment Cadence records what actually happened — nothing to check off.")
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)

            statusPill(
                icon: "checkmark.seal.fill",
                text: "Cadence detected · same Esengo account · \(cadence.routineCount) routine\(cadence.routineCount == 1 ? "" : "s")"
            )

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.setCadenceConnected(true)
            } label: {
                Text("Connect Cadence")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.cadenceLavender)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Connecting is optional and only links what you choose. Nothing flows back to Cadence.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Connected status

    private var connectedStatusCard: some View {
        HStack(spacing: 13) {
            emblem
            VStack(alignment: .leading, spacing: 3) {
                Text("Cadence connected")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Same Esengo account · \(cadence.routineCount) routine\(cadence.routineCount == 1 ? "" : "s")")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.cadenceLavender)
        }
        .padding(14)
        .background(Theme.cadenceLavenderWash)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cadenceLavender.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: "Your links")

            if store.cadenceLinks.isEmpty {
                Text("No routines linked yet. Link one to bring it into your day.")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                Theme.textPrimary.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.cadenceLinks) { link in
                        linkRow(link)
                    }
                }
            }
        }
    }

    private func linkRow(_ link: CadenceLink) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.cadenceLavender.opacity(0.16))
                Image(systemName: linkIcon(link))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.cadenceLavenderDark)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayTitle)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(linkMeta(link))
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.removeCadenceLink(link)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(link.displayTitle)")
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var linkButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showLinkFlow = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Link a routine")
                    .font(.sans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.cadenceLavenderDark)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.cadenceLavender.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cadenceLavender.opacity(0.3), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Privacy")

            Toggle(isOn: Binding(
                get: { store.cadenceSurfacePointsSocially },
                set: { store.setCadenceSurfacePointsSocially($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show sleep & focus points to friends")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Off by default. Your sleep/focus points always count toward your own season — this only controls whether friends can see them, still respecting your per-friend sharing level.")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                }
            }
            .tint(Theme.cadenceLavender)
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Disconnect

    private var disconnectButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { store.setCadenceConnected(false) }
        } label: {
            Text("Disconnect Cadence")
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "Debug")
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.3)) {
                    store.debugSimulateCadenceOutcomes()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("Simulate tonight's Cadence outcomes")
                }
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.cadenceLavenderDark)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.cadenceLavender.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Developer only — fills linked routines/outcomes as if Cadence recorded them tonight.")
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
        }
    }
    #endif

    // MARK: - Pieces

    private var emblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cadenceLavender)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 46)
    }

    private func statusPill(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.cadenceLavender)
            Text(text)
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.cadenceLavenderWash)
        .clipShape(Capsule())
    }

    private func linkIcon(_ link: CadenceLink) -> String {
        switch link.type {
        case .launchRun: return "play.fill"
        case .passiveOutcome: return link.outcomeKind?.icon ?? "moon.stars.fill"
        }
    }

    private func linkMeta(_ link: CadenceLink) -> String {
        let pts = min(max(link.points, 0), CadenceLink.pointCeiling)
        var parts = ["\(pts) pts"]
        parts.append(seasonName(for: link))
        if link.type == .launchRun {
            parts.append(link.recurrence.label)
        }
        return parts.joined(separator: " · ")
    }

    private func seasonName(for link: CadenceLink) -> String {
        if let id = link.seasonId, id == store.currentSeason.id {
            return store.currentSeason.name
        }
        return store.currentSeason.name
    }
}

#Preview {
    NavigationStack {
        CadenceConnectView()
            .environment(Store())
            .environment(CadenceLinkService())
            .environment(AuthManager())
    }
}
