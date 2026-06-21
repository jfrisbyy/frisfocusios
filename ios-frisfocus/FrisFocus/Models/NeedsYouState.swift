//
//  NeedsYouState.swift
//  FrisFocus
//
//  Observable, self-persisting state for the Needs You section. Holds the
//  per-day dismiss/snooze bookkeeping and the cached once-daily "Today's
//  Read". Persists to UserDefaults directly so it stays out of the Store's
//  main save/load envelope.
//

import Foundation
import Observation

/// Where the Today's Read flow currently is (transient — never persisted).
enum ReadPhase: Equatable {
    case idle      // resting prompt may show
    case thinking  // call in flight — cards become skeletons, sun pulses
    case shown     // a read is rendered (fresh or cached)
    case failed(String)
}

@Observable
final class NeedsYouState {
    /// key → dayKey the card was dismissed on. Cleared on a new day.
    private(set) var dismissed: [String: String] = [:]
    /// key → instant the snooze expires (re-surfaces after).
    private(set) var snoozedUntil: [String: Date] = [:]
    /// The cached read for the active day, if any.
    private(set) var cachedRead: TodaysRead?

    /// Transient UI phase for the read panel.
    var phase: ReadPhase = .idle

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dismissed = "needsYou.dismissed"
        static let snoozed = "needsYou.snoozedUntil"
        static let read = "needsYou.cachedRead"
    }

    init() {
        load()
    }

    // MARK: - Day key

    static func dayKey(for date: Date = Date()) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Dismiss / snooze queries

    /// True when a card is hidden for the current day (dismissed today, or
    /// snoozed and still inside the snooze window).
    func isHidden(key: String, now: Date = Date()) -> Bool {
        let todayKey = Self.dayKey(for: now)
        if dismissed[key] == todayKey { return true }
        if let until = snoozedUntil[key], until > now { return true }
        return false
    }

    func dismiss(key: String, now: Date = Date()) {
        dismissed[key] = Self.dayKey(for: now)
        save()
    }

    func snooze(key: String, until: Date) {
        snoozedUntil[key] = until
        save()
    }

    // MARK: - Read cache

    func storeRead(_ read: TodaysRead) {
        cachedRead = read
        phase = .shown
        save()
    }

    /// The cached read if it belongs to the current day, else nil.
    func read(for now: Date = Date()) -> TodaysRead? {
        guard let cachedRead, cachedRead.dayKey == Self.dayKey(for: now) else { return nil }
        return cachedRead
    }

    /// Roll over stale per-day state at the start of a new day. Idempotent.
    func rolloverIfNeeded(now: Date = Date()) {
        let todayKey = Self.dayKey(for: now)
        var changed = false

        let staleDismissed = dismissed.filter { $0.value != todayKey }
        if !staleDismissed.isEmpty {
            for key in staleDismissed.keys { dismissed.removeValue(forKey: key) }
            changed = true
        }

        let staleSnoozes = snoozedUntil.filter { $0.value <= now }
        if !staleSnoozes.isEmpty {
            for key in staleSnoozes.keys { snoozedUntil.removeValue(forKey: key) }
            changed = true
        }

        if let cachedRead, cachedRead.dayKey != todayKey {
            self.cachedRead = nil
            phase = .idle
            changed = true
        }

        if changed { save() }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Keys.dismissed),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            dismissed = decoded
        }
        if let data = defaults.data(forKey: Keys.snoozed),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            snoozedUntil = decoded
        }
        if let data = defaults.data(forKey: Keys.read),
           let decoded = try? JSONDecoder().decode(TodaysRead.self, from: data) {
            cachedRead = decoded
            // Only resurface a same-day cached read as "shown".
            if decoded.dayKey == Self.dayKey() {
                phase = .shown
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(dismissed) {
            defaults.set(data, forKey: Keys.dismissed)
        }
        if let data = try? JSONEncoder().encode(snoozedUntil) {
            defaults.set(data, forKey: Keys.snoozed)
        }
        if let cachedRead, let data = try? JSONEncoder().encode(cachedRead) {
            defaults.set(data, forKey: Keys.read)
        } else {
            defaults.removeObject(forKey: Keys.read)
        }
    }
}
