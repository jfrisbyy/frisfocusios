//
//  ShareCompositionOverlayView.swift
//  FrisFocus
//
//  One overlay door for the share pipeline: switches a frozen
//  `ShareCardComposition` to the right card overlay — the day card
//  (sun mark, chips) or the milestone card (flag mark, title). The
//  camera, the preview, and the renderer all draw through this view so
//  the viewfinder, the 9:16 preview, and the export stay pixel-true.
//

import SwiftUI

struct ShareCompositionOverlayView: View {
    let composition: ShareCardComposition
    let mode: ShareOverlayMode
    let username: String
    var layer: ShareOverlayLayer = .all
    var showChipHint: Bool = false
    var onToggleChip: ((UUID) -> Void)? = nil
    var bottomPadding: CGFloat = 20

    var body: some View {
        switch composition {
        case .day(let context, let options):
            ShareOverlayView(
                context: context,
                options: options,
                mode: mode,
                username: username,
                layer: layer,
                showChipHint: showChipHint,
                onToggleChip: onToggleChip,
                bottomPadding: bottomPadding
            )

        case .milestone(let context, let options):
            MilestoneShareOverlayView(
                context: context,
                options: options,
                mode: mode,
                username: username,
                layer: layer,
                bottomPadding: bottomPadding
            )
        }
    }
}
