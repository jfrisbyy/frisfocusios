//
//  CircleStoryStrip.swift
//  FrisFocus
//
//  The watchable group-story tile that sits under "The circle today"
//  on a parallel circle's detail page when at least one member has
//  posted a clip today. Warm gradient, a centered play button,
//  `{N} ran today · watch the story`, and a small duration pill. Only
//  surfaced when there is real material to watch — the parent owns
//  the conditional so the strip never lies about its content.
//
//  Tapping fires the parent's callback; today that opens a placeholder
//  sheet until C9b lands the real group-story viewer.
//

import SwiftUI

struct CircleStoryStrip: View {
    let memberCount: Int
    /// Every clip today has been played — the tile mutes into a
    /// "watched · replay" state instead of looking like fresh news.
    var isWatched: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                playGlyph

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.sans(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.textCream.opacity(0.78))

                    Text(headline)
                        .font(.serif(15, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                durationPill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isWatched
                ? "Replay today's circle story"
                : "Watch today's circle story, \(memberCount) \(memberCount == 1 ? "person" : "people")"
        )
    }

    private var eyebrow: String {
        isWatched ? "TODAY \u{00B7} WATCHED" : "TODAY \u{00B7} GROUP STORY"
    }

    private var headline: String {
        if isWatched {
            return "Watched \u{00B7} replay today's story"
        }
        let verb = memberCount == 1 ? "ran today" : "ran today"
        return "\(memberCount) \(verb) \u{00B7} watch the story"
    }

    private var playGlyph: some View {
        ZStack {
            Circle()
                .fill(Theme.textCream.opacity(0.16))
            Circle()
                .strokeBorder(Theme.textCream.opacity(0.4), lineWidth: 0.6)
            Image(systemName: isWatched ? "arrow.counterclockwise" : "play.fill")
                .font(.sans(13, weight: .bold))
                .foregroundStyle(Theme.textCream)
                .offset(x: isWatched ? 0 : 1)
        }
        .frame(width: 36, height: 36)
    }

    private var durationPill: some View {
        Text(approximateDuration)
            .font(.sans(10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(0.25), lineWidth: 0.5)
            )
    }

    /// A coarse running-length estimate so the pill reads as a real
    /// duration without claiming precision. Five seconds per clip is
    /// the rough cap the future C9 player will enforce.
    private var approximateDuration: String {
        let seconds = max(memberCount, 1) * 5
        if seconds < 60 {
            return "0:\(String(format: "%02d", seconds))"
        }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    private var background: some View {
        LinearGradient(
            colors: isWatched
                ? [
                    Color(red: 216.0/255, green: 125.0/255, blue: 68.0/255).opacity(0.45),
                    Color(red: 178.0/255, green: 90.0/255, blue: 44.0/255).opacity(0.45)
                ]
                : [
                    Color(red: 216.0/255, green: 125.0/255, blue: 68.0/255),
                    Color(red: 178.0/255, green: 90.0/255, blue: 44.0/255)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        CircleStoryStrip(memberCount: 1, onTap: {})
        CircleStoryStrip(memberCount: 3, onTap: {})
    }
    .padding()
    .background(Theme.warmWheat)
}
