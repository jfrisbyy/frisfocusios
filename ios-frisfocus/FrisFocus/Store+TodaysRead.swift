//
//  Store+TodaysRead.swift
//  FrisFocus
//
//  The once-daily "Today's Read" state machine. Assembles the day snapshot,
//  makes ONE bounded model call per user per active day, caches the result,
//  and gates "Think again" to material day-state changes (capped). The
//  ranking engine never calls a model — only this does.
//

import Foundation

// MARK: - Snapshot the app assembles for the read

private nonisolated struct ReadSeason: Encodable {
    let name: String
    let theme: String
    let day_n: Int
    let length: Int?
    let recent_arc: String
}

private nonisolated struct ReadNow: Encodable {
    let time_of_day: String
    let hours_left_in_active_window: Int
}

private nonisolated struct ReadOpenTask: Encodable {
    let id: String
    let name: String
    let value: Int
    let penalty: Int
    let time_competing: Bool
}

private nonisolated struct ReadToday: Encodable {
    let points_so_far: Int
    let daily_target: Int
    let ratio: Double
    let tasks_done: [String]
    let tasks_open: [ReadOpenTask]
    let target_hit: Bool
}

private nonisolated struct ReadCandidate: Encodable {
    let id: String
    let name: String
    let type: String
    let value: Int
    let penalty: Int
    let drift_days: Int
    let category: String
}

private nonisolated struct ReadDrift: Encodable {
    let category: String
    let days_idle: Int
    let sample_goal: String
}

private nonisolated struct ReadInput: Encodable {
    let season: ReadSeason
    let now: ReadNow
    let today: ReadToday
    let open_candidates_ranked: [ReadCandidate]
    let drift: [ReadDrift]
}

extension Store {

    // MARK: - Read gating

    /// Whether the resting "Get a read on today" prompt could plausibly
    /// help: at least one ranked card, target not yet hit, within active
    /// hours, and no read generated yet today.
    var canShowReadPrompt: Bool {
        guard needsYouSectionVisible, !needsYouTargetHit else { return false }
        guard needsYou.read() == nil else { return false }
        return !rankedNeedsYou.isEmpty
    }

    /// A coarse fingerprint of the day's state. "Think again" only spends a
    /// call when this differs from the cached read's hash — new completions,
    /// a crossed time bucket, or the target newly hit.
    var todaysReadStateHash: String {
        let dayKey = NeedsYouState.dayKey()
        let done = completedTaskCountToday
        let bucket: String = {
            switch needsYouTimeBucket() {
            case .morning: return "m"
            case .afternoon: return "a"
            case .evening: return "e"
            }
        }()
        let hit = needsYouTargetHit ? "1" : "0"
        let openCount = rankedNeedsYou.count
        return "\(dayKey)|done:\(done)|b:\(bucket)|hit:\(hit)|open:\(openCount)"
    }

    /// "Think again" is allowed only when a read exists, the day has
    /// materially changed since it was made, and we're under the daily cap.
    var canThinkAgain: Bool {
        guard let read = needsYou.read() else { return false }
        guard read.recallCount < 2 else { return false }
        return read.stateHash != todaysReadStateHash
    }

    private var completedTaskCountToday: Int {
        let cal = Calendar.current
        return logEntries.filter {
            $0.entryType == .completed && cal.isDateInToday($0.date)
        }.count
    }

    // MARK: - Generate

    /// Make the read call (or re-call). Sets the phase to `.thinking`,
    /// fires the bounded request, and stores the result. Caller should only
    /// invoke on an explicit "get a read" / valid "think again" tap.
    @MainActor
    func generateTodaysRead() async {
        // Guard against double-fire while one is already in flight.
        if case .thinking = needsYou.phase { return }

        let priorRecalls = needsYou.read()?.recallCount ?? 0
        let stateHash = todaysReadStateHash
        let input = assembleReadInput()
        needsYou.phase = .thinking

        do {
            let snapshot = try JSONEncoder().encode(input)
            let payload = try await TodaysReadService.fetch(snapshot: snapshot)
            let read = TodaysRead(
                payload: payload,
                dayKey: NeedsYouState.dayKey(),
                stateHash: stateHash,
                recallCount: priorRecalls + 1,
                generatedAt: Date()
            )
            needsYou.storeRead(read)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "The read didn\u{2019}t come through."
            needsYou.phase = .failed(message)
        }
    }

    // MARK: - Input assembly

    private func assembleReadInput() -> ReadInput {
        let now = Date()
        let cal = Calendar.current
        let ranked = rankedNeedsYou

        let tasksDone: [String] = logEntries
            .filter { $0.entryType == .completed && cal.isDateInToday($0.date) }
            .compactMap { entry in
                guard let taskId = entry.taskId else { return nil }
                return tasks.first(where: { $0.id == taskId })?.title
            }

        let openTasks: [ReadOpenTask] = tasks
            .filter {
                $0.isPinnedToday
                    && !hasLogEntryToday(forTaskId: $0.id)
                    && $0.nominalValue >= reminderValueThreshold
            }
            .map {
                ReadOpenTask(
                    id: $0.id.uuidString,
                    name: $0.title,
                    value: $0.nominalValue,
                    penalty: abs(min(0, $0.skipPenalty ?? 0)),
                    time_competing: ($0.estimatedMinutes ?? 0) >= 60
                )
            }

        let candidates: [ReadCandidate] = ranked.map { item in
            let id: String = {
                if let t = item.taskId { return t.uuidString }
                if let r = item.routineId { return r.uuidString }
                return item.category?.rawValue ?? item.key
            }()
            let type: String = {
                switch item.kind {
                case .task: return "task"
                case .routine: return "routine"
                case .drift: return "drift"
                }
            }()
            return ReadCandidate(
                id: id,
                name: item.title,
                type: type,
                value: item.value,
                penalty: item.penalty,
                drift_days: item.driftDays,
                category: item.category.map { categoryDisplayName($0) } ?? ""
            )
        }

        let drift: [ReadDrift] = ranked
            .filter { $0.kind == .drift }
            .map { item in
                ReadDrift(
                    category: item.category.map { categoryDisplayName($0) } ?? "",
                    days_idle: item.driftDays,
                    sample_goal: driftSampleGoal(for: item.category)
                )
            }

        let target = max(1, currentSeason.dailyGoal)
        let ratio = Double(todayScore) / Double(target)

        let season = ReadSeason(
            name: currentSeason.name,
            theme: (currentSeason.intention?.isEmpty == false ? currentSeason.intention! : currentSeason.name),
            day_n: currentSeasonDay,
            length: currentSeason.resolvedEndMode == .date ? currentSeason.lengthDays : nil,
            recent_arc: recentArcDescription()
        )

        let readNow = ReadNow(
            time_of_day: timeOfDayWord(now: now),
            hours_left_in_active_window: needsYouHoursLeft(now: now)
        )

        let today = ReadToday(
            points_so_far: todayScore,
            daily_target: target,
            ratio: (ratio * 100).rounded() / 100,
            tasks_done: tasksDone,
            tasks_open: openTasks,
            target_hit: needsYouTargetHit
        )

        return ReadInput(
            season: season,
            now: readNow,
            today: today,
            open_candidates_ranked: candidates,
            drift: drift
        )
    }

    /// A representative goal/task name for a drifting category (the
    /// highest-value task in it), used to ground the read's specificity.
    private func driftSampleGoal(for category: Category?) -> String {
        guard let category else { return "" }
        return tasks
            .filter { $0.category == category }
            .max(by: { $0.nominalValue < $1.nominalValue })?
            .title ?? ""
    }

    private func timeOfDayWord(now: Date) -> String {
        switch needsYouTimeBucket(now: now) {
        case .morning: return "morning"
        case .afternoon: return "afternoon"
        case .evening: return "evening"
        }
    }

    /// A short human read of the last few days' rhythm to give the model
    /// arc context (comeback / strong stretch / grinding / steady).
    private func recentArcDescription() -> String {
        let cal = Calendar.current
        let target = max(1, currentSeason.dailyGoal)
        var scores: [Int] = []
        for offset in 1...5 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            scores.append(score(on: day))
        }
        guard !scores.isEmpty else { return "just getting started" }

        let strongDays = scores.filter { $0 >= target }.count
        let quietLead = scores.prefix(while: { $0 < target / 3 }).count

        if strongDays >= 4 { return "grinding hard, little rest lately" }
        if quietLead >= 2 { return "coming back after \(quietLead) quiet days" }
        if strongDays >= 2 { return "a strong recent stretch" }
        return "a steady, ordinary stretch"
    }
}
