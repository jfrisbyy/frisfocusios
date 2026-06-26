//
//  AgendaRows.swift
//  FrisFocus
//
//  The element rows the agenda day view places into its bands and tray:
//  fixed time blocks (solid, "fixed"), buckets (dashed, "BUCKET ·
//  you choose"), soft-placed task rows ("~band"), and Anytime chips.
//  All tinted by area; none of them ever read late or red.
//

import SwiftUI
import UIKit

// MARK: - Completion ring

/// The small tappable check used across agenda rows.
private struct AgendaCheckRing: View {
    let isDone: Bool
    let tint: Color
    let interactive: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? tint : Theme.textPrimary.opacity(0.25), lineWidth: 2)
                .frame(width: 22, height: 22)
            if isDone {
                Circle().fill(tint).frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .opacity(interactive ? 1 : 0.55)
    }
}

// MARK: - Fixed block

struct FixedBlockRow: View {
    @Environment(Store.self) private var store
    let task: FFTask
    let interactive: Bool
    let onTap: () -> Void

    private var tint: Color { Color(hex: store.categoryColorHex(task.category)) }
    private var isDone: Bool { store.hasLogEntryToday(forTaskId: task.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.8))
                        Text(task.timeWindow?.displayText ?? "")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(tint)
                        Text("fixed")
                            .font(.sans(9, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    }
                    Text(task.title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .strikethrough(isDone, color: Theme.textPrimary.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AgendaCheckRing(isDone: isDone, tint: tint, interactive: interactive)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(isDone ? 0.06 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .opacity(isDone ? 0.85 : 1)
    }
}

// MARK: - Bucket block

struct BucketBlockRow: View {
    @Environment(Store.self) private var store
    let bucket: Bucket
    let onTap: () -> Void

    private var tint: Color { Color(hex: store.categoryColorHex(bucket.category)) }
    private var isHonored: Bool { store.hasLogEntryToday(forBucketId: bucket.id) }
    private var logged: String? { store.loggedSpecificToday(forBucketId: bucket.id) }

    private var timingText: String {
        if let window = bucket.timeWindow { return window.displayText }
        if bucket.partOfDay != .anytime { return bucket.partOfDay.softLabel }
        return "anytime"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("BUCKET")
                            .font(.sans(8, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.15)))
                        Text(timingText)
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                    Text(bucket.title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(isHonored ? (logged.map { "honored · \($0)" } ?? "block honored") : "you choose how")
                        .font(.serifItalic(11))
                        .foregroundStyle(isHonored ? Theme.alertGreen : Theme.textPrimary.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AgendaCheckRing(isDone: isHonored, tint: tint, interactive: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHonored ? tint.opacity(0.06) : Color.white.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        tint.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.2, dash: isHonored ? [] : [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Soft-placed task

struct SoftTaskRow: View {
    @Environment(Store.self) private var store
    let task: FFTask
    let band: PartOfDay
    let interactive: Bool
    let onTap: () -> Void

    private var tint: Color { Color(hex: store.categoryColorHex(task.category)) }
    private var isDone: Bool { store.hasLogEntryToday(forTaskId: task.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle().fill(tint).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .strikethrough(isDone, color: Theme.textPrimary.opacity(0.4))
                        .lineLimit(1)
                    Text(band.softLabel)
                        .font(.sans(10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                Spacer(minLength: 8)
                AgendaCheckRing(isDone: isDone, tint: tint, interactive: interactive)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(isDone ? 0.85 : 1)
    }
}

// MARK: - Anytime chip

struct TrayChip: View {
    @Environment(Store.self) private var store
    let task: FFTask
    let interactive: Bool
    let onTap: () -> Void

    private var tint: Color { Color(hex: store.categoryColorHex(task.category)) }
    private var isDone: Bool { store.hasLogEntryToday(forTaskId: task.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                } else {
                    Circle().fill(tint).frame(width: 6, height: 6)
                }
                Text(task.title)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(isDone ? 0.5 : 0.9))
                    .strikethrough(isDone, color: Theme.textPrimary.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isDone ? tint.opacity(0.10) : Color.white.opacity(0.7))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}
