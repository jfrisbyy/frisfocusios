//
//  SignalZoneView.swift
//  FrisFocus
//
//  Zone 4 — dusk gradient background. The social feed peek.
//

import SwiftUI

struct SignalZoneView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.duskLight, location: 0.0),
                    .init(color: Theme.duskMid, location: 0.6),
                    .init(color: Theme.duskDeep, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 20) {
                ZoneHeaderView(
                    title: "The signal",
                    eyebrowRight: "Zone 4 of 4",
                    subline: "three of yours showed up today",
                    textColor: Theme.textCream,
                    dim: 0.65
                )
                .padding(.top, 28)

                VStack(spacing: 10) {
                    ForEach(SampleData.circleEntries) { entry in
                        CircleEntryCardView(entry: entry)
                    }
                }

                EncouragementChipView()
                    .padding(.top, 2)

                // Footer row
                HStack {
                    Text("SideQuest Soldiers · 6 active")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.75))

                    Spacer()

                    HStack(spacing: 4) {
                        Text("open Circles")
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Theme.textCream)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textCream)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }
}

#Preview {
    SignalZoneView()
}
