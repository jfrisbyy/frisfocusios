//
//  CreateCircleEventView.swift
//  FrisFocus
//
//  The sheet any circle member uses to plan an event: title,
//  description, when & where, an optional linked circle task (existing
//  or brand-new), a repeat schedule, and a reminder lead time.
//

import SwiftUI
import UIKit

struct CreateCircleEventView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let circle: FFCircle
    /// Called with the created event so the caller can open it.
    var onCreated: ((CircleEvent) -> Void)? = nil

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var location: String = ""
    @State private var startAt: Date = CreateCircleEventView.defaultStart()
    @State private var hasEnd: Bool = false
    @State private var endAt: Date = CreateCircleEventView.defaultStart().addingTimeInterval(60 * 60)
    @State private var frequency: EventRepeatFrequency = .none
    @State private var weekdays: Set<Int> = []
    @State private var reminderMinutes: Int = 30

    // Task linking
    @State private var linkedTaskId: UUID? = nil
    @State private var showNewTaskField: Bool = false
    @State private var newTaskTitle: String = ""

    private let reminderOptions: [Int] = [0, 10, 30, 60, 120, 1440]

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                whenSection
                repeatSection
                taskSection
                reminderSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { create() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("What is it? (e.g. 5-mile run)", text: $title)
                .font(.sans(15, weight: .medium))
            TextField("Add a description", text: $details, axis: .vertical)
                .font(.sans(14, weight: .regular))
                .lineLimit(2...5)
            TextField("Location", text: $location)
                .font(.sans(14, weight: .regular))
        } header: {
            Text("Event")
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker("Starts", selection: $startAt)
                .font(.sans(14, weight: .regular))
            Toggle("Set an end time", isOn: $hasEnd.animation())
                .font(.sans(14, weight: .regular))
            if hasEnd {
                DatePicker("Ends", selection: $endAt, in: startAt...)
                    .font(.sans(14, weight: .regular))
            }
        } header: {
            Text("When")
        }
    }

    private var repeatSection: some View {
        Section {
            Picker("Repeats", selection: $frequency.animation()) {
                ForEach(EventRepeatFrequency.allCases, id: \.self) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .font(.sans(14, weight: .regular))

            if frequency == .weekly {
                weekdayPicker
            }
        } header: {
            Text("Repeat")
        }
    }

    private var weekdayPicker: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let selected = weekdays.contains(day)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(selected ? Theme.textCream : Theme.textPrimary.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(selected ? circle.type.tintDark : Theme.textPrimary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var taskSection: some View {
        Section {
            // Existing tasks
            ForEach(circle.tasks) { task in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    linkedTaskId = (linkedTaskId == task.id) ? nil : task.id
                    showNewTaskField = false
                } label: {
                    HStack {
                        Image(systemName: linkedTaskId == task.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(linkedTaskId == task.id ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        Text(task.title)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation { showNewTaskField.toggle() }
                linkedTaskId = nil
            } label: {
                Label("Create a new task", systemImage: "plus.circle")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(circle.type.tintDark)
            }
            .buttonStyle(.plain)

            if showNewTaskField {
                TextField("New task title", text: $newTaskTitle)
                    .font(.sans(14, weight: .regular))
            }
        } header: {
            Text("Link to a task (optional)")
        } footer: {
            Text("Finishing the linked task counts in the circle.")
        }
    }

    private var reminderSection: some View {
        Section {
            Picker("Remind me", selection: $reminderMinutes) {
                ForEach(reminderOptions, id: \.self) { m in
                    Text(reminderLabel(m)).tag(m)
                }
            }
            .font(.sans(14, weight: .regular))
        } header: {
            Text("Reminder")
        }
    }

    private func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "None"
        case 1440: return "1 day before"
        case 60: return "1 hour before"
        case 120: return "2 hours before"
        default: return "\(minutes) min before"
        }
    }

    // MARK: - Create

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Resolve the linked task — a brand-new one is created on the fly.
        var resolvedTaskId = linkedTaskId
        if showNewTaskField {
            let t = newTaskTitle.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                resolvedTaskId = store.addCircleTask(circleId: circle.id, title: t, pointValue: nil)
            }
        }

        let rule = EventRepeat(
            frequency: frequency,
            weekdays: frequency == .weekly ? weekdays : [],
            endDate: nil,
            endAfterCount: nil
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let event = store.createEvent(
            circleId: circle.id,
            title: trimmed,
            details: details,
            location: location,
            startAt: startAt,
            endAt: hasEnd ? endAt : nil,
            linkedCircleTaskId: resolvedTaskId,
            repeatRule: rule,
            reminderMinutes: reminderMinutes
        )
        onCreated?(event)
        dismiss()
    }

    /// Next round-ish hour from now as a friendly default start.
    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: next)
        return cal.date(from: comps) ?? next
    }
}
