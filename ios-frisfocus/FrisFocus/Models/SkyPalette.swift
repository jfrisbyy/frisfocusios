//
//  SkyPalette.swift
//  FrisFocus
//
//  The full set of colors that paint the Sun zone — sky gradient, sun,
//  ridges, mountains, foreground band — captured as a single immutable
//  value so the Sun zone can be repainted by handing it a different
//  palette.
//
//  Four keyframes are defined: dawn, midMorning, afternoon, dusk. The
//  `interpolated(progress:)` factory crossfades between them in HSL,
//  matching the four reference states in the locked design.
//
//  Keyframes are anchored at progress values matching a typical 6:30 AM
//  to 8:30 PM day:
//    progress 0.00  → dawn       (~6:30 AM)
//    progress 0.25  → midMorning (~10:00 AM)
//    progress 0.65  → afternoon  (~3:30 PM)
//    progress 1.00  → dusk       (~7:45-8:30 PM)
//

import SwiftUI

struct SkyPalette {
    /// Sky gradient stops, top → bottom. Always 4 entries so dawn/dusk
    /// can carry their full vertical band.
    let skyStops: [Color]

    // Sun
    let sunCore: Color
    let sunWarm: Color
    let sunOuter: Color
    let halo: Color

    // Landscape (back → front)
    let mountainShadow: Color   // distant jagged peaks behind the ridges
    let ridgeFar: Color
    let ridgeMid: Color
    let ridgeNear: Color
    let foregroundBand: Color   // the band that bleeds into the warm wheat below
}

// MARK: - Keyframes

extension SkyPalette {
    /// ~6:30 AM. Cool navy → mauve → warm horizon, peachy sun, blue-grey mountains.
    static let dawn = SkyPalette(
        skyStops: [
            Color(hex: 0x1B2842),
            Color(hex: 0x2D3B5C),
            Color(hex: 0x5A5878),
            Color(hex: 0x8E7560)
        ],
        sunCore: Color(hex: 0xFFE5B8),
        sunWarm: Color(hex: 0xFFD088),
        sunOuter: Color(hex: 0xE89548),
        halo: Color(hex: 0xFFD088),
        mountainShadow: Color(hex: 0x14223A),
        ridgeFar: Color(hex: 0x1F2840),
        ridgeMid: Color(hex: 0x26384A),
        ridgeNear: Color(hex: 0x2E4A50),
        foregroundBand: Color(hex: 0x445E4E)
    )

    /// ~10:00 AM. Warm Forest greens, bright cream-warm sun.
    static let midMorning = SkyPalette(
        skyStops: [
            Color(hex: 0x0F2802),
            Color(hex: 0x173404),
            Color(hex: 0x224009),
            Color(hex: 0x2A4F0C)
        ],
        sunCore: Color(hex: 0xFFF4D6),
        sunWarm: Color(hex: 0xFFE5A8),
        sunOuter: Color(hex: 0xFAC775),
        halo: Color(hex: 0xFAC775),
        mountainShadow: Color(hex: 0x0F2802),
        ridgeFar: Color(hex: 0x27500A),
        ridgeMid: Color(hex: 0x3B6D11),
        ridgeNear: Color(hex: 0x639922),
        foregroundBand: Color(hex: 0x8FA53C)
    )

    /// ~3:30 PM. Default state for the hardcoded 32/50 view. Deeper green
    /// sky, warm full sun, full Warm Forest ridges.
    static let afternoon = SkyPalette(
        skyStops: [
            Color(hex: 0x0F2802),
            Color(hex: 0x1F4407),
            Color(hex: 0x2E5A0E),
            Color(hex: 0x3B6D11)
        ],
        sunCore: Color(hex: 0xFFF4D6),
        sunWarm: Color(hex: 0xFFE5A8),
        sunOuter: Color(hex: 0xFAC775),
        halo: Color(hex: 0xFAC775),
        mountainShadow: Color(hex: 0x1A3F0A),
        ridgeFar: Color(hex: 0x27500A),
        ridgeMid: Color(hex: 0x3B6D11),
        ridgeNear: Color(hex: 0x639922),
        foregroundBand: Color(hex: 0x8FA53C)
    )

    /// ~7:45 PM. Purple-rose-amber sky, ember sun, rust-tinted ground.
    static let dusk = SkyPalette(
        skyStops: [
            Color(hex: 0x2A1F38),
            Color(hex: 0x4D2E48),
            Color(hex: 0x8E5040),
            Color(hex: 0xC97540)
        ],
        sunCore: Color(hex: 0xFFD088),
        sunWarm: Color(hex: 0xF29850),
        sunOuter: Color(hex: 0xC9602A),
        halo: Color(hex: 0xF29850),
        mountainShadow: Color(hex: 0x1F1428),
        ridgeFar: Color(hex: 0x3D2030),
        ridgeMid: Color(hex: 0x4A2820),
        ridgeNear: Color(hex: 0x5E3820),
        foregroundBand: Color(hex: 0x7C4A28)
    )
}

// MARK: - Interpolation

extension SkyPalette {
    /// Returns the palette for a given day-progress (0 at sunrise, 1 at
    /// sunset). Interpolates in HSL between the four keyframes.
    static func interpolated(progress: Double) -> SkyPalette {
        let p = max(0.0, min(1.0, progress))

        if p < 0.25 {
            let t = p / 0.25
            return lerp(.dawn, .midMorning, t: t)
        } else if p < 0.65 {
            let t = (p - 0.25) / 0.40
            return lerp(.midMorning, .afternoon, t: t)
        } else {
            let t = (p - 0.65) / 0.35
            return lerp(.afternoon, .dusk, t: t)
        }
    }

    /// Linear HSL interpolation between two palettes.
    static func lerp(_ a: SkyPalette, _ b: SkyPalette, t: Double) -> SkyPalette {
        let mix = { (lhs: Color, rhs: Color) in Color.lerpHSL(lhs, rhs, t: t) }
        let skyStops = zip(a.skyStops, b.skyStops).map { mix($0.0, $0.1) }

        return SkyPalette(
            skyStops: skyStops,
            sunCore: mix(a.sunCore, b.sunCore),
            sunWarm: mix(a.sunWarm, b.sunWarm),
            sunOuter: mix(a.sunOuter, b.sunOuter),
            halo: mix(a.halo, b.halo),
            mountainShadow: mix(a.mountainShadow, b.mountainShadow),
            ridgeFar: mix(a.ridgeFar, b.ridgeFar),
            ridgeMid: mix(a.ridgeMid, b.ridgeMid),
            ridgeNear: mix(a.ridgeNear, b.ridgeNear),
            foregroundBand: mix(a.foregroundBand, b.foregroundBand)
        )
    }
}
