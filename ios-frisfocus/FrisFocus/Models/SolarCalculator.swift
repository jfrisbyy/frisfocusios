//
//  SolarCalculator.swift
//  FrisFocus
//
//  Pure-math sunrise / sunset times for a given coordinate and date.
//  Based on the "Sunrise/Sunset Algorithm" published by the U.S. Naval
//  Observatory (Almanac for Computers, 1990). Accurate to a few minutes,
//  which is plenty for choosing how to paint the sky.
//
//  Returns nil for polar days/nights where the sun never rises or never
//  sets — callers fall back to fixed 6:30 / 20:30 in that case.
//

import Foundation

nonisolated enum SolarCalculator {

    /// Civil zenith — sun's centre is 0.833° below the horizon when it
    /// "rises" or "sets" (accounts for atmospheric refraction).
    private static let officialZenith: Double = 90.833

    /// Returns the sunrise and sunset for `date` at the given coordinate
    /// in the device's current timezone. Returns nil if the calculation
    /// fails or the sun doesn't rise/set on this day at this latitude.
    static func sunriseSunset(
        for date: Date,
        latitude: Double,
        longitude: Double
    ) -> (sunrise: Date, sunset: Date)? {
        guard let utRise = utHour(for: date, latitude: latitude, longitude: longitude, rising: true),
              let utSet  = utHour(for: date, latitude: latitude, longitude: longitude, rising: false)
        else {
            return nil
        }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        // The UT hours are wrapped to 0–24, so the event may actually
        // belong to the UTC day before or after the user's local day
        // (e.g. an 8:27 PM EDT sunset is 00:27 UTC *tomorrow*). Naively
        // pinning both onto today's UTC day puts sunset ~24 h before
        // sunrise in the Americas, or sunrise a day ahead far east of
        // UTC. Resolve each event onto whichever adjacent UTC day makes
        // it land inside the user's local calendar day.
        guard let sunrise = resolveToLocalDay(utHour: utRise, near: date, utcCalendar: utcCal),
              let sunset  = resolveToLocalDay(utHour: utSet,  near: date, utcCalendar: utcCal),
              sunset > sunrise
        else {
            return nil
        }

        return (sunrise, sunset)
    }

    /// Tries the UTC day of `date` and its neighbours, returning the
    /// candidate that falls on the same *local* calendar day as `date`.
    private static func resolveToLocalDay(
        utHour: Double,
        near date: Date,
        utcCalendar: Calendar
    ) -> Date? {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = .current

        for dayOffset in [-1, 0, 1] {
            guard let shifted = utcCalendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            let dayComponents = utcCalendar.dateComponents([.year, .month, .day], from: shifted)
            guard let candidate = makeDate(
                utHour: utHour,
                dayComponents: dayComponents,
                calendar: utcCalendar
            ) else {
                continue
            }
            if localCal.isDate(candidate, inSameDayAs: date) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Math

    private static func utHour(
        for date: Date,
        latitude: Double,
        longitude: Double,
        rising: Bool
    ) -> Double? {
        let calendar = Calendar(identifier: .gregorian)
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else {
            return nil
        }
        let N = Double(dayOfYear)

        // 2. Longitude → hours
        let lngHour = longitude / 15.0

        // 3. Approximate time
        let t: Double = rising
            ? N + ((6.0 - lngHour) / 24.0)
            : N + ((18.0 - lngHour) / 24.0)

        // 4. Sun's mean anomaly
        let M = (0.9856 * t) - 3.289

        // 5. Sun's true longitude
        var L = M
            + (1.916 * sin(M.degreesToRadians))
            + (0.020 * sin((2.0 * M).degreesToRadians))
            + 282.634
        L = wrap(L, lower: 0.0, upper: 360.0)

        // 6. Sun's right ascension
        var RA = atan(0.91764 * tan(L.degreesToRadians)).radiansToDegrees
        RA = wrap(RA, lower: 0.0, upper: 360.0)

        // 6b. RA must be in the same quadrant as L
        let lQuadrant  = floor(L  / 90.0) * 90.0
        let raQuadrant = floor(RA / 90.0) * 90.0
        RA = RA + (lQuadrant - raQuadrant)
        RA = RA / 15.0

        // 7. Sun's declination
        let sinDec = 0.39782 * sin(L.degreesToRadians)
        let cosDec = cos(asin(sinDec))

        // 8. Sun's local hour angle
        let cosH = (cos(officialZenith.degreesToRadians) - (sinDec * sin(latitude.degreesToRadians)))
                 / (cosDec * cos(latitude.degreesToRadians))
        if cosH > 1.0 || cosH < -1.0 {
            // Polar day or polar night.
            return nil
        }

        var H = acos(cosH).radiansToDegrees
        if rising {
            H = 360.0 - H
        }
        H = H / 15.0

        // 9. Local mean time of rising / setting
        let T = H + RA - (0.06571 * t) - 6.622

        // 10. Adjust to UTC
        var UT = T - lngHour
        UT = wrap(UT, lower: 0.0, upper: 24.0)

        return UT
    }

    private static func makeDate(
        utHour: Double,
        dayComponents: DateComponents,
        calendar: Calendar
    ) -> Date? {
        let totalSeconds = Int((utHour * 3600.0).rounded())
        let hour = (totalSeconds / 3600) % 24
        let minute = (totalSeconds % 3600) / 60
        let second = totalSeconds % 60

        var components = dayComponents
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    private static func wrap(_ value: Double, lower: Double, upper: Double) -> Double {
        let range = upper - lower
        var result = value
        while result < lower { result += range }
        while result >= upper { result -= range }
        return result
    }
}

// MARK: - Angle helpers

nonisolated private extension Double {
    var degreesToRadians: Double { self * .pi / 180.0 }
    var radiansToDegrees: Double { self * 180.0 / .pi }
}
