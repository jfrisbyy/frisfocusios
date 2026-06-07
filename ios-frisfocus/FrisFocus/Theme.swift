//
//  Theme.swift
//  FrisFocus
//
//  Color tokens and typography helpers. Defined as hex literals so the
//  rest of the app can reference them via `Theme.color.warmWheat` etc.
//

import SwiftUI

enum Theme {
    // MARK: - Backgrounds
    static let warmWheat = Color(hex: 0xFAF2E0)
    static let paperCream = Color(hex: 0xF5EBD0)

    // MARK: - Landscape (Warm Forest)
    static let skyDeep = Color(hex: 0x0F2802)
    static let skyMid = Color(hex: 0x173404)
    static let skyLow = Color(hex: 0x1F4407)
    static let ridgeFar = Color(hex: 0x27500A)
    static let ridgeMid = Color(hex: 0x3B6D11)
    static let ridgeNear = Color(hex: 0x639922)
    static let foregroundBand = Color(hex: 0x8FA53C)

    // MARK: - Sun
    static let sunCore = Color(hex: 0xFFE5A8)
    static let sunWarm = Color(hex: 0xFAC775)
    static let sunOuter = Color(hex: 0xEF9F27)
    static let sunShadow = Color(hex: 0xBA7517)

    // MARK: - Dusk
    static let duskLight = Color(hex: 0xD8B98A)
    static let duskMid = Color(hex: 0xB89A75)
    static let duskDeep = Color(hex: 0x8E7B60)

    // MARK: - Text
    static let textPrimary = Color(hex: 0x2C2C2A)
    static let textSecondary = Color(hex: 0x5F5E5A)
    static let textTertiary = Color(hex: 0x888780)
    static let textMuted = Color(hex: 0xB4B2A9)
    static let textCream = Color(hex: 0xFAEEDA)

    // MARK: - Category dots
    static let categorySpiritual = Color(hex: 0x7F77DD)
    static let categoryFitness = Color(hex: 0xD85A30)
    static let categoryHealth = Color(hex: 0x639922)
    static let categoryWork = Color(hex: 0x185FA5)
    static let categoryCreative = Color(hex: 0x993556)

    // MARK: - Status
    static let alertRed = Color(hex: 0xA32D2D)
    static let alertAmber = Color(hex: 0x854F0B)
    static let alertGreen = Color(hex: 0x3B6D11)

    // MARK: - Folder tints (note zone)
    static let folderSongsBg = Color(red: 127.0/255, green: 119.0/255, blue: 221.0/255).opacity(0.15)
    static let folderSongsText = Color(hex: 0x4A3F9E)
    static let folderPrayerBg = Color(red: 99.0/255, green: 153.0/255, blue: 34.0/255).opacity(0.15)
    static let folderPrayerText = Color(hex: 0x3B6D11)
    static let folderWorkBg = Color(red: 24.0/255, green: 95.0/255, blue: 165.0/255).opacity(0.15)
    static let folderWorkText = Color(hex: 0x185FA5)

    // MARK: - Spacing
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let pageHorizontalPadding: CGFloat = 22
    static let zoneVerticalGap: CGFloat = 28
}

// MARK: - Hex Color initializer
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// String-hex convenience used by Codable types that store colors as
    /// strings (e.g. `Friend.accentColorHex`). Accepts `#RRGGBB` or
    /// `RRGGBB`; falls back to charcoal text on a malformed input so a
    /// friend card never blanks out mid-render.
    init(hex: String, alpha: Double = 1.0) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            self.init(hex: 0x2C2C2A, alpha: alpha)
            return
        }
        self.init(hex: value, alpha: alpha)
    }
}

// MARK: - HSL interpolation
//
// Used by SkyPalette to crossfade between time-of-day keyframes in HSL
// rather than sRGB, so warm-to-cool transitions don't pass through a muddy
// grey mid-point.
extension Color {
    /// Linearly interpolate between two colors in HSL space.
    /// Hue uses the shorter path around the colour wheel.
    static func lerpHSL(_ a: Color, _ b: Color, t: Double) -> Color {
        let clamped = max(0.0, min(1.0, t))
        let lhs = a.hslComponents
        let rhs = b.hslComponents

        // Shorter arc around the hue wheel
        var dh = rhs.h - lhs.h
        if dh > 0.5 { dh -= 1.0 }
        if dh < -0.5 { dh += 1.0 }
        var h = lhs.h + dh * clamped
        if h < 0 { h += 1.0 }
        if h >= 1 { h -= 1.0 }

        let s = lhs.s + (rhs.s - lhs.s) * clamped
        let l = lhs.l + (rhs.l - lhs.l) * clamped
        let alpha = lhs.a + (rhs.a - lhs.a) * clamped

        return Color(hsl: (h: h, s: s, l: l, a: alpha))
    }

    /// Returns this color's H, S (HSL), L, and alpha components in 0...1.
    /// Converts from UIKit HSB internally.
    var hslComponents: (h: Double, s: Double, l: Double, a: Double) {
        let ui = UIColor(self)
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bright: CGFloat = 0
        var alpha: CGFloat = 0
        ui.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)

        // HSB → HSL (where lightness is the midpoint between min/max channel)
        let h = Double(hue)
        let l = (2.0 - Double(sat)) * Double(bright) / 2.0
        let s: Double
        if l <= 0 || l >= 1 {
            s = 0
        } else {
            s = (Double(bright) - l) / min(l, 1.0 - l)
        }
        return (h, s, l, Double(alpha))
    }

    init(hsl components: (h: Double, s: Double, l: Double, a: Double)) {
        // HSL → HSB so SwiftUI's Color(hue:saturation:brightness:) can render it.
        let s = max(0.0, min(1.0, components.s))
        let l = max(0.0, min(1.0, components.l))

        let bright = l + s * min(l, 1.0 - l)
        let satHSB: Double = bright == 0 ? 0 : 2.0 * (1.0 - l / bright)

        self.init(
            hue: components.h,
            saturation: max(0.0, min(1.0, satHSB)),
            brightness: max(0.0, min(1.0, bright)),
            opacity: max(0.0, min(1.0, components.a))
        )
    }
}

// MARK: - Typography helpers
extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func serifItalic(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Category + Tier UI bridges
//
// SwiftUI sugar on top of the pure-data enums in `Models.swift`. Lives
// here so `Models.swift` stays Foundation-only.

extension Category {
    /// The dot color used in card metadata rows.
    var color: Color {
        switch self {
        case .spiritual: return Theme.categorySpiritual
        case .fitness: return Theme.categoryFitness
        case .health: return Theme.categoryHealth
        case .work: return Theme.categoryWork
        case .creative: return Theme.categoryCreative
        case .apartment: return Theme.textTertiary
        }
    }

    /// A darker variant of the category color, used for legible text on
    /// tinted backgrounds (category pills, tier pills inside category
    /// sections). Each value is hand-tuned to read against a 15 %
    /// opacity wash of `color`.
    var darkColor: Color {
        switch self {
        case .spiritual: return Color(hex: 0x4A3F9E)
        case .creative:  return Color(hex: 0x72243E)
        case .fitness:   return Color(hex: 0x712B13)
        case .health:    return Color(hex: 0x3B6D11)
        case .work:      return Color(hex: 0x0C447C)
        case .apartment: return Theme.textSecondary
        }
    }
}

extension Tier {
    /// Uppercase pill label (`MUST`, `SHOULD`, `COULD`).
    var label: String {
        switch self {
        case .must: return "MUST"
        case .should: return "SHOULD"
        case .could: return "COULD"
        }
    }

    /// Pill text + tint for the metadata row.
    var color: Color {
        switch self {
        case .must: return Theme.alertRed
        case .should: return Theme.alertAmber
        case .could: return Theme.textSecondary
        }
    }
}

// MARK: - FolderColor palette
//
// SwiftUI Color values for each `FolderColor` case. Three slots per
// case so a folder reads consistently across surfaces:
//   • `dotColor`       — solid swatch for list rows and detail headers
//   • `pillBackground` — low-opacity tint for chip backgrounds
//   • `pillText`       — darker variant legible on top of the pill

extension FolderColor {
    /// The solid swatch shown as the small dot in folder lists and the
    /// large dot on the manage-folders edit drawer.
    var dotColor: Color {
        switch self {
        case .purple: return Color(hex: 0x7F77DD)
        case .green:  return Color(hex: 0x639922)
        case .blue:   return Color(hex: 0x185FA5)
        case .pink:   return Color(hex: 0x993556)
        case .orange: return Color(hex: 0xD85A30)
        case .amber:  return Color(hex: 0xBA7517)
        case .grey:   return Color(hex: 0x888780)
        case .dusk:   return Color(hex: 0xB89A75)
        }
    }

    /// Tinted background used inside folder chips and pills. Sits on
    /// the cream paper, so the 15 % opacity reads as a quiet wash.
    var pillBackground: Color {
        dotColor.opacity(0.15)
    }

    /// Hand-tuned darker variant for legible text on top of `pillBackground`.
    var pillText: Color {
        switch self {
        case .purple: return Color(hex: 0x4A3F9E)
        case .green:  return Color(hex: 0x3B6D11)
        case .blue:   return Color(hex: 0x0C447C)
        case .pink:   return Color(hex: 0x72243E)
        case .orange: return Color(hex: 0x712B13)
        case .amber:  return Color(hex: 0x854F0B)
        case .grey:   return Color(hex: 0x5F5E5A)
        case .dusk:   return Color(hex: 0x8E7B60)
        }
    }
}

// MARK: - Eyebrow label style
struct EyebrowText: View {
    let text: String
    var opacity: Double = 0.6
    var color: Color = Theme.textPrimary

    var body: some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .medium))
            .tracking(2)
            .foregroundStyle(color.opacity(opacity))
    }
}
