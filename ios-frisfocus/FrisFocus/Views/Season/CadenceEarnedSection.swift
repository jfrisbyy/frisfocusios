//
//  CadenceEarnedSection.swift
//  FrisFocus
//
//  The "EARNED FROM CADENCE" block in the inline season detail (inside
//  the Sun zone). Passive outcomes — sleep, focus, wind-down timing —
//  live here, not in Today's Plan, because they're things that happen,
//  not chores you check off. Each row fills itself from a verified
//  Cadence outcome event and shows fulfilled ("✓ 6h 40m last night",
//  points in green) or pending ("waiting on tonight", dimmed).
//
//  The section renders glass-on-sky (cream ink, translucent fills);
//  `CadenceOutcomeRow` keeps a paper appearance by default because the
//  link-flow preview still shows it on cream.
//

import SwiftUI

struct CadenceEarnedSection: View {
    @Environment(Store.self) private var store

    var body: some View {
        let links = store.passiveCadenceLinks(forSeason: store.currentSeason.id)
        if store.cadenceConnected, !links.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.cadenceLavender)
                    Text("EARNED FROM CADENCE")
                        .font(.sans(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.cadenceLavender)
                }

                VStack(spacing: 10) {
                    ForEach(links) { link in
                        CadenceOutcomeRow(link: link, onSky: true)
                    }
                }

                Text("These fill themselves from what Cadence actually records. Nothing to check — just live your night.")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.6))
                    .lineSpacing(2)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
        }
    }
}

// MARK: - Outcome row (shared with the link-flow preview)

/// One passive-outcome row. Fulfilled shows the recorded summary + the
/// credited points in green; pending is dim with a dashed border.
struct CadenceOutcomeRow: View {
    @Environment(Store.self) private var store
    let link: CadenceLink

    /// When true the row is a static preview (link form) — always pending.
    var isPreview: Bool = false
    /// Glass-on-sky appearance for the inline season detail. The
    /// default paper styling remains for the link-flow preview.
    var onSky: Bool = false

    /// Primary ink — charcoal on paper, cream on the sky.
    private var ink: Color { onSky ? Theme.textCream : Theme.textPrimary }
    /// Fulfilled green that stays legible on the deep sky.
    private var fulfilledGreen: Color { onSky ? Color(hex: 0x9BC25B) : Theme.alertGreen }
    private var lavenderInk: Color { onSky ? Theme.cadenceLavender : Theme.cadenceLavenderDark }

    private var fulfillment: CadenceOutcomeFulfillment? {
        guard !isPreview else { return nil }
        return store.latestCadenceFulfillment(for: link)
    }

    private var isFulfilled: Bool { fulfillment != nil }

    private var cappedPoints: Int {
        min(max(link.points, 0), CadenceLink.pointCeiling)
    }

    private var waitingWord: String {
        switch link.outcomeKind {
        case .focusBlock: return "today"
        default: return "tonight"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.cadenceLavender.opacity(isFulfilled ? 0.18 : 0.10))
                Image(systemName: link.outcomeKind?.icon ?? "moon.stars.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isFulfilled ? lavenderInk : lavenderInk.opacity(0.55))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayTitle)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(ink.opacity(isFulfilled ? 1.0 : 0.7))

                if let fill = fulfillment {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(fill.summary)
                            .font(.sans(11, weight: .medium))
                    }
                    .foregroundStyle(fulfilledGreen)
                } else {
                    Text("waiting on \(waitingWord)")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(ink.opacity(0.45))
                }
            }

            Spacer(minLength: 8)

            Text("+\(fulfillment?.points ?? cappedPoints)")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(isFulfilled ? fulfilledGreen : ink.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            onSky
                ? Color.white.opacity(isFulfilled ? 0.14 : 0.07)
                : (isFulfilled ? Color.white : Color.white.opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    onSky
                        ? (isFulfilled ? Theme.cadenceLavender.opacity(0.35) : Color.white.opacity(0.22))
                        : (isFulfilled ? Theme.cadenceLavender.opacity(0.22) : Theme.textPrimary.opacity(0.18)),
                    style: isFulfilled
                        ? StrokeStyle(lineWidth: 0.5)
                        : StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isFulfilled)
    }
}

#Preview {
    let store = Store()
    return ScrollView {
        CadenceEarnedSection()
    }
    .background(Theme.skyDeep)
    .environment(store)
}
