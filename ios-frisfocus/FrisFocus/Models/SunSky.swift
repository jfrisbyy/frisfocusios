//
//  SunSky.swift
//  FrisFocus
//
//  A pure value that captures everything about "where the sun is and how
//  the sky looks right now". Built from the current time + optional
//  device coordinate. Views can re-create it on every render — there's
//  no internal state and no notification mechanism.
//
//  Day progress runs 0 at sunrise → 1 at sunset. Before sunrise or after
//  sunset we clamp, so the sky reads as dawn or dusk respectively.
//

import CoreLocation
import Foundation
import SwiftUI

struct SunSky {
    /// Current device time. Drives both palette and sun position.
    let currentTime: Date

    /// Sunrise / sunset for `currentTime`. Real if a coordinate was
    /// available; otherwise the 6:30 / 20:30 fallback for this day.
    let sunrise: Date
    let sunset: Date

    /// Whether the times came from real geo data or the fallback.
    let usesRealCoordinate: Bool

    // MARK: - Factories

    /// Build a SunSky for the given time, using the coordinate if
    /// available. Silently falls back to fixed 6:30 / 20:30 on failure.
    static func make(now: Date, coordinate: CLLocationCoordinate2D?) -> SunSky {
        let (sunrise, sunset, real) = computeSunriseSunset(now: now, coordinate: coordinate)
        return SunSky(
            currentTime: now,
            sunrise: sunrise,
            sunset: sunset,
            usesRealCoordinate: real
        )
    }

    private static func computeSunriseSunset(
        now: Date,
        coordinate: CLLocationCoordinate2D?
    ) -> (sunrise: Date, sunset: Date, real: Bool) {
        if let coord = coordinate,
           let result = SolarCalculator.sunriseSunset(
            for: now,
            latitude: coord.latitude,
            longitude: coord.longitude
           ) {
            return (result.sunrise, result.sunset, true)
        }

        // Fallback: 6:30 AM → 8:30 PM local for the same calendar day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = cal.dateComponents([.year, .month, .day], from: now)

        var rise = day
        rise.hour = 6
        rise.minute = 30

        var set = day
        set.hour = 20
        set.minute = 30

        let sunrise = cal.date(from: rise) ?? now
        let sunset = cal.date(from: set) ?? now.addingTimeInterval(14 * 3600)
        return (sunrise, sunset, false)
    }

    // MARK: - Day progress

    /// 0 at sunrise, 1 at sunset. Clamped before sunrise and after sunset
    /// so the sky reads as dawn / dusk respectively.
    var dayProgress: Double {
        let span = sunset.timeIntervalSince(sunrise)
        guard span > 0 else { return 0.5 }
        let elapsed = currentTime.timeIntervalSince(sunrise)
        return max(0.0, min(1.0, elapsed / span))
    }

    /// The palette interpolated to this exact moment of the day.
    var palette: SkyPalette {
        SkyPalette.interpolated(progress: dayProgress)
    }

    // MARK: - Sun position

    /// Returns the sun's center position inside a Sun-zone frame of the
    /// given size.
    ///
    /// The sweep is intentionally wide so the sun visibly drifts across
    /// the sky as the day progresses:
    ///   x: ~8 % from left at sunrise → ~92 % at sunset (linear)
    ///   y: parabolic — low at sunrise/sunset, high at midday
    ///
    /// At midday the peak is pulled to a comfortable mid-upper position
    /// where the entire disc sits inside the visible Sun zone (clear of
    /// the Dynamic Island / status bar) while still leaving the score
    /// headline below it unobstructed. The score is nudged down at
    /// midday by `SunZoneView` so the two never collide.
    func sunPosition(in size: CGSize) -> CGPoint {
        let progress = dayProgress

        let xMin: CGFloat = size.width * 0.08
        let xMax: CGFloat = size.width * 0.92
        let x = xMin + (xMax - xMin) * CGFloat(progress)

        let yLow: CGFloat = size.height * 0.82
        let yHigh: CGFloat = size.height * 0.30
        let arcLift = sin(progress * .pi)
        let y = yLow - (yLow - yHigh) * CGFloat(arcLift)

        return CGPoint(x: x, y: y)
    }

    /// How close we are to solar noon — 0 at sunrise/sunset, 1 at midday.
    /// Matches `sin(dayProgress * π)`, the same curve that drives the
    /// sun's vertical position, so views can blend behaviour with the
    /// sun's height in the sky.
    var middayProximity: Double {
        sin(dayProgress * .pi)
    }
}

// MARK: - Environment

private struct SunSkyEnvironmentKey: EnvironmentKey {
    static let defaultValue: SunSky = .make(now: Date(), coordinate: nil)
}

extension EnvironmentValues {
    /// The current SunSky, propagated from HomeView to every Sun-zone
    /// child so they don't all need to recompute the palette themselves.
    var sunSky: SunSky {
        get { self[SunSkyEnvironmentKey.self] }
        set { self[SunSkyEnvironmentKey.self] = newValue }
    }
}
