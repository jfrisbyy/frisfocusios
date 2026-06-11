//
//  PastDayBanner.swift
//  FrisFocus
//
//  The slim floating "viewing a past day" pill that rides on top of the
//  real homescreen while the time machine is engaged. The home itself
//  transforms in place (every zone reads `store.displayedDay`); this
//  banner is the only extra chrome — a clear marker plus one tap back
//  to today.
//

import SwiftUI
import UIKit

struct PastDayBanner: View {
    let day: Date
    let onBackToToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textCream)

            VStack(alignment: .leading, spacing: 0) {
                Text("VIEWING A PAST DAY")
                    .font(.sans(8.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textCream.opacity(0.7))
                Text(bannerDate)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }

            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onBackToToday()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back to today")
                        .font(.sans(12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x2C2C2A))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Theme.textCream))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to today")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(Color(hex: 0x2C2C2A).opacity(0.92))
        )
        .overlay(
            Capsule().strokeBorder(Theme.textCream.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var bannerDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: day)
    }
}
