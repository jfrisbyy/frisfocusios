//
//  SeamView.swift
//  FrisFocus
//
//  Simple gradient seams between zones (Work→Note, Note→Signal).
//

import SwiftUI

struct GradientSeam: View {
    let topColor: Color
    let bottomColor: Color
    var height: CGFloat = 30

    var body: some View {
        LinearGradient(
            colors: [topColor, bottomColor],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
    }
}
