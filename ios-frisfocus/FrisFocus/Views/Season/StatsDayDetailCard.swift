//
//  StatsDayDetailCard.swift
//  FrisFocus
//
//  One day's full breakdown — every LogEntry with an icon, the actual
//  task / to-do name, and its points — shown when a bar is tapped in
//  the Week or Month stats charts. Entries backed by a pinned proof
//  show a small photo mark; tapping the row unfolds the proof card
//  from that specific day right beneath it.
//

import AVFoundation
import SwiftUI
import UIKit

struct StatsDayDetailCard: View {
    @Environment(Store.self) private var store

    let day: Date

    /// Rows whose pinned proof is currently unfolded.
    @State private var expandedEntryIds: Set<UUID> = []

    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    private var cal: Calendar { Calendar.current }

    var body: some View {
        let entries = dayEntries
        let score = entries.map(\.pointsEarned).reduce(0, +)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(16, weight: .medium))
                    .foregroundStyle(Theme.textCream)

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("\(score)")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(score < 0 ? Theme.alertRed : Theme.textCream)
                    Text(" / \(store.currentSeason.dailyGoal)")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.5))
                }
            }

            if entries.isEmpty {
                Text("Nothing logged this day.")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textCream.opacity(0.5))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(entries, id: \.id) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    private var title: String {
        if cal.isDateInToday(day) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMM d"
        return formatter.string(from: day)
    }

    private var dayEntries: [LogEntry] {
        store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Entry row

    @ViewBuilder
    private func entryRow(_ entry: LogEntry) -> some View {
        let pins = proofPins(for: entry)
        let isExpanded = expandedEntryIds.contains(entry.id)

        VStack(spacing: 0) {
            Button {
                guard !pins.isEmpty else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if isExpanded {
                        expandedEntryIds.remove(entry.id)
                    } else {
                        expandedEntryIds.insert(entry.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: entryIconName(entry))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(entryIconColor(entry))
                        .frame(width: 18)

                    Text(entryLabel(entry))
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.92))
                        .lineLimit(2)

                    if !pins.isEmpty {
                        Image(systemName: "photo.fill.on.rectangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.sunWarm.opacity(0.9))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.textCream.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }

                    Spacer(minLength: 8)

                    Text(entry.pointsEarned >= 0 ? "+\(entry.pointsEarned)" : "\(entry.pointsEarned)")
                        .font(.serif(15, weight: .medium))
                        .foregroundStyle(
                            entry.pointsEarned < 0 ? Theme.alertRed : Theme.textCream
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pins.isEmpty)
            .accessibilityLabel(entryLabel(entry))
            .accessibilityHint(pins.isEmpty ? "" : "Shows the proof pinned to this item")

            if isExpanded, !pins.isEmpty {
                VStack(spacing: 10) {
                    ForEach(pins) { pin in
                        ProofPinMediaView(pin: pin)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Proofs pinned to this entry's task / to-do on this day.
    private func proofPins(for entry: LogEntry) -> [ProofPin] {
        if let taskId = entry.taskId {
            return store.proofPins(forTaskId: taskId, on: day)
        }
        if let todoId = entry.todoId {
            return store.proofPins(forTodoId: todoId, on: day)
        }
        return []
    }

    private func entryIconName(_ entry: LogEntry) -> String {
        switch entry.entryType {
        case .completed: return "checkmark.circle.fill"
        case .boosterBonus: return "sparkles"
        case .trainBonus: return "rectangle.stack.fill"
        case .milestone: return "flag.checkered"
        case .milestoneStep: return "flag"
        case .skipped: return "minus.circle"
        case .penalty: return "exclamationmark.circle.fill"
        }
    }

    private func entryIconColor(_ entry: LogEntry) -> Color {
        switch entry.entryType {
        case .completed: return Theme.sunWarm
        case .boosterBonus, .trainBonus, .milestone, .milestoneStep: return Theme.sunWarm.opacity(0.85)
        case .skipped: return Theme.textCream.opacity(0.4)
        case .penalty: return Theme.alertRed
        }
    }

    private func entryLabel(_ entry: LogEntry) -> String {
        if let taskId = entry.taskId,
           let task = store.tasks.first(where: { $0.id == taskId }) {
            switch entry.entryType {
            case .boosterBonus: return "\(task.title) · booster"
            case .penalty: return "\(task.title) · weekly limit"
            default: return task.title
            }
        }
        if let todoId = entry.todoId,
           let todo = store.todos.first(where: { $0.id == todoId }) {
            return todo.title
        }
        if let trainId = entry.trainId,
           let train = store.habitTrains.first(where: { $0.id == trainId }) {
            return "\(train.name) · routine"
        }
        if let milestoneId = entry.milestoneId,
           let milestone = store.currentSeason.milestones.first(where: { $0.id == milestoneId }) {
            if entry.entryType == .milestoneStep {
                let stepTitle = entry.milestoneStepId.flatMap { stepId in
                    milestone.steps.first { $0.id == stepId }?.title
                }
                return "\(stepTitle ?? milestone.title) · milestone step"
            }
            return "\(milestone.title) · milestone"
        }
        if let cadenceLinkId = entry.cadenceLinkId,
           let link = store.cadenceLinks.first(where: { $0.id == cadenceLinkId }) {
            return link.displayTitle
        }
        // Fall back to the title snapshot taken when the entry was
        // logged — the name survives even after the item is deleted.
        if let title = entry.title, !title.isEmpty {
            switch entry.entryType {
            case .boosterBonus: return "\(title) · booster"
            case .penalty: return "\(title) · penalty"
            default: return title
            }
        }
        switch entry.entryType {
        case .boosterBonus: return "Booster bonus"
        case .trainBonus: return "Routine complete"
        case .milestone: return "Milestone"
        case .milestoneStep: return "Milestone step"
        case .penalty: return "Avoidance"
        case .skipped: return "Skipped"
        case .completed: return "Logged"
        }
    }
}

// MARK: - Pinned proof media

/// One pinned proof card rendered inline beneath its entry row — the
/// composed 9:16 clean card, photo or looping clip.
struct ProofPinMediaView: View {
    let pin: ProofPin

    var body: some View {
        Color.black.opacity(0.25)
            .frame(width: 168, height: 298)
            .overlay {
                media
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Pinned proof")
    }

    @ViewBuilder
    private var media: some View {
        if pin.kind == .video, let url = pin.url {
            VideoLoopView(url: url, gravity: .resizeAspectFill)
                .id(url)
        } else if let url = pin.url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
                Text("Proof unavailable")
                    .font(.sans(10, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}
