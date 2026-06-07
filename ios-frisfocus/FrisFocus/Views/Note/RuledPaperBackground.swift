//
//  RuledPaperBackground.swift
//  FrisFocus
//
//  Paper-cream background with subtle horizontal rule lines bleeding
//  through, mimicking journal paper.
//

import SwiftUI

struct RuledPaperBackground: View {
    private let lineSpacing: CGFloat = 29
    private let lineHeight: CGFloat = 1

    var body: some View {
        ZStack {
            Theme.paperCream

            GeometryReader { proxy in
                Canvas { context, size in
                    let lineColor = GraphicsContext.Shading.color(
                        Theme.textPrimary.opacity(0.05)
                    )

                    var y: CGFloat = 28
                    while y < size.height {
                        let lineRect = CGRect(x: 0, y: y, width: size.width, height: lineHeight)
                        context.fill(Path(lineRect), with: lineColor)
                        y += lineSpacing
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(false)
        }
    }
}
