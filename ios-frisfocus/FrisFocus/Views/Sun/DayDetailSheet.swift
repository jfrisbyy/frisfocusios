//
//  DayDetailSheet.swift
//  FrisFocus
//
//  Opens when the user taps the date line on the Sun zone. A graphical
//  calendar lets the user jump to any day:
//
//   • a PAST day closes this picker and turns the whole home screen
//     into that day's snapshot (the time machine) — handled by the
//     parent through `store.viewingDay`.
//   • today      — a quiet pointer back to Today's Plan
//   • the future — a list of to-dos already scheduled for that day,
//     plus an inline quick-add so the user can plan ahead.
//
//  A "Today" shortcut in the toolbar jumps the picker back to now.
//

import SwiftUI
import UIKit

struct DayDetailSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var selectedDate: Date

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var startOfSelected: Date { cal.startOfDay(for: selectedDate) }

    private enum Relation { case past, today, future }
    private var relation: Relation {
        if cal.isDate(selectedDate, inSameDayAs: today) { return .today }
        return startOfSelected < today ? .past : .future
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DatePicker(
                        "Day",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(Theme.alertGreen)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    Group {
                        switch relation {
                        case .past:
                            // The parent swaps the home into this day's
                            // snapshot via the onChange below; this is a
                            // brief fallback while the sheet dismisses.
                            PastDaySnapshotView(date: startOfSelected)
                        case .today:
                            TodayDayPointerView()
                        case .future:
                            FutureDayView(date: startOfSelected)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedDate) { _, newValue in
                // Picking a past day enters the home-screen time machine:
                // close the picker and let the home render that snapshot.
                let start = cal.startOfDay(for: newValue)
                if start < today {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.viewingDay = start
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if relation == .future {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                selectedDate = Date()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Today")
                                    .font(.sans(14, weight: .semibold))
                            }
                            .foregroundStyle(Theme.alertGreen)
                        }
                        .accessibilityLabel("Back to today")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
        }
    }

    private var navTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: selectedDate)
    }
}

// MARK: - Today pointer

private struct TodayDayPointerView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.alertGreen.opacity(0.7))

            Text("This is today.")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text("Close this and use Today's Plan to log what's happening now.")
                .font(.serifItalic(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Future day

private struct FutureDayView: View {
    @Environment(Store.self) private var store
    let date: Date

    @State private var quickTitle: String = ""
    @State private var withPoints: Bool = false
    @State private var pointValue: Int = 2
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            futureSectionHeader("Planned for \(dayLabel)")

            if todosDue.isEmpty {
                Text("Nothing planned yet.")
                    .font(.serifItalic(14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(todosDue, id: \.id) { todo in
                        scheduledRow(todo)
                    }
                }
            }

            futureSectionHeader("Add a to-do")

            VStack(spacing: 12) {
                TextField("e.g. Call grandma", text: $quickTitle)
                    .focused($titleFocused)
                    .font(.sans(15, weight: .regular))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                    )
                    .submitLabel(.done)
                    .onSubmit(add)

                Toggle("Worth points", isOn: $withPoints.animation(.easeInOut(duration: 0.2)))
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.alertGreen)

                if withPoints {
                    Stepper(value: $pointValue, in: 1...10) {
                        HStack {
                            Text("Bonus")
                                .font(.sans(14, weight: .medium))
                            Spacer()
                            Text("+\(pointValue) pts")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                Button(action: add) {
                    Text("Add to \(dayLabel)")
                        .font(.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canAdd ? Theme.alertGreen : Theme.textPrimary.opacity(0.12))
                        .foregroundStyle(canAdd ? Theme.warmWheat : Theme.textPrimary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(14)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
    }

    private var todosDue: [Todo] {
        let cal = Calendar.current
        return store.todos
            .filter { todo in
                guard let due = todo.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: date)
            }
            .sorted { ($0.pointValue ?? -1) > ($1.pointValue ?? -1) }
    }

    @ViewBuilder
    private func scheduledRow(_ todo: Todo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(width: 18)

            Text(todo.title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .strikethrough(todo.isCompleted, color: Theme.textPrimary.opacity(0.5))
                .lineLimit(2)

            Spacer(minLength: 8)

            if let pts = todo.pointValue {
                Text("+\(pts)")
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }

    private var canAdd: Bool {
        !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let cal = Calendar.current
        let due = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date

        let todo = Todo(
            title: quickTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: due,
            pointValue: withPoints ? pointValue : nil
        )
        store.todos.append(todo)
        store.persistAll()

        quickTitle = ""
        titleFocused = false
    }
}

// MARK: - Shared section header

@ViewBuilder
private func futureSectionHeader(_ text: String) -> some View {
    EyebrowText(text: text, opacity: 0.6)
        .tracking(2)
        .padding(.top, 4)
}

#Preview {
    DayDetailSheet(selectedDate: Date())
        .environment(Store())
}
