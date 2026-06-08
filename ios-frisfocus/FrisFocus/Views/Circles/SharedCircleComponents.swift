//
//  SharedCircleComponents.swift
//  FrisFocus
//
//  Shared UI building blocks for the real, Supabase-backed shared
//  circles (`CircleGraphService` / `SharedCircle`). Kept deliberately
//  separate from the seeded local-circle views (`CircleDetailView`,
//  `CreateCircleView`) so the two systems never tangle: this file only
//  ever speaks `RemoteProfile` + `CircleKind`.
//

import SwiftUI

// MARK: - Kind styling

extension CircleKind {
    /// Short human label used on list cards and the create chooser.
    var shortLabel: String {
        switch self {
        case .parallel: return "Same list"
        case .collective: return "One number"
        }
    }

    /// Uppercase eyebrow shown in the detail hero.
    var eyebrow: String {
        switch self {
        case .parallel: return "PARALLEL CIRCLE"
        case .collective: return "COLLECTIVE CIRCLE"
        }
    }

    /// Accent tint — purple for "same list", green for "one number".
    var tint: Color {
        switch self {
        case .parallel: return Color(hex: 0x7F77DD)
        case .collective: return Color(hex: 0x639922)
        }
    }

    /// Darker variant legible on a 15% wash of `tint`.
    var tintDark: Color {
        switch self {
        case .parallel: return Color(hex: 0x4A3F9E)
        case .collective: return Color(hex: 0x3B6D11)
        }
    }

    /// Night-sky hero gradient stops (matches the seeded detail's cue:
    /// violet night for parallel, forest night for collective).
    var heroColors: [Color] {
        switch self {
        case .parallel:
            return [Color(hex: 0x1A1830), Color(hex: 0x3A2F48), Color(hex: 0x6B4D52)]
        case .collective:
            return [Color(hex: 0x13251A), Color(hex: 0x1F4030), Color(hex: 0x3B6D4A)]
        }
    }
}

// MARK: - Number formatting

/// Render a contribution/target value without a trailing `.0`, but keep
/// one decimal when the value isn't whole (e.g. `12.5`).
func circleNumber(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%.1f", value)
}

// MARK: - Avatar

/// A circular avatar for a `RemoteProfile`: their photo when available,
/// otherwise an initials disc. `highlight` paints the gold "you" ring;
/// `onDark` switches the hairline ring colour for night-sky heroes.
struct RemoteCircleAvatar: View {
    let profile: RemoteProfile?
    var size: CGFloat = 44
    var highlight: Bool = false
    var onDark: Bool = false

    var body: some View {
        ZStack {
            if let url = profile?.photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { disc }
            } else {
                disc
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { ring }
    }

    private var disc: some View {
        ZStack {
            Theme.textPrimary
            Text(profile?.initials ?? "?")
                .font(.sans(size * 0.36, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var ring: some View {
        if highlight {
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Theme.sunWarm, Theme.sunOuter],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.8
            )
        } else {
            Circle().strokeBorder(
                onDark ? Theme.textCream.opacity(0.85) : Theme.textPrimary.opacity(0.08),
                lineWidth: onDark ? 1.2 : 1
            )
        }
    }
}

// MARK: - Overlapping member stack

/// Overlapping disc stack used on list cards and the detail hero. The
/// signed-in user gets the gold ring; the tail closes with a soft `+N`.
struct RemoteCircleAvatarStack: View {
    let members: [RemoteProfile]
    let myUserId: String
    var maxVisible: Int = 4
    var diameter: CGFloat = 26
    var onDark: Bool = true

    var body: some View {
        let visible = Array(members.prefix(maxVisible))
        let remainder = max(0, members.count - visible.count)

        HStack(spacing: -7) {
            ForEach(visible) { member in
                RemoteCircleAvatar(
                    profile: member,
                    size: diameter,
                    highlight: member.id == myUserId,
                    onDark: onDark
                )
            }
            if remainder > 0 {
                ZStack {
                    Circle().fill(onDark ? Theme.textCream.opacity(0.16) : Theme.textPrimary.opacity(0.08))
                    Text("+\(remainder)")
                        .font(.sans(diameter * 0.36, weight: .semibold))
                        .foregroundStyle(onDark ? Theme.textCream.opacity(0.9) : Theme.textPrimary.opacity(0.7))
                }
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().strokeBorder(
                        onDark ? Theme.textCream.opacity(0.5) : Theme.textPrimary.opacity(0.12),
                        lineWidth: 0.8
                    )
                )
            }
        }
    }
}

// MARK: - Animated progress bar (collective circles)

/// A rounded, animated fill bar used for collective circle progress and
/// the per-member share rows.
struct CircleProgressBar: View {
    /// 0...1.
    let fraction: Double
    var tint: Color = Theme.alertGreen
    var height: CGFloat = 12
    var track: Color = Theme.textPrimary.opacity(0.08)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(track)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}
