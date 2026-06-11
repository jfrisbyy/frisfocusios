//
//  PastDayHomeView.swift
//  FrisFocus
//
//  The home-screen time machine. When the user taps a past date in the
//  day picker, the whole home is replaced by this snapshot of that day:
//  a warm header band evoking the Sun zone (with the day's score), then
//  the full day record — what happened, the tasks pinned that day, the
//  to-dos, the notes, and milestone movement. A quiet banner up top
//  makes it obvious you're in the past, with one tap back to today.
//
//  Edits are still allowed but every change confirms first (handled by
//  `PastDaySnapshotView`), so history is never altered by accident.
//

import SwiftUI
import UIKit

struct PastDayHomeView: View {
    @Environment(Store.self) private var store
    let day: Date

    private var onBackToToday: () -> Void

    init(day: Date, onBackToToday: @escaping () -> Void) {
        self.day = day
        self.onBackToToday = onBackToToday
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.warmWheat.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    sunBand
                    PastDaySnapshotView(date: day)
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 60)
                }
            }
            .ignoresSafeArea(edges: .top)

            banner
                .padding(.top, safeTop + 8)
                .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }

    // MARK: - Banner

    private var banner: some View {
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
    }

    // MARK: - Sun band

    private var sunBand: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xE9A14B),
                    Color(hex: 0xD87D44),
                    Color(hex: 0x9C5B3C)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            FilmGrainView(strength: 0.2)
                .allowsHitTesting(false)

            VStack(spacing: 6) {
                Spacer(minLength: 0)

                Text(eyebrowDate)
                    .font(.sans(10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.85))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(store.score(on: day))")
                        .font(.serif(64, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                    Text("/ \(store.currentSeason.dailyGoal)")
                        .font(.serif(22, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                }

                Text("how this day landed")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                    .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
            .padding(.top, safeTop + 56)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 320 + safeTop)
    }

    // MARK: - Helpers

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top ?? 47
    }

    private var bannerDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: day)
    }

    private var eyebrowDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: day).uppercased()
    }
}
