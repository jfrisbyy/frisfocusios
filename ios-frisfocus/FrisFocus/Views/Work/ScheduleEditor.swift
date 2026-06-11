//
//  ScheduleEditor.swift
//  FrisFocus
//
//  Shared schedule controls for a Task — the mode chips (Not pinned /
//  Today only / Specific days / Every day), the seven weekday chips,
//  and the optional daily time window. Used by the redesigned
//  NewTaskFormView and the compact TaskScheduleSheet so both surfaces
//  edit exactly the same state.
//

import SwiftUI
import UIKit

/// UI-level schedule shape. Maps to/from `PinSchedule` + `oneOffPinDate`.
enum TaskScheduleMode: String, CaseIterable, Identifiable {
    case notPinned
    case today
    case specificDays
    case everyDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notPinned: return "Not pinned"
        case .today: return "Today only"
        case .specificDays: return "Specific days"
        case .everyDay: return "Every day"
        }
    }
}

/// Bindable working copy of a task's schedule, shared by the full
/// editor and the compact sheet. Build with `init(task:)`, write back
/// with `resolvedSchedule` + `resolvedTimeWindow`.
struct ScheduleDraft: Equatable {
    var mode: TaskScheduleMode
    var selectedDays: Set<Int>
    var hasTimeWindow: Bool
    var startTime: Date
    var endTime: Date

    init(task: FFTask?) {
        let cal = Calendar.current
        switch task?.pinSchedule {
        case .today:
            mode = .today
            selectedDays = []
        case .singleDate(let date):
            mode = cal.isDateInToday(date) ? .today : .notPinned
            selectedDays = []
        case .daysOfWeek(let days):
            mode = .specificDays
            selectedDays = days
        case .daily:
            mode = .everyDay
            selectedDays = []
        case .none, .some(.none):
            // A live one-off pin reads as "Today only" so the editor
            // reflects what the user sees on the plan.
            if let oneOff = task?.oneOffPinDate, cal.isDateInToday(oneOff) {
                mode = .today
            } else {
                mode = .notPinned
            }
            selectedDays = []
        }

        let window = task?.timeWindow
        hasTimeWindow = window != nil
        startTime = window?.startDate() ?? Self.defaultStart
        endTime = window?.endDate() ?? Self.defaultEnd
    }

    private static var defaultStart: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static var defaultEnd: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// The `PinSchedule` this draft resolves to. "Today only" keeps the
    /// existing `.today` semantics (rollover clears it).
    var resolvedSchedule: PinSchedule {
        switch mode {
        case .notPinned: return .none
        case .today: return .today
        case .specificDays: return selectedDays.isEmpty ? .none : .daysOfWeek(selectedDays)
        case .everyDay: return .daily
        }
    }

    /// The `TimeWindow` this draft resolves to — nil when off or when
    /// the task isn't pinned anywhere.
    var resolvedTimeWindow: TimeWindow? {
        guard hasTimeWindow, mode != .notPinned else { return nil }
        let cal = Calendar.current
        let start = cal.component(.hour, from: startTime) * 60 + cal.component(.minute, from: startTime)
        let end = cal.component(.hour, from: endTime) * 60 + cal.component(.minute, from: endTime)
        return TimeWindow(startMinutes: start, endMinutes: max(end, start))
    }
}

/// The shared schedule controls. Drop inside any warm-paper card.
struct ScheduleEditorView: View {
    @Binding var draft: ScheduleDraft

    /// Single-letter weekday labels in Calendar order (1 = Sunday).
    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Mode chips — 2×2 grid so the labels never truncate.
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(TaskScheduleMode.allCases) { mode in
                    modeChip(mode)
                }
            }

            if draft.mode == .specificDays {
                dayChipsRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if draft.mode != .notPinned {
                timeWindowControls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: draft.mode)
        .animation(.easeInOut(duration: 0.2), value: draft.hasTimeWindow)
    }

    // MARK: - Mode chips

    @ViewBuilder
    private func modeChip(_ mode: TaskScheduleMode) -> some View {
        let selected = draft.mode == mode
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            draft.mode = mode
        } label: {
            Text(mode.label)
                .font(.sans(13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Theme.textPrimary : Theme.warmWheat)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Color.clear : Theme.textPrimary.opacity(0.10),
                            lineWidth: 0.6
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Day chips

    @ViewBuilder
    private var dayChipsRow: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                dayChip(weekday)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayChip(_ weekday: Int) -> some View {
        let selected = draft.selectedDays.contains(weekday)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if selected {
                draft.selectedDays.remove(weekday)
            } else {
                draft.selectedDays.insert(weekday)
            }
        } label: {
            Text(Self.dayLetters[weekday - 1])
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    Circle()
                        .fill(selected ? Theme.alertGreen : Theme.warmWheat)
                        .frame(width: 38, height: 38)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            selected ? Color.clear : Theme.textPrimary.opacity(0.15),
                            lineWidth: 0.8
                        )
                        .frame(width: 38, height: 38)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Time window

    @ViewBuilder
    private var timeWindowControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $draft.hasTimeWindow.animation(.easeInOut(duration: 0.2))) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Text("Time window")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .tint(Theme.alertGreen)

            if draft.hasTimeWindow {
                HStack(spacing: 12) {
                    DatePicker(
                        "From",
                        selection: $draft.startTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    Text("to")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    DatePicker(
                        "To",
                        selection: $draft.endTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
