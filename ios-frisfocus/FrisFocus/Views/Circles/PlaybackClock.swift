//
//  PlaybackClock.swift
//  FrisFocus
//
//  Isolates the 25 Hz story/proof playback tick from the player's view
//  tree. `progress` lives in an @Observable box, so each timer tick
//  re-renders only the thin progress-bar leaf below — the full-screen
//  player (media layer, chrome, gesture surface, derived post queue)
//  is untouched until the segment actually advances. Before this, every
//  tick re-evaluated the whole player body 25×/sec, which made taps,
//  holds and swipes inside the players feel sluggish.
//

import SwiftUI

/// Mutable segment-progress box for timed players. Mutated by the
/// player's timer; observed only by the progress-bar leaves below.
@Observable
final class PlaybackClock {
    /// 0…1 fill of the current segment.
    var progress: Double = 0
}

/// Story-style segmented progress bars. Reads `clock.progress` so only
/// this view invalidates on each tick.
struct SegmentedProgressBars: View {
    let count: Int
    let currentIndex: Int
    let clock: PlaybackClock

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { idx in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.textCream.opacity(0.28))
                        Capsule()
                            .fill(Theme.textCream)
                            .frame(width: geo.size.width * fillFraction(for: idx))
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func fillFraction(for idx: Int) -> Double {
        if idx < currentIndex { return 1 }
        if idx == currentIndex { return min(1, max(0, clock.progress)) }
        return 0
    }
}

/// Single-segment bar for the one-proof player.
struct SingleSegmentBar: View {
    let clock: PlaybackClock

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textCream.opacity(0.28))
                Capsule()
                    .fill(Theme.textCream)
                    .frame(width: geo.size.width * min(1, max(0, clock.progress)))
            }
        }
        .frame(height: 2.5)
    }
}
