//
//  WeekScheduleView.swift
//  FrisFocus
//
//  The weekly schedule page — seven day sections for the current week
//  (today highlighted), each listing every task pinned to that day:
//  daily tasks, day-of-week tasks, and one-off pins. Tap a task to
//  adjust its schedule inline (TaskScheduleSheet). An arrange-by-time
//  toggle turns each day into a simple agenda: timed tasks sorted by
//  their window with times shown, untimed tasks under "Anytime".
//
//  Opened from the small calendar button in the Today's Plan header.
//

import SwiftUI
import UIKit

struct WeekScheduleView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var arrangeByTime: Bool = false
    @State private var scheduleTask: FFTask? = nil
    @State private var addTaskDay: Date? = nil

    /// The seven days of the calendar week containing today.
    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let dayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        arrangeToggle

                        ForEach(weekDays, id: \.self) { day in
                            daySection(day)
                                .id(dayId(day))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.warmWheat)
                .onAppear {
                    // Land on today rather than Sunday.
                    proxy.scrollTo(dayId(Date()), anchor: .top)
                }
            }
            .navigationTitle("This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .sheet(item: $scheduleTask) { task in
            TaskScheduleSheet(task: task)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $addTaskDay) { day in
            PinTaskToDaySheet(day: day)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func dayId(_ day: Date) -> String {
        let cal = Calendar.current
        return "day-\(cal.component(.weekday, from: day))"
    }

    // MARK: - Arrange toggle

    @ViewBuilder
    private var arrangeToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) {
                arrangeByTime.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: arrangeByTime ? "clock.fill" : "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(arrangeByTime ? Theme.warmWheat : Theme.textPrimary.opacity(0.6))
                Text("ARRANGE BY TIME")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(arrangeByTime ? Theme.warmWheat : Theme.textPrimary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(arrangeByTime ? Theme.textPrimary : Theme.textPrimary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(arrangeByTime ? "Switch off time arrangement" : "Arrange each day by time")
    }

    // MARK: - Day section

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let pinned = store.tasksPinned(on: day)

        VStack(alignment: .leading, spacing: 10) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.dayTitleFormatter.string(from: day))
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(isToday ? 1 : 0.8))
                Text(Self.dayDateFormatter.string(from: day))
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                if isToday {
                    Text("TODAY")
                        .font(.sans(9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.alertGreen)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.alertGreen.opacity(0.12)))
                }
                Spacer(minLength: 0)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    addTaskDay = day
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a task to \(Self.dayTitleFormatter.string(from: day))")
            }

            if pinned.isEmpty {
                emptyDayHint(day)
            } else if arrangeByTime {
                agendaList(pinned)
            } else {
                VStack(spacing: 8) {
                    ForEach(pinned) { task in
                        scheduleRow(task, showTime: true)
                    }
                }
            }
        }
        .padding(14)
        .background(isToday ? Color.white : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isToday ? Theme.alertGreen.opacity(0.35) : Theme.textPrimary.opacity(0.07),
                    lineWidth: isToday ? 1 : 0.5
                )
        )
    }

    // MARK: - Agenda (arrange by time)

    @ViewBuilder
    private func agendaList(_ tasks: [FFTask]) -> some View {
        let timed = tasks
            .filter { $0.timeWindow != nil }
            .sorted { ($0.timeWindow?.startMinutes ?? 0) < ($1.timeWindow?.startMinutes ?? 0) }
        let untimed = tasks.filter { $0.timeWindow == nil }

        VStack(alignment: .leading, spacing: 8) {
            ForEach(timed) { task in
                HStack(alignment: .top, spacing: 10) {
                    Text(task.timeWindow?.startText ?? "")
                        .font(.serif(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 64, alignment: .trailing)
                        .padding(.top, 12)
                    scheduleRow(task, showTime: false)
                }
            }

            if !untimed.isEmpty {
                if !timed.isEmpty {
                    Text("ANYTIME")
                        .font(.sans(9, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                        .padding(.top, 4)
                }
                ForEach(untimed) { task in
                    scheduleRow(task, showTime: false)
                }
            }
        }
    }

    // MARK: - Task row

    @ViewBuilder
    private func scheduleRow(_ task: FFTask, showTime: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            scheduleTask = task
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: store.categoryColorHex(task.category)))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(scheduleLabel(task))
                            .font(.sans(10, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        if showTime, let window = task.timeWindow {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8, weight: .regular))
                                Text(window.displayText)
                                    .font(.sans(10, weight: .medium))
                            }
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        }
                    }
                }

                Spacer(minLength: 8)

                Text("\(task.nominalValue)")
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.warmWheat.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Adjust schedule for \(task.title)")
    }

    /// Short label for how this task earns its place on the day.
    private func scheduleLabel(_ task: FFTask) -> String {
        switch task.pinSchedule {
        case .daily: return "Every day"
        case .daysOfWeek(let days):
            let cal = Calendar.current
            let symbols = cal.shortWeekdaySymbols
            let names = days.sorted().compactMap { d -> String? in
                guard (1...7).contains(d) else { return nil }
                return symbols[d - 1]
            }
            return names.joined(separator: " · ")
        case .today: return "Today only"
        case .singleDate: return "One day"
        case .none: return "Pinned today"
        }
    }

    // MARK: - Empty day

    @ViewBuilder
    private func emptyDayHint(_ day: Date) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            addTaskDay = day
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                Text("Nothing pinned — add a task")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Sheet(item:) needs Identifiable — a calendar day identifies itself.
extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    WeekScheduleView()
        .environment(Store())
}
