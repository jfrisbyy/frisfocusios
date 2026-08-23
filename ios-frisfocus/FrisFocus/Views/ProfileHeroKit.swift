//
//  ProfileHeroKit.swift
//  FrisFocus
//
//  The redesigned profile shell shared by the self and friend pages —
//  one stretchy hero photo, one collapsing top bar, one floating
//  identity card anchored over the hero's bottom edge, one "today"
//  board card, and one card language for everything below. Self and
//  friend render the exact same pieces; only the slot contents differ.
//
//  Hard rule carried over from the mirror kit: NO denominators,
//  fractions, or point values ever render in these pieces.
//

import SwiftUI
import UIKit

// MARK: - Card chrome

extension View {
    /// The one profile card treatment — warm paper surface, continuous
    /// corners, a soft lift, and a hairline edge. Every card on the
    /// profile uses exactly this so the page reads as one system.
    func mirrorCard(radius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(hex: 0xFFFBF1))
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.05), lineWidth: 0.8)
            )
    }
}

// MARK: - Stretchy hero photo

/// The full-bleed hero at the top of the profile scroll. Pulling down
/// stretches the photo from the very top of the screen; scrolling up
/// slides it away at just under half speed (parallax) while a warm
/// darkening settles in, so the identity card appears to glide over it.
struct MirrorHeroHeader: View {
    let headerURL: URL?
    let accent: Color
    /// The owner's day (0…1) — a soft golden lift on strong days.
    var strength: Double = 0.5
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            let risen = max(0, -minY)
            let parallax = risen * 0.45
            let fade = min(0.45, (risen / max(1, height)) * 0.6)

            ZStack {
                MirrorHeaderBackground(headerURL: headerURL, accent: accent, strength: strength)
                Color(hex: 0x140D06).opacity(fade)
            }
            .frame(width: geo.size.width, height: height + stretch)
            .offset(y: -stretch + parallax)
            // A fixed window: open far above for the pull-down stretch,
            // closed at the bottom so the parallaxing photo never bleeds
            // under the seam beside the identity card.
            .mask {
                Rectangle().padding(.top, -1200)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Collapsing top bar

/// The persistent top chrome. Over the photo it's just the two glass
/// controls; once the identity card's name scrolls under it, a wheat
/// bar with a hairline fades in and the name slides into the center.
struct MirrorTopBar<Leading: View, Trailing: View>: View {
    let title: String
    /// 0 = transparent over the photo → 1 = solid bar with the name.
    let progress: Double
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay {
            Text(title)
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 74)
                .opacity(progress)
                .offset(y: (1 - progress) * 7)
                .allowsHitTesting(false)
        }
        .background {
            ZStack(alignment: .bottom) {
                Theme.warmWheat
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.08))
                    .frame(height: 0.5)
            }
            .opacity(progress)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Floating identity card

/// The single anchored identity block — avatar floating half above the
/// card, name with the handle + days-shown-up line, the status quote,
/// a meta slot (season pill, mutuals, …) and the action pills. Replaces
/// the old name-on-photo + floating-pill seam.
struct MirrorIdentityCard<Avatar: View, Meta: View, Actions: View>: View {
    let name: String
    let handle: String?
    let daysShownUp: Int?
    let statusText: String
    var statusEditable: Bool = false
    var onStatusEdit: (() -> Void)? = nil

    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let meta: () -> Meta
    @ViewBuilder let actions: () -> Actions

    private let avatarSize: CGFloat = 78
    private let avatarLift: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Space the floating avatar occupies inside the card.
                Color.clear
                    .frame(width: avatarSize, height: avatarSize - avatarLift)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    metaLine
                }
                .padding(.top, 5)

                Spacer(minLength: 0)
            }

            MirrorStatusLine(text: statusText, editable: statusEditable, onEdit: onStatusEdit)

            meta()

            actions()
                .padding(.top, 3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: Color.black.opacity(0.13), radius: 18, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8)
        )
        .overlay(alignment: .topLeading) {
            avatar()
                .frame(width: avatarSize, height: avatarSize)
                .offset(x: 18, y: -avatarLift)
        }
    }

    /// `@handle · N days shown up` — the number bold, the stat omitted
    /// entirely when it would read "0 days shown up".
    @ViewBuilder
    private var metaLine: some View {
        let showsHandle = !(handle ?? "").isEmpty
        let showsDays = (daysShownUp ?? 0) > 0
        Group {
            if showsHandle, showsDays {
                Text("\(prefixed(handle ?? "")) · ") + boldDays + Text(" days shown up")
            } else if showsHandle {
                Text(prefixed(handle ?? ""))
            } else if showsDays {
                boldDays + Text(" days shown up")
            }
        }
        .font(.sans(12.5, weight: .regular))
        .foregroundStyle(Theme.textPrimary.opacity(0.55))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var boldDays: Text {
        Text("\(daysShownUp ?? 0)").font(.sans(12.5, weight: .bold))
    }

    private func prefixed(_ handle: String) -> String {
        handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}

// MARK: - Today board (one card, no inner scrolling)

/// The whole visible board as ONE card — each category is a tinted
/// header row plus its checked-first task rows, separated by inset
/// hairlines. Long categories expand in place ("Show all N") instead
/// of scrolling inside the page scroll. When `showsRows` is false
/// (the Open tier — task names stay private) only the header rows
/// with completion counts render.
struct MirrorTodayBoard: View {
    let sections: [(Category, [MirrorTaskRow])]
    var showsRows: Bool = true

    @State private var expanded: Set<Category> = []
    private let previewCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.0) { index, pair in
                if index > 0 { divider }
                sectionView(category: pair.0, rows: pair.1)
            }
        }
        .padding(.vertical, 2)
        .mirrorCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func sectionView(category: Category, rows: [MirrorTaskRow]) -> some View {
        let tint = Color(hex: category.hexColor)
        let doneCount = rows.filter { $0.isDone }.count
        let isExpanded = expanded.contains(category)
        let visible: [MirrorTaskRow] = showsRows
            ? (isExpanded ? rows : Array(rows.prefix(previewCount)))
            : []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(category.displayName.uppercased())
                    .font(.sans(11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textPrimary.opacity(0.62))
                Spacer(minLength: 8)
                if doneCount > 0 {
                    Text("\(doneCount) today")
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Text("quiet so far")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.38))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, visible.isEmpty ? 13 : 4)

            ForEach(visible) { row in
                MirrorTaskRowView(row: row, tint: tint)
                    .frame(height: 40)
            }

            if showsRows && rows.count > previewCount {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if isExpanded {
                            expanded.remove(category)
                        } else {
                            expanded.insert(category)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Show all \(rows.count)")
                            .font(.sans(12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.sans(9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Show fewer \(category.displayName) tasks" : "Show all \(rows.count) \(category.displayName) tasks")
            } else if !visible.isEmpty {
                Color.clear.frame(height: 10)
            }
        }
    }
}

// MARK: - Record tiles (cheers / activity)

/// A compact tappable tile for the record row — icon up top, title and
/// a quiet italic subline below, an unread dot when something's new.
struct MirrorRecordTile: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.72))
                    Spacer(minLength: 0)
                    if badge {
                        Circle()
                            .fill(Theme.sunOuter)
                            .frame(width: 8, height: 8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.25))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.serifItalic(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mirrorCard()
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)\(badge ? ". Something new" : "")")
    }
}

// MARK: - Section card

/// A tracked-uppercase section header with its content in the shared
/// card — destinations, seasons before, together, since-you-connected
/// all wear this so the record reads as one system.
struct MirrorSectionCard<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            JournalSectionHeader(label: label)
                .padding(.horizontal, 2)
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mirrorCard()
        }
    }
}
