//
//  EncouragementChipView.swift
//  FrisFocus
//
//  Smaller, more horizontal chip on the dusk background. Lives between
//  the circle cards and the footer.
//

import SwiftUI

struct EncouragementChipView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textCream)

            (Text("Aaron").font(.sans(12, weight: .semibold))
             + Text(" + 2 others tapped through on your week").font(.sans(12, weight: .regular)))
                .foregroundStyle(Theme.textCream)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.warmWheat.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.35), lineWidth: 0.5)
        )
    }
}

#Preview {
    ZStack {
        Theme.duskMid
        EncouragementChipView()
            .padding()
    }
}
