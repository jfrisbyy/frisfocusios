//
//  CirclesSideRailView.swift
//  FrisFocus
//
//  The floating right-edge rail on the Friends page. Two stacked
//  entries — FRIENDS and CIRCLES — each rendered as a thin vertical
//  uppercase label paired with a short bar. The active entry gets a
//  taller, fully-opaque bar; the inactive entry is muted.
//
//  Stateless: the parent owns the active selection and the tap
//  callback. C3a hardcodes `FRIENDS` as active; the actual scroll-to
//  behavior arrives once there are sections beneath the hero (C3d).
//

import SwiftUI
import UIKit

enum CirclesRailSection: String, CaseIterable, Identifiable {
    case friends = "FRIENDS"
    case circles = "CIRCLES"

    var id: String { rawValue }
}

struct CirclesSideRailView: View {
    let active: CirclesRailSection
    let onTap: (CirclesRailSection) -> Void
    /// Called continuously while the user scrubs the rail — fires once
    /// per section the finger newly enters. The parent translates each
    /// call into a live scroll-to so the page follows the finger.
    var onScrub: ((CirclesRailSection) -> Void)? = nil

    @State private var isScrubbing: Bool = false
    @State private var railHeight: CGFloat = 0
    @State private var lastScrubSection: CirclesRailSection?
    @State private var engageHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var boundaryHaptic = UIImpactFeedbackGenerator(style: .light)

    private let railWidth: CGFloat = 44
    private let scrubExpandedWidth: CGFloat = 96
    /// Brief hold required before scrub engages — prevents casual
    /// vertical scrolls near the right edge from widening the rail and
    /// fighting the user's scroll (a side-to-side wobble).
    private let scrubEngageDelay: Double = 0.18
    /// Small vertical slop above/below the visible labels so the rail
    /// stays comfortable to grab — but no further. The rail's hit area
    /// used to span the entire screen height (the scrub backdrop is a
    /// Shape, which greedily fills all proposed height), swallowing
    /// taps on the profile avatar in the hero's top-right corner.
    private let verticalHitSlop: CGFloat = 12

    var body: some View {
        // The interactive surface is sized to the visible labels (plus a
        // small slop), NOT the full screen height — so nothing above or
        // below the rail (like the profile avatar) loses its taps.
        VStack(spacing: 18) {
            ForEach(CirclesRailSection.allCases) { section in
                railItem(section)
            }
        }
        .padding(.trailing, 8)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { railHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in railHeight = h }
            }
        )
        .animation(.easeInOut(duration: 0.25), value: active)
        .padding(.vertical, verticalHitSlop)
        .frame(width: isScrubbing ? scrubExpandedWidth : railWidth, alignment: .trailing)
        // Scrub backdrop lives in .background so it can never inflate
        // the rail's layout (and therefore its hit area) beyond the
        // labels themselves.
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.textPrimary.opacity(isScrubbing ? 0.06 : 0))
                .frame(width: scrubExpandedWidth)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isScrubbing)
        .gesture(scrubGesture)
    }

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
                    let section = sectionForY(drag.location.y)
                    if section != lastScrubSection {
                        if lastScrubSection != nil {
                            boundaryHaptic.impactOccurred()
                            boundaryHaptic.prepare()
                        }
                        lastScrubSection = section
                        onScrub?(section)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                isScrubbing = false
                lastScrubSection = nil
            }
    }

    private func sectionForY(_ y: CGFloat) -> CirclesRailSection {
        let sections = CirclesRailSection.allCases
        let h = max(railHeight, 1)
        // The gesture's local space includes the vertical slop padding;
        // shift back into the labels' own coordinate space.
        let clamped = max(0, min(h, y - verticalHitSlop))
        let segment = Int((clamped / h) * CGFloat(sections.count))
        let idx = min(sections.count - 1, max(0, segment))
        return sections[idx]
    }

    @ViewBuilder
    private func railItem(_ section: CirclesRailSection) -> some View {
        let isActive = section == active
        Button {
            onTap(section)
        } label: {
            VStack(spacing: 8) {
                Text(section.rawValue)
                    .font(.sans(9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(isActive ? 1.0 : 0.25))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 14, height: 60)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.textPrimary.opacity(isActive ? 1.0 : 0.25))
                    .frame(width: 3, height: isActive ? 30 : 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(section.rawValue.capitalized))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    ZStack {
        Theme.warmWheat.ignoresSafeArea()
        HStack {
            Spacer()
            CirclesSideRailView(active: .friends, onTap: { _ in })
        }
    }
}
