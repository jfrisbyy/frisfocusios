//
//  WeekStripeView.swift
//  FrisFocus
//
//  7-segment week stripe. Days are passed in as opacities (top-right
//  corner of the Sun zone). Right-aligned, 60pt wide × 3pt tall.
//

import SwiftUI

struct WeekStripeView: View {
    /// Opacity for each of the 7 days (left = Monday). Hardcoded by caller.
    let dayOpacities: [Double]

    private let totalWidth: CGFloat = 60
    private let height: CGFloat = 3
    private let gap: CGFloat = 2

    var body: some View {
        let segmentWidth = (totalWidth - gap * CGFloat(dayOpacities.count - 1)) / CGFloat(dayOpacities.count)

        HStack(spacing: gap) {
            ForEach(Array(dayOpacities.enumerated()), id: \.offset) { _, opacity in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.textCream.opacity(opacity))
                    .frame(width: segmentWidth, height: height)
            }
        }
        .frame(width: totalWidth, alignment: .trailing)
    }
}

#Preview {
    ZStack {
        Theme.skyDeep.ignoresSafeArea()
        WeekStripeView(dayOpacities: [0.9, 0.65, 0.8, 0.9, 0.15, 0.15, 0.15])
    }
}
