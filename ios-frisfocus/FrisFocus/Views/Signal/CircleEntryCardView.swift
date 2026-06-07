//
//  CircleEntryCardView.swift
//  FrisFocus
//
//  Nearly-opaque cream card sitting on the dusk gradient. Avatar circle
//  on the left, name+meta line, optional flame, status copy below.
//

import SwiftUI

struct CircleEntryCardView: View {
    let entry: CircleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(entry.avatarColor)
                        .frame(width: 28, height: 28)
                    Text(entry.initial)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("· \(entry.dayScore) today · \(entry.season)")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                }

                Spacer(minLength: 4)

                if entry.hasFlame {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.sunShadow)
                }
            }

            Text(entry.status)
                .font(.sans(13, weight: .regular))
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.warmWheat.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Theme.duskLight, Theme.duskMid, Theme.duskDeep],
            startPoint: .top,
            endPoint: .bottom
        )
        VStack(spacing: 10) {
            CircleEntryCardView(entry: SampleData.circleEntries[0])
            CircleEntryCardView(entry: SampleData.circleEntries[1])
        }
        .padding()
    }
}
