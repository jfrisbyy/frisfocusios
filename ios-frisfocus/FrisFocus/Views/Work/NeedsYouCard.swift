//
//  NeedsYouCard.swift
//  FrisFocus
//
//  A single tappable Needs You card. Tapping reveals a witness-model
//  action row whose options depend on the card's kind. Declining ("Not
//  today") is free — no confirm, no penalty, no guilt copy.
//

import SwiftUI
import UIKit

struct NeedsYouCard: View {
    let item: NeedsYouItem
    /// Slightly stronger presence for the #1 card so the eye lands first.
    var isLead: Bool = false
    let onAction: (NeedsYouAction) -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    expanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                actionRow
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white.opacity(isLead ? 1 : 0.96))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(item.tint.opacity(isLead ? 0.30 : 0.18), lineWidth: isLead ? 0.8 : 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.tint.opacity(0.14))
                Image(systemName: item.glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.sans(13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(item.subtitle)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.28))
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 8) {
            if item.canStartFocus {
                actionPill("Start focus", system: "leaf.fill", tint: Theme.alertGreen) {
                    onAction(.startFocus)
                }
            }
            if item.canLog && item.kind != .routine {
                actionPill("Log it", system: "checkmark", tint: Theme.alertGreen) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onAction(.log)
                }
            }
            if item.kind == .routine {
                actionPill("Open", system: "arrow.up.forward", tint: Theme.cadenceLavenderDark) {
                    onAction(.open)
                }
            }
            Spacer(minLength: 0)
            overflowMenu
        }
    }

    /// "Not today" + "Snooze" tucked into a quiet ellipsis so the row stays
    /// uncluttered — both are soft, low-stakes choices.
    private var overflowMenu: some View {
        Menu {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onAction(.snoozeTilEvening)
            } label: {
                Label("Snooze til evening", systemImage: "moon")
            }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onAction(.notToday)
            } label: {
                Label("Not today", systemImage: "xmark")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                Text("Later")
                    .font(.sans(12, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.05)))
        }
    }

    private func actionPill(
        _ title: String,
        system: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
