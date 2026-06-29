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
    /// gesture — passes a 0...1 fraction of how far down the rail the
    /// finger is (0 = top of the page, 1 = the very bottom). The parent
    /// translates this into a live scroll offset so the page follows the
    /// finger smoothly, like dragging a scrollbar thumb.
    var onScrub: ((Double) -> Void)? = nil

    /// Fixed-width track so the rail's footprint never changes when the
    /// active label swaps between SUN / WORK / NOTE / MILESTONES —
    /// different label widths would otherwise nudge the layout during
    /// scroll. Sized to fit the longest label (MILESTONES).
    private let railWidth: CGFloat = 80
    /// Wider hit area surfaced while a scrub is in flight so the
    /// finger keeps tracking even if it drifts left of the slim rail.
    private let scrubExpandedWidth: CGFloat = 110
    /// How far the finger must travel along the rail before scrub
    /// engages. Deliberately generous so a quick tap stays a tap
    /// (handled by the section Buttons) and a casual graze near the
    /// right edge stays a normal vertical scroll — the rail only takes
    /// over on an intentional drag.
    private let scrubEngageDistance: CGFloat = 20
    /// Only touches that START within this slim strip on the right edge
    /// (the rail itself) can begin a scrub. A drag that begins further
    /// left — over page content — is left alone so it scrolls normally.
    private let grabZoneWidth: CGFloat = 44
    /// The scrub must be clearly vertical to engage: the vertical travel
    /// has to exceed the horizontal travel by this factor. A sideways or
    /// diagonal motion (an ordinary scroll fling) no longer hijacks the
    /// rail.
    private let verticalDominanceRatio: CGFloat = 1.6
    /// Small vertical slop above/below the visible labels so the rail
    /// stays comfortable to grab — but no further. The rail's hit area
    /// used to span the entire screen height (the scrub backdrop is a
    /// Shape, which greedily fills all proposed height), silently
    /// swallowing taps on anything near the right edge — most notably
    /// the profile avatar in the top-right corner.
    private let verticalHitSlop: CGFloat = 12

    @State private var isScrubbing: Bool = false
    /// Latches true for the duration of a single drag once it has been
    /// judged not-a-scrub (wrong origin or not vertical enough), so we
    /// don't re-evaluate mid-gesture and accidentally grab a scroll that
    /// later curves vertical.
    @State private var gestureRejected: Bool = false
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

    /// A plain drag that only engages once the finger has moved a few
    /// points along the rail. Below that threshold the touch falls
    /// through to the section Buttons (so a quick tap is always a jump),
    /// and a normal vertical scroll that merely grazes the right edge
    /// isn't hijacked. Once engaged, the finger's position maps
    /// continuously onto the page like a scrollbar thumb.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: scrubEngageDistance, coordinateSpace: .local)
            .onChanged { value in
                if !isScrubbing {
                    if gestureRejected { return }

                    // Must begin on the slim rail itself, not a wide
                    // strip to its left over the page content.
                    let startedOnRail = value.startLocation.x >= railWidth - grabZoneWidth
                    // Must be a predominantly vertical scrub — sideways
                    // or diagonal motion is left to the scroll view.
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    let isVertical = dy > dx * verticalDominanceRatio

                    guard startedOnRail, isVertical else {
                        gestureRejected = true
                        return
                    }

                    isScrubbing = true
                    engageHaptic.prepare()
                    engageHaptic.impactOccurred()
                    boundaryHaptic.prepare()
                }
                let fraction = fractionForY(value.location.y)
                onScrub?(fraction)

                // Light tick each time the finger crosses into a new
                // section while scrubbing.
                let zone = zoneForFraction(fraction)
                if zone != lastScrubZone {
                    if lastScrubZone != nil {
                        boundaryHaptic.impactOccurred()
                        boundaryHaptic.prepare()
                    }
                    lastScrubZone = zone
                }
            }
            .onEnded { _ in
                isScrubbing = false
                lastScrubZone = nil
                gestureRejected = false
            }
    }

    /// Maps a finger y-position (in the rail's local coordinate space)
    /// onto a 0...1 fraction of the rail's visible height.
    private func fractionForY(_ y: CGFloat) -> Double {
        let h = max(railHeight, 1)
        let clamped = max(0, min(h, y - verticalHitSlop))
        return Double(clamped / h)
    }

    /// Which zone a 0...1 fraction lands in — used only for boundary
    /// haptics while scrubbing.
    private func zoneForFraction(_ fraction: Double) -> HomeZone {
        let zones = HomeZone.allCases
        let segment = Int(fraction * Double(zones.count))
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
