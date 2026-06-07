//
//  FrisFocusWidget.swift
//  FrisFocusWidget
//
//  F3 — Live Activity for an active focus block. Lock-screen banner
//  shows a compact tree (canopy fullness reflects current leaf count),
//  the wall-clock countdown, the label, and the rooted / leaves-fell
//  state. Dynamic Island renders the same data scaled down. The
//  countdown uses the system timer text style so it stays live
//  without continual pushes.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Theme constants (widget-local copy of the app palette)

private enum WidgetTheme {
    static let cream = Color(red: 0.980, green: 0.949, blue: 0.878)        // #FAF2E0
    static let creamDeep = Color(red: 0.953, green: 0.910, blue: 0.800)    // #F3E8CC
    static let charcoal = Color(red: 0.173, green: 0.173, blue: 0.165)     // #2C2C2A
    static let bark = Color(red: 0.541, green: 0.416, blue: 0.282)         // #8A6A48
    static let canopyDeep = Color(red: 0.255, green: 0.388, blue: 0.114)   // dark green
    static let canopyMid = Color(red: 0.388, green: 0.600, blue: 0.133)    // #639922
    static let canopyLight = Color(red: 0.525, green: 0.722, blue: 0.243)  // sun-catch
    static let leaf = Color(red: 0.769, green: 0.659, blue: 0.416)         // #C4A86A
    static let alertGreen = Color(red: 0.376, green: 0.580, blue: 0.235)
}

// MARK: - Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            FocusLockScreenView(
                state: context.state,
                label: context.attributes.label
            )
            .activityBackgroundTint(WidgetTheme.cream)
            .activitySystemActionForegroundColor(WidgetTheme.charcoal)
        } dynamicIsland: { context in
            let state = context.state
            let label = context.attributes.label
            return DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    DynamicTreeGlyph(
                        leavesFallen: state.leavesFallen,
                        canopyTotal: state.canopyTotal
                    )
                    .frame(width: 36, height: 44)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            timerInterval: state.startedAt...state.startedAt.addingTimeInterval(state.plannedDuration),
                            countsDown: true
                        )
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.cream)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 92, alignment: .trailing)

                        Text(stateChipText(leaves: state.leavesFallen))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WidgetTheme.cream.opacity(0.7))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let label, !label.isEmpty {
                        Text(label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(WidgetTheme.cream.opacity(0.6))
                            .lineLimit(1)
                    } else {
                        Text("FOCUS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(WidgetTheme.cream.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                DynamicTreeGlyph(
                    leavesFallen: state.leavesFallen,
                    canopyTotal: state.canopyTotal
                )
                .frame(width: 18, height: 22)
            } compactTrailing: {
                Text(
                    timerInterval: state.startedAt...state.startedAt.addingTimeInterval(state.plannedDuration),
                    countsDown: true
                )
                .font(.system(size: 12, weight: .regular, design: .serif))
                .monospacedDigit()
                .frame(maxWidth: 52)
            } minimal: {
                DynamicTreeGlyph(
                    leavesFallen: state.leavesFallen,
                    canopyTotal: state.canopyTotal
                )
                .frame(width: 18, height: 22)
            }
            .keylineTint(WidgetTheme.canopyMid)
        }
    }
}

private func stateChipText(leaves: Int) -> String {
    if leaves == 0 { return "rooted" }
    if leaves == 1 { return "1 leaf fell" }
    return "\(leaves) leaves fell"
}

// MARK: - Lock Screen view

struct FocusLockScreenView: View {
    let state: FocusActivityAttributes.ContentState
    let label: String?

    var body: some View {
        HStack(spacing: 14) {
            // Compact tree on the left.
            FocusTreeMini(
                leavesFallen: state.leavesFallen,
                canopyTotal: state.canopyTotal
            )
            .frame(width: 64, height: 84)

            // Eyebrow + countdown + state chip on the right.
            VStack(alignment: .leading, spacing: 4) {
                Text((label?.isEmpty == false ? "FOCUS · \(label!.uppercased())" : "FOCUS"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(WidgetTheme.charcoal.opacity(0.55))
                    .lineLimit(1)

                Text(
                    timerInterval: state.startedAt...state.startedAt.addingTimeInterval(state.plannedDuration),
                    countsDown: true
                )
                .font(.system(size: 30, weight: .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.charcoal)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.leavesFallen == 0 ? WidgetTheme.alertGreen : WidgetTheme.leaf)
                        .frame(width: 6, height: 6)
                    Text(stateChipText(leaves: state.leavesFallen))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(WidgetTheme.charcoal.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Tree art (constrained to Live Activity size)

/// Tiny tree used in the lock-screen banner. Layered canopy + tapered
/// trunk + a hint of fallen leaves below; canopy thins as leaves fall.
struct FocusTreeMini: View {
    let leavesFallen: Int
    let canopyTotal: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // Ground shadow
            let shadowRect = CGRect(
                x: w * 0.08,
                y: h * 0.84,
                width: w * 0.84,
                height: h * 0.06
            )
            ctx.fill(
                Path(ellipseIn: shadowRect),
                with: .color(WidgetTheme.charcoal.opacity(0.12))
            )

            // Trunk
            let trunkTop = CGPoint(x: w * 0.50, y: h * 0.42)
            let trunkBL = CGPoint(x: w * 0.43, y: h * 0.86)
            let trunkBR = CGPoint(x: w * 0.57, y: h * 0.86)
            let trunkTL = CGPoint(x: w * 0.47, y: h * 0.42)
            let trunkTR = CGPoint(x: w * 0.53, y: h * 0.42)
            var trunk = Path()
            trunk.move(to: trunkTL)
            trunk.addLine(to: trunkTR)
            trunk.addLine(to: trunkBR)
            trunk.addLine(to: trunkBL)
            trunk.closeSubpath()
            ctx.fill(trunk, with: .color(WidgetTheme.bark))
            _ = trunkTop

            // Canopy: three stacked ellipses, fullness reflects leaves remaining
            let leavesRemaining = max(0, canopyTotal - leavesFallen)
            // Floor visible canopy so the tree never reads "dead"
            let fullness = canopyTotal == 0 ? 1.0 : max(0.35, Double(leavesRemaining) / Double(canopyTotal))

            let canopyMasses: [(CGRect, Color)] = [
                (CGRect(x: w * 0.10, y: h * 0.18, width: w * 0.80, height: h * 0.40),
                 WidgetTheme.canopyDeep),
                (CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.72, height: h * 0.36),
                 WidgetTheme.canopyMid),
                (CGRect(x: w * 0.22, y: h * 0.06, width: w * 0.62, height: h * 0.32),
                 WidgetTheme.canopyLight)
            ]
            for (rect, color) in canopyMasses {
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.55 + 0.45 * fullness))
                )
            }

            // Fallen leaves at the base — a few small dots per leaf, capped.
            let dotsToDraw = min(leavesFallen, 6)
            for i in 0..<dotsToDraw {
                let t = (Double(i) + 0.5) / 6.0
                let cx = w * (0.18 + 0.64 * t)
                let cy = h * 0.88 + (i % 2 == 0 ? -1 : 1)
                let r: CGFloat = 1.8
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .color(WidgetTheme.leaf)
                )
            }
        }
    }
}

/// Even smaller tree glyph for the Dynamic Island.
struct DynamicTreeGlyph: View {
    let leavesFallen: Int
    let canopyTotal: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // Trunk
            var trunk = Path()
            trunk.move(to: CGPoint(x: w * 0.45, y: h * 0.45))
            trunk.addLine(to: CGPoint(x: w * 0.55, y: h * 0.45))
            trunk.addLine(to: CGPoint(x: w * 0.60, y: h * 0.95))
            trunk.addLine(to: CGPoint(x: w * 0.40, y: h * 0.95))
            trunk.closeSubpath()
            ctx.fill(trunk, with: .color(WidgetTheme.bark))

            // Canopy
            let leavesRemaining = max(0, canopyTotal - leavesFallen)
            let fullness = canopyTotal == 0 ? 1.0 : max(0.35, Double(leavesRemaining) / Double(canopyTotal))
            let canopy = CGRect(x: 0, y: 0, width: w, height: h * 0.55)
            ctx.fill(
                Path(ellipseIn: canopy.insetBy(dx: w * 0.05, dy: h * 0.04)),
                with: .color(WidgetTheme.canopyDeep.opacity(0.55 + 0.4 * fullness))
            )
            ctx.fill(
                Path(ellipseIn: canopy.insetBy(dx: w * 0.18, dy: h * 0.10)),
                with: .color(WidgetTheme.canopyLight.opacity(0.7 + 0.3 * fullness))
            )
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: FocusActivityAttributes(label: "Deep work")) {
    FocusLiveActivity()
} contentStates: {
    FocusActivityAttributes.ContentState(
        startedAt: .now,
        plannedDuration: 45 * 60,
        leavesFallen: 0,
        canopyTotal: 26
    )
    FocusActivityAttributes.ContentState(
        startedAt: .now.addingTimeInterval(-600),
        plannedDuration: 45 * 60,
        leavesFallen: 3,
        canopyTotal: 26
    )
}
