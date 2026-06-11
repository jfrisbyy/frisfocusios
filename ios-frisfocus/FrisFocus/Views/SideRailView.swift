//
//  SideRailView.swift
//  FrisFocus
//
//  The persistent right-edge zone navigator. Stateless — it's handed
//  the active zone, the progress through that zone, and the tint to
//  paint itself with. HomeView owns the scrolling state and feeds those
//  in.
//
//  Tapping any item calls `onTap(zone)`; HomeView turns that into a
//  scrollProxy.scrollTo(...) animation. Inactive items are tappable as
//  well (they expand their hit area).
//

import SwiftUI
import UIKit

enum HomeZone: String, CaseIterable, Identifiable {
    case sun = "Sun"
    case work = "Work"
    case note = "Note"
    case milestone = "Milestones"

    var id: String { rawValue }

    /// Identifier used by ScrollViewReader to scroll to this zone.
    var anchorID: String { rawValue.lowercased() }

    /// Dark-background zones (Sun) want a cream rail; the light
    /// Work / Note / Milestones zones want a charcoal rail.
    var prefersDarkRail: Bool {
        switch self {
        case .sun: return false
        case .work, .note, .milestone: return true
        }
    }
}

struct SideRailView: View {
    let activeZone: HomeZone
    /// 0...1 — fill across the active zone's track.
    let progress: Double
    /// Color the rail paints itself with. Comes from HomeView based on
    /// which zone is currently active.
    let tint: Color
    let onTap: (HomeZone) -> Void
    /// Called continuously while the user scrubs the rail with a drag
    /// gesture — fires once per zone the finger newly enters. The
    /// parent translates each call into a live scroll-to so the page
    /// follows the finger across the rail.
    var onScrub: ((HomeZone) -> Void)? = nil

    /// Fixed-width track so the rail's footprint never changes when the
    /// active label swaps between SUN / WORK / NOTE / MILESTONES —
    /// different label widths would otherwise nudge the layout during
    /// scroll. Sized to fit the longest label (MILESTONES).
    private let railWidth: CGFloat = 80
    /// Wider hit area surfaced while a scrub is in flight so the
    /// finger keeps tracking even if it drifts left of the slim rail.
    private let scrubExpandedWidth: CGFloat = 110
    /// How long the user must press the rail before scrub engages.
    /// Short enough to feel responsive when you mean to scrub; long
    /// enough that a casual vertical scroll near the right edge of the
    /// screen never trips the rail (which used to widen leftward mid-
    /// scroll, producing a side-to-side wobble).
    private let scrubEngageDelay: Double = 0.18
    /// Small vertical slop above/below the visible labels so the rail
    /// stays comfortable to grab — but no further. The rail's hit area
    /// used to span the entire screen height (the scrub backdrop is a
    /// Shape, which greedily fills all proposed height), silently
    /// swallowing taps on anything near the right edge — most notably
    /// the profile avatar in the top-right corner.
    private let verticalHitSlop: CGFloat = 12

    @State private var isScrubbing: Bool = false
    @State private var railHeight: CGFloat = 0
    @State private var lastScrubZone: HomeZone?
    @State private var engageHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var boundaryHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        // The interactive surface is sized to the visible labels (plus a
        // small slop), NOT the full screen height — so nothing above or
        // below the rail (like the profile avatar) loses its taps.
        VStack(alignment: .trailing, spacing: 24) {
            ForEach(HomeZone.allCases) { zone in
                if zone == activeZone {
                    activeItem(zone)
                } else {
                    inactiveItem(zone)
                }
            }
        }
        .frame(width: railWidth, alignment: .trailing)
        .padding(.trailing, 10)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { railHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in railHeight = h }
            }
        )
        .animation(.easeInOut(duration: 0.30), value: tint)
        .animation(.easeInOut(duration: 0.25), value: activeZone)
        .padding(.vertical, verticalHitSlop)
        .frame(width: isScrubbing ? scrubExpandedWidth : railWidth, alignment: .trailing)
        // Soft backdrop that fades in while scrubbing — purely a visual
        // cue that the rail has "opened up" into a scrub surface. Lives
        // in .background so it can never inflate the rail's layout (and
        // therefore its hit area) beyond the labels.
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(tint.opacity(isScrubbing ? 0.07 : 0))
                .frame(width: scrubExpandedWidth)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isScrubbing)
        .gesture(scrubGesture)
    }

    // MARK: - Scrub gesture

    /// Sequenced LongPress → Drag so a casual vertical scroll that
    /// happens to start on the right edge of the screen doesn't engage
    /// the rail (which would widen it leftward and fight the scroll).
    /// Holding briefly before sliding is the explicit "scrub" intent.
    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: scrubEngageDelay, maximumDistance: 4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if !isScrubbing {
                        isScrubbing = true
                        engageHaptic.prepare()
                        engageHaptic.impactOccurred()
                        boundaryHaptic.prepare()
                    }
                    let zone = zoneForY(drag.location.y)
                    if zone != lastScrubZone {
                        if lastScrubZone != nil {
                            boundaryHaptic.impactOccurred()
                            boundaryHaptic.prepare()
                        }
                        lastScrubZone = zone
                        onScrub?(zone)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                isScrubbing = false
                lastScrubZone = nil
            }
    }

    /// Maps a finger y-position (in the rail's local coordinate space)
    /// onto one of the four zones by splitting the rail's visible
    /// height into equal segments.
    private func zoneForY(_ y: CGFloat) -> HomeZone {
        let zones = HomeZone.allCases
        let h = max(railHeight, 1)
        // The gesture's local space includes the vertical slop padding;
        // shift back into the labels' own coordinate space.
        let clamped = max(0, min(h, y - verticalHitSlop))
        let segment = Int((clamped / h) * CGFloat(zones.count))
        let idx = min(zones.count - 1, max(0, segment))
        return zones[idx]
    }

    // MARK: - Active

    @ViewBuilder
    private func activeItem(_ zone: HomeZone) -> some View {
        Button {
            onTap(zone)
        } label: {
            VStack(alignment: .trailing, spacing: 6) {
                Text(zone.rawValue.uppercased())
                    .font(.sans(8, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(tint)
                    .transition(.opacity.animation(.easeInOut(duration: 0.20)))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.25))
                        .frame(width: 22, height: 3)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: max(0, 22 * CGFloat(progress)), height: 3)
                        .animation(.linear(duration: 0.06), value: progress)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(zone.rawValue))
        .accessibilityAddTraits(.isSelected)
    }

    // MARK: - Inactive

    @ViewBuilder
    private func inactiveItem(_ zone: HomeZone) -> some View {
        Button {
            onTap(zone)
        } label: {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint.opacity(0.4))
                .frame(width: 8, height: 2)
                // Pad out the hit target so taps register reliably.
                .padding(.vertical, 14)
                .padding(.leading, 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(zone.rawValue))
    }
}

#Preview {
    ZStack {
        Theme.skyMid.ignoresSafeArea()
        HStack {
            Spacer()
            SideRailView(
                activeZone: .sun,
                progress: 0.35,
                tint: Theme.textCream,
                onTap: { _ in }
            )
        }
    }
}
