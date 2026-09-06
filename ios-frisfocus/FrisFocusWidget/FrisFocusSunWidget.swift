//
//  FrisFocusSunWidget.swift
//  FrisFocusWidget
//
//  Home-screen widget: today's completion painted onto the sun's arc.
//  The app writes a `WidgetSnapshot` into the shared App Group on every
//  plan change; this extension just draws the latest copy and refreshes
//  on a gentle 30-minute cadence between pushes. Tapping opens the app
//  on today's plan.
//

import SwiftUI
import WidgetKit

// MARK: - Shared snapshot (app-side twin lives in WidgetBridge.swift)

private nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var dayKey: String
    var doneCount: Int
    var totalCount: Int
    var sunRatio: Double
    var seasonName: String
    var nextTitle: String?
    var nextDetail: String?
    var updatedAt: Date
}

private nonisolated enum SunWidgetStore {
    static let appGroupId = "group.com.frisfocus.app"
    static let snapshotKey = "widgetSnapshot.v1"

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Timeline

private nonisolated struct SunEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private nonisolated struct SunProvider: TimelineProvider {
    func placeholder(in context: Context) -> SunEntry {
        SunEntry(date: Date(), snapshot: WidgetSnapshot(
            dayKey: SunWidgetStore.dayFormatter.string(from: Date()),
            doneCount: 2,
            totalCount: 5,
            sunRatio: 0.4,
            seasonName: "Season",
            nextTitle: "Morning run",
            nextDetail: "7:00–8:00 AM",
            updatedAt: Date()
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SunEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(SunEntry(date: Date(), snapshot: SunWidgetStore.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunEntry>) -> Void) {
        let snapshot = SunWidgetStore.load()
        let now = Date()
        // One entry every 30 minutes for the next 6 hours; the app also
        // pushes an immediate reload after every recorded change.
        var entries: [SunEntry] = []
        for step in 0..<12 {
            let date = now.addingTimeInterval(Double(step) * 30 * 60)
            entries.append(SunEntry(date: date, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Palette (widget-local copy of the app's cream world)

private enum SunTheme {
    static let cream = Color(red: 0.980, green: 0.949, blue: 0.878)      // #FAF2E0
    static let creamDeep = Color(red: 0.953, green: 0.910, blue: 0.800)  // #F3E8CC
    static let charcoal = Color(red: 0.173, green: 0.173, blue: 0.165)   // #2C2C2A
    static let sunGold = Color(red: 0.878, green: 0.639, blue: 0.204)    // #E0A334
    static let sunDeep = Color(red: 0.816, green: 0.525, blue: 0.153)    // #D08627
}

// MARK: - Widget

struct FrisFocusSunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FrisFocusSunWidget", provider: SunProvider()) { entry in
            SunWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [SunTheme.cream, SunTheme.creamDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .widgetURL(URL(string: "frisfocus://today"))
        }
        .configurationDisplayName("Today's sun")
        .description("Your plan's progress, painted on the sun's arc.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry view

private struct SunWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SunEntry

    /// Snapshot is only meaningful for the day it was written.
    private var isFreshDay: Bool {
        guard let snapshot = entry.snapshot else { return false }
        return snapshot.dayKey != SunWidgetStore.dayFormatter.string(from: entry.date)
    }

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private var ratio: Double {
        guard let snapshot, !isFreshDay else { return 0 }
        return min(1, max(0, snapshot.sunRatio))
    }

    private var headline: String {
        guard let snapshot, snapshot.totalCount > 0 else {
            return "No plan yet"
        }
        if isFreshDay { return "A new day is waiting" }
        let remaining = snapshot.totalCount - snapshot.doneCount
        if remaining <= 0 { return "All \(snapshot.totalCount) done" }
        if snapshot.doneCount == 0 {
            return remaining == 1 ? "1 thing today" : "\(remaining) things today"
        }
        return "\(snapshot.doneCount) done · \(remaining) to go"
    }

    private var subline: String {
        guard let snapshot, snapshot.totalCount > 0 else {
            return "Open FrisFocus to shape today"
        }
        if isFreshDay { return "Open the app to light it" }
        let remaining = snapshot.totalCount - snapshot.doneCount
        if remaining <= 0 { return "Golden hour" }
        return "The sun is waiting"
    }

    private var eyebrow: String {
        let name = snapshot?.seasonName ?? ""
        return name.isEmpty ? "FRISFOCUS" : name.uppercased()
    }

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(SunTheme.charcoal.opacity(0.45))
                .lineLimit(1)

            SunArcView(ratio: ratio)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 2)

            Text(headline)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(SunTheme.charcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subline)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(SunTheme.charcoal.opacity(0.55))
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            SunArcView(ratio: ratio)
                .frame(width: 118)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(SunTheme.charcoal.opacity(0.45))
                    .lineLimit(1)

                Text(headline)
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(SunTheme.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(subline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SunTheme.charcoal.opacity(0.55))
                    .lineLimit(1)

                if let snapshot, !isFreshDay,
                   snapshot.totalCount > snapshot.doneCount,
                   let next = snapshot.nextTitle {
                    HStack(spacing: 5) {
                        Circle()
                            .strokeBorder(SunTheme.charcoal.opacity(0.35), lineWidth: 1.4)
                            .frame(width: 11, height: 11)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(next)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(SunTheme.charcoal.opacity(0.85))
                                .lineLimit(1)
                            if let detail = snapshot.nextDetail {
                                Text(detail)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(SunTheme.charcoal.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 5)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sun arc

/// The day's arc: a faint track from horizon to horizon, the travelled
/// portion painted gold, and the sun disc sitting at the ratio point.
private struct SunArcView: View {
    let ratio: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let horizonY = h * 0.86
            let cx = w * 0.5
            let radius = min(w * 0.42, h * 0.72)

            func point(at t: Double) -> CGPoint {
                // t 0...1 sweeps left horizon → zenith → right horizon.
                let angle = Double.pi * (1 - t)
                return CGPoint(
                    x: cx + radius * Darwin.cos(angle),
                    y: horizonY - radius * Darwin.sin(angle)
                )
            }

            // Horizon line
            var horizon = Path()
            horizon.move(to: CGPoint(x: w * 0.04, y: horizonY))
            horizon.addLine(to: CGPoint(x: w * 0.96, y: horizonY))
            ctx.stroke(horizon, with: .color(SunTheme.charcoal.opacity(0.18)), lineWidth: 1)

            // Full track (faint, dashed)
            var track = Path()
            track.move(to: point(at: 0))
            for step in 1...60 {
                track.addLine(to: point(at: Double(step) / 60))
            }
            ctx.stroke(
                track,
                with: .color(SunTheme.charcoal.opacity(0.16)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.5, 4])
            )

            // Travelled portion — painted gold up to the ratio.
            let t = min(1, max(0, ratio))
            if t > 0.005 {
                var trail = Path()
                trail.move(to: point(at: 0))
                let steps = max(2, Int(60 * t))
                for step in 1...steps {
                    trail.addLine(to: point(at: (Double(step) / Double(steps)) * t))
                }
                ctx.stroke(
                    trail,
                    with: .linearGradient(
                        Gradient(colors: [SunTheme.sunDeep.opacity(0.55), SunTheme.sunGold]),
                        startPoint: point(at: 0),
                        endPoint: point(at: t)
                    ),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
            }

            // The sun disc (with a soft glow), resting on the horizon
            // when nothing is done yet.
            let sun = point(at: t)
            let glowRect = CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22)
            ctx.fill(Path(ellipseIn: glowRect), with: .color(SunTheme.sunGold.opacity(0.22)))
            let sunRect = CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)
            ctx.fill(
                Path(ellipseIn: sunRect),
                with: .radialGradient(
                    Gradient(colors: [SunTheme.sunGold, SunTheme.sunDeep]),
                    center: sun,
                    startRadius: 1,
                    endRadius: 7
                )
            )
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    FrisFocusSunWidget()
} timeline: {
    SunEntry(date: .now, snapshot: WidgetSnapshot(
        dayKey: SunWidgetStore.dayFormatter.string(from: .now),
        doneCount: 2, totalCount: 5, sunRatio: 0.4,
        seasonName: "Rebuild", nextTitle: "Morning run",
        nextDetail: "7:00–8:00 AM", updatedAt: .now
    ))
    SunEntry(date: .now, snapshot: nil)
}

#Preview("Medium", as: .systemMedium) {
    FrisFocusSunWidget()
} timeline: {
    SunEntry(date: .now, snapshot: WidgetSnapshot(
        dayKey: SunWidgetStore.dayFormatter.string(from: .now),
        doneCount: 4, totalCount: 4, sunRatio: 1.0,
        seasonName: "Rebuild", nextTitle: nil,
        nextDetail: nil, updatedAt: .now
    ))
}
