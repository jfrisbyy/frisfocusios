//
//  ProfileIdentityCard.swift
//  FrisFocus
//
//  The floating identity card every profile shares — a warm white
//  card that overlaps the hero seam. Avatar (slot, so each surface
//  keeps its own story-ring behavior), name with the one number that
//  matters (lifetime days shown up), handle + tenure, the intention
//  as a quiet italic quote, an optional mood line, then surface-
//  specific extras (mutual friends, edit affordances) and the pill row.
//

import SwiftUI
import UIKit

struct ProfileIdentityCard<Avatar: View, Extra: View, Pills: View>: View {
    let name: String
    let lifetimeDays: Int?
    let metaLine: String
    let intention: String?
    let moodLine: String?
    /// When set, the mood line renders as a tappable edit affordance
    /// (the owner's own card).
    var onMoodTap: (() -> Void)? = nil

    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let extra: () -> Extra
    @ViewBuilder let pills: () -> Pills

    private let avatarSize: CGFloat = 74
    private let avatarLift: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Space the floating avatar occupies inside the card.
                Color.clear
                    .frame(width: avatarSize, height: avatarSize - avatarLift)

                VStack(alignment: .leading, spacing: 3) {
                    nameRow
                    Text(metaLine)
                        .font(.sans(12.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.top, 4)
            }

            if let intention, !intention.isEmpty {
                Text("“\(intention)”")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            moodRow

            extra()

            pills()
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8)
        )
        .overlay(alignment: .topLeading) {
            avatar()
                .frame(width: avatarSize, height: avatarSize)
                .offset(x: 18, y: -avatarLift)
        }
    }

    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.serif(23, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if let lifetimeDays, lifetimeDays > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(lifetimeDays)")
                        .font(.serif(23, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("days\nshown up")
                        .font(.sans(8.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .lineLimit(2)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(lifetimeDays) days shown up, ever")
            }
        }
    }

    @ViewBuilder
    private var moodRow: some View {
        if let onMoodTap {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onMoodTap()
            } label: {
                moodContent(editable: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(moodLine == nil ? "Set a mood line" : "Edit your mood line")
        } else if let moodLine, !moodLine.isEmpty {
            moodContent(editable: false)
        }
    }

    private func moodContent(editable: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.sunOuter)
            Text(moodLine?.isEmpty == false ? moodLine! : "Set a mood…")
                .font(.sans(13, weight: .medium))
                .foregroundStyle(
                    moodLine?.isEmpty == false
                        ? Theme.textPrimary.opacity(0.65)
                        : Theme.textPrimary.opacity(0.35)
                )
                .lineLimit(1)
            if editable {
                Image(systemName: "pencil")
                    .font(.sans(10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
        }
    }
}

// MARK: - Shared pill pieces

/// The big dark relationship pill — "Friends ✓", "Add friend",
/// "Requested", "Accept request".
struct IdentityPill: View {
    let title: String
    var icon: String? = nil
    /// Filled = the dark primary look; outline = quiet secondary.
    var filled: Bool = true
    var isWorking: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(filled ? Theme.textCream : Theme.textPrimary)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.sans(13, weight: .bold))
                }
                Text(title)
                    .font(.sans(15, weight: .semibold))
            }
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(filled ? 0 : 0.16), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

/// The round secondary button beside the pill (message, settings).
struct IdentityRoundButton: View {
    let icon: String
    var badge: Bool = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.14), lineWidth: 1))

                if badge {
                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 9, height: 9)
                        .offset(x: -3, y: 3)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
