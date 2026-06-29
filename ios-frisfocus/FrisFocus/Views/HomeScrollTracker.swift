//
//  HomeScrollTracker.swift
//  FrisFocus
//
//  Isolates the home screen's scroll/zone bookkeeping into a single
//  @Observable so updating the side rail's active zone + progress never
//  invalidates the heavy page content underneath it.
//
//  Zone tops/heights are measured ONCE in the content's own coordinate
//  space (stable during scroll), and the live scroll offset arrives via
//  `onScrollGeometryChange`. Recomputing active zone + progress from
//  those numbers is cheap and only re-renders the small rail.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class HomeScrollTracker {
    /// The zone the user has most recently scrolled into. Drives the
    /// rail's highlight + tint.
    private(set) var activeZone: HomeZone = .sun
    /// 0...1 progress through the active zone — drives the rail fill.
    private(set) var progress: Double = 0

    /// Total scrollable content + viewport heights, used by the parent's
    /// rail scrub to map a 0...1 fraction onto a real offset.
    private(set) var contentHeight: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0

    /// Live vertical scroll offset (content-space top = 0).
    private var scrollY: CGFloat = 0
    /// Stable per-zone tops + heights in the content's coordinate space.
    private var zoneTops: [HomeZone: CGFloat] = [:]
    private var zoneHeights: [HomeZone: CGFloat] = [:]

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    func prepareHaptics() {
        haptic.prepare()
    }

    /// Record a zone's measured top + height (content-space). Ignores
    /// sub-point jitter so a stray relayout doesn't churn the rail.
    func updateZoneFrame(_ zone: HomeZone, top: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        if let pt = zoneTops[zone], let ph = zoneHeights[zone],
           abs(pt - top) < 0.5, abs(ph - height) < 0.5 {
            return
        }
        zoneTops[zone] = top
        zoneHeights[zone] = height
        recompute()
    }

    /// Feed the latest scroll geometry. Called every frame while
    /// scrolling, but only mutates the tiny rail state.
    func updateScroll(offsetY: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        scrollY = offsetY
        recompute()
    }

    private func recompute() {
        // Active zone = the last one whose top we've scrolled past.
        var newActive: HomeZone = .sun
        for zone in HomeZone.allCases {
            guard let top = zoneTops[zone], let h = zoneHeights[zone], h > 0 else { continue }
            if scrollY >= top - 0.5 {
                newActive = zone
            }
        }

        let top = zoneTops[newActive] ?? 0
        let h = max(zoneHeights[newActive] ?? 1, 1)
        let newProgress = max(0.0, min(1.0, Double((scrollY - top) / h)))
        if abs(newProgress - progress) > 0.0005 {
            progress = newProgress
        }

        if newActive != activeZone {
            activeZone = newActive
            haptic.impactOccurred()
            haptic.prepare()
        }
    }
}
