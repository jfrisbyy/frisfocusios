//
//  WidgetBridge.swift
//  FrisFocus
//
//  The app half of the home-screen widget: folds today's plan into a
//  small snapshot, writes it into the shared App Group container, and
//  asks WidgetKit to redraw — but only when the content actually
//  changed, so the reload budget is never wasted. Called from the
//  Store's single write path (`flushPendingSaves`), which means every
//  check-off, plan edit, and day rollover refreshes the widget within
//  moments.
//

import Foundation
import WidgetKit

/// The wire payload shared with the widget extension. The extension
/// keeps its own identical copy of this struct (targets don't share
/// files) — keep the coding keys in lockstep.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Local calendar day this snapshot describes ("yyyy-MM-dd") — the
    /// widget treats a stale key as "a new day is waiting".
    var dayKey: String
    var doneCount: Int
    var totalCount: Int
    /// Today's sun ratio (points ÷ daily goal), clamped 0...1 — the
    /// same number that drives the home sun.
    var sunRatio: Double
    var seasonName: String
    var nextTitle: String?
    var nextDetail: String?
    var updatedAt: Date
}

enum WidgetBridge {
    static let appGroupId = "group.com.frisfocus.app"
    static let snapshotKey = "widgetSnapshot.v1"
    static let widgetKind = "FrisFocusSunWidget"

    private nonisolated static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Publish the current plan state to the widget. Cheap: encodes,
    /// compares against the stored copy, and only writes + reloads on a
    /// real change.
    static func publish(from store: Store) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        var snapshot = makeSnapshot(from: store)

        // Content-compare with the stored snapshot, ignoring the
        // volatile timestamp.
        if let data = defaults.data(forKey: snapshotKey),
           var previous = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            previous.updatedAt = .distantPast
            var current = snapshot
            current.updatedAt = .distantPast
            if previous == current { return }
        }

        snapshot.updatedAt = Date()
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private static func makeSnapshot(from store: Store) -> WidgetSnapshot {
        let dayKey = dayFormatter.string(from: Date())

        // Demo / uninitialized installs publish an empty snapshot so the
        // widget shows its calm placeholder, never sample data.
        guard store.appMode == .clean else {
            return WidgetSnapshot(
                dayKey: dayKey,
                doneCount: 0,
                totalCount: 0,
                sunRatio: 0,
                seasonName: "",
                nextTitle: nil,
                nextDetail: nil,
                updatedAt: Date()
            )
        }

        let progress = store.coldStartProgress
        let goal = max(1, store.currentSeason.dailyGoal)
        let ratio = min(1, max(0, Double(store.myDay.todayLogged) / Double(goal)))

        // The next thing to do: soonest unfinished timed task whose
        // window hasn't fully passed, else the first floating one.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let doneIds = Set(store.logEntries.compactMap { entry -> UUID? in
            guard entry.entryType == .completed,
                  cal.isDate(entry.date, inSameDayAs: today) else { return nil }
            return entry.taskId
        })
        let unfinished = store.tasksPinned(on: today).filter { !doneIds.contains($0.id) }
        let now = Date()
        let timed = unfinished
            .filter { task in
                guard let window = task.timeWindow else { return false }
                return window.endDate(on: today) > now
            }
            .sorted { ($0.timeWindow?.startMinutes ?? 0) < ($1.timeWindow?.startMinutes ?? 0) }

        let next = timed.first ?? unfinished.first
        var nextDetail: String?
        if let next {
            if let window = next.timeWindow {
                nextDetail = window.displayText
            } else if next.partOfDay != .anytime {
                nextDetail = next.partOfDay.softLabel
            }
        }

        return WidgetSnapshot(
            dayKey: dayKey,
            doneCount: progress.done,
            totalCount: progress.total,
            sunRatio: ratio,
            seasonName: store.currentSeason.name,
            nextTitle: next?.title,
            nextDetail: nextDetail,
            updatedAt: Date()
        )
    }
}
