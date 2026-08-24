//
//  Store+Agenda.swift
//  FrisFocus
//
//  The S9 agenda layer: bucket lifecycle + scoring, soft placement
//  (`partOfDay`), and day templates (save / stamp / swap / week
//  assignment). Built strictly on top of the existing PinSchedule day
//  engine — nothing here grades *when* a thing happened, only whether
//  and what. The grid reflects and arranges; it never enforces.
//

import Foundation

extension Store {

    // MARK: - Buckets: resolution

    /// Every bucket that appears on the given calendar day, ordered:
    /// hard-timed first by window start, then soft buckets by title.
    func bucketsPinned(on date: Date) -> [Bucket] {
        buckets
            .filter { $0.isPinnedFor(date) }
            .sorted { lhs, rhs in
                switch (lhs.timeWindow, rhs.timeWindow) {
                case let (l?, r?): return l.startMinutes < r.startMinutes
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.title < rhs.title
                }
            }
    }

    /// True if this bucket has been honored on the displayed day.
    func hasLogEntryToday(forBucketId bucketId: UUID) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: displayedDay)
        return logEntries.contains { entry in
            entry.bucketId == bucketId
                && cal.isDate(entry.date, inSameDayAs: day)
                && entry.entryType == .completed
        }
    }

    /// The specific the user logged inside a honored bucket today, if
    /// any — shown on the block ("Strength session"). Falls back to nil
    /// when the block was honored without naming a specific.
    func loggedSpecificToday(forBucketId bucketId: UUID) -> String? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: displayedDay)
        return logEntries.first { entry in
            entry.bucketId == bucketId
                && cal.isDate(entry.date, inSameDayAs: day)
                && entry.entryType == .completed
        }?.title
    }

    // MARK: - Buckets: CRUD

    /// Add a brand-new bucket. Returns it for the caller's convenience.
    @discardableResult
    func addBucket(_ bucket: Bucket) -> Bucket {
        buckets.append(bucket)
        persistAll()
        return bucket
    }

    /// Replace a bucket in place by id.
    func updateBucket(_ bucket: Bucket) {
        guard let idx = buckets.firstIndex(where: { $0.id == bucket.id }) else { return }
        buckets[idx] = bucket
        persistAll()
    }

    /// Permanently delete a bucket. Its honored-block log entries are
    /// left intact so past days keep their scores.
    func deleteBucket(_ bucket: Bucket) {
        buckets.removeAll { $0.id == bucket.id }
        persistAll()
    }

    // MARK: - Buckets: fulfillment (scoring)

    /// Honor a bucket — the witnessed, scored thing. Credits the
    /// bucket's own value once for today. A `specific` (a picked
    /// candidate or free-logged text) is recorded as *what* happened; it
    /// never stacks a second score on top of the block's value.
    func honorBucket(_ bucket: Bucket, specific: String? = nil) {
        guard !isViewingPast else { return }
        guard !hasLogEntryToday(forBucketId: bucket.id) else {
            // Already honored: just refine the recorded specific.
            if let specific, !specific.trimmingCharacters(in: .whitespaces).isEmpty {
                updateLoggedSpecific(forBucketId: bucket.id, to: specific)
            }
            return
        }
        captureUndo("Honored \u{201C}\(bucket.title)\u{201D}")
        let label = specific?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = LogEntry(
            date: Date(),
            bucketId: bucket.id,
            pointsEarned: bucket.pointValue,
            entryType: .completed,
            title: (label?.isEmpty ?? true) ? bucket.title : label
        )
        logEntries.append(entry)
        persistAll()
    }

    /// Undo today's honoring of a bucket — removes the matching credit.
    func unhonorBucket(_ bucket: Bucket) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        removeLogEntries { entry in
            entry.bucketId == bucket.id
                && cal.isDate(entry.date, inSameDayAs: today)
                && entry.entryType == .completed
        }
        persistAll()
    }

    /// Rewrite the recorded specific on an already-honored bucket.
    private func updateLoggedSpecific(forBucketId bucketId: UUID, to specific: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let idx = logEntries.firstIndex(where: { entry in
            entry.bucketId == bucketId
                && cal.isDate(entry.date, inSameDayAs: today)
                && entry.entryType == .completed
        }) else { return }
        logEntries[idx].title = specific.trimmingCharacters(in: .whitespacesAndNewlines)
        persistAll()
    }

    // MARK: - Bucket day gestures

    /// "Do today" — pin a bucket onto just this day without touching its
    /// repeat pattern.
    func pinBucketToToday(_ bucket: Bucket) {
        guard let idx = buckets.firstIndex(where: { $0.id == bucket.id }) else { return }
        buckets[idx].oneOffPinDate = Date()
        buckets[idx].skipDate = nil
        persistAll()
    }

    /// "Not today" — hide a recurring bucket for this one day only.
    func skipBucketToday(_ bucket: Bucket) {
        guard let idx = buckets.firstIndex(where: { $0.id == bucket.id }) else { return }
        let cal = Calendar.current
        if let oneOff = buckets[idx].oneOffPinDate, cal.isDateInToday(oneOff) {
            buckets[idx].oneOffPinDate = nil
        }
        switch buckets[idx].pinSchedule {
        case .today:
            buckets[idx].pinSchedule = .none
        case .singleDate(let date) where cal.isDateInToday(date):
            buckets[idx].pinSchedule = .none
        default:
            if buckets[idx].isPinnedFor(Date()) {
                buckets[idx].skipDate = cal.startOfDay(for: Date())
            }
        }
        persistAll()
    }

    // MARK: - Band ordering (manual reorder)

    /// Every element in a band on a day, as refs, in display order.
    /// Items the user has manually reordered sort by their `agendaOrder`;
    /// the rest fall back to the sensible default (fixed-timed by time,
    /// buckets, then soft tasks by title). `.anytime` returns the tray's
    /// time-less tasks.
    func orderedBandRefs(_ band: PartOfDay, on day: Date) -> [AgendaElementRef] {
        struct Entry {
            let ref: AgendaElementRef
            let order: Int?
            let typeRank: Int
            let timeKey: Int
            let title: String
        }
        var entries: [Entry] = []

        if band == .anytime {
            for t in tasksPinned(on: day) where t.timeWindow == nil && t.partOfDay == .anytime {
                entries.append(Entry(ref: .task(t.id), order: t.agendaOrder, typeRank: 2, timeKey: 0, title: t.title))
            }
        } else {
            for t in tasksPinned(on: day) where t.timeWindow != nil
                && PartOfDay.band(forMinutes: t.timeWindow!.startMinutes) == band {
                entries.append(Entry(ref: .task(t.id), order: t.agendaOrder, typeRank: 0,
                                     timeKey: t.timeWindow!.startMinutes, title: t.title))
            }
            for b in bucketsPinned(on: day) where b.resolvedBand == band {
                entries.append(Entry(ref: .bucket(b.id), order: b.agendaOrder, typeRank: 1,
                                     timeKey: b.timeWindow?.startMinutes ?? Int.max, title: b.title))
            }
            for t in tasksPinned(on: day) where t.timeWindow == nil && t.partOfDay == band {
                entries.append(Entry(ref: .task(t.id), order: t.agendaOrder, typeRank: 2, timeKey: 0, title: t.title))
            }
        }

        return entries.sorted { a, b in
            if let x = a.order, let y = b.order, x != y { return x < y }
            if a.order != nil && b.order == nil { return true }
            if a.order == nil && b.order != nil { return false }
            if a.typeRank != b.typeRank { return a.typeRank < b.typeRank }
            if a.timeKey != b.timeKey { return a.timeKey < b.timeKey }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }.map(\.ref)
    }

    /// Write a fresh `0..<count` manual order onto the given refs, in the
    /// order supplied. This is the single source of truth for a band's
    /// arrangement after a drag — order persists on every day the items
    /// appear, matching how sections already behave.
    func applyAgendaOrder(_ refs: [AgendaElementRef]) {
        for (i, ref) in refs.enumerated() {
            switch ref {
            case .task(let id):
                if let idx = tasks.firstIndex(where: { $0.id == id }) { tasks[idx].agendaOrder = i }
            case .bucket(let id):
                if let idx = buckets.firstIndex(where: { $0.id == id }) { buckets[idx].agendaOrder = i }
            }
        }
        persistAll()
    }

    /// Pin an existing task onto a day and drop it into a band at the end
    /// of that band's current order. Time-anchored tasks keep their real
    /// time (and thus their time-band); soft tasks take the band as their
    /// `partOfDay`. Used by the per-section "+".
    func pinTask(_ task: FFTask, intoBand band: PartOfDay, on day: Date) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let cal = Calendar.current
        if let skip = tasks[idx].skipDate, cal.isDate(skip, inSameDayAs: day) {
            tasks[idx].skipDate = nil
        }
        if !tasks[idx].isPinnedFor(day) {
            tasks[idx].oneOffPinDate = cal.startOfDay(for: day)
        }
        if tasks[idx].timeWindow == nil {
            tasks[idx].partOfDay = band
        }
        let resolved = tasks[idx].timeWindow != nil
            ? PartOfDay.band(forMinutes: tasks[idx].timeWindow!.startMinutes)
            : band
        var refs = orderedBandRefs(resolved, on: day).filter { $0 != .task(task.id) }
        refs.append(.task(task.id))
        applyAgendaOrder(refs)
    }

    // MARK: - Soft placement (partOfDay)

    /// Set a task's soft placement (the band it floats in, or `.anytime`
    /// to send it back to the tray). Untouched: which days it repeats.
    func setPartOfDay(_ part: PartOfDay, forTaskId taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].partOfDay = part
        persistAll()
    }

    /// Set a bucket's soft placement.
    func setPartOfDay(_ part: PartOfDay, forBucketId bucketId: UUID) {
        guard let idx = buckets.firstIndex(where: { $0.id == bucketId }) else { return }
        buckets[idx].partOfDay = part
        persistAll()
    }

    // MARK: - Day rollover sweep for buckets

    /// Sweep stale one-off / skip flags on buckets at day rollover, the
    /// same way tasks are tidied. Safe to call repeatedly.
    func sweepStaleBucketFlags(asOf today: Date = Calendar.current.startOfDay(for: Date())) {
        let cal = Calendar.current
        var changed = false
        for i in buckets.indices {
            switch buckets[i].pinSchedule {
            case .today:
                buckets[i].pinSchedule = .none; changed = true
            case .singleDate(let date):
                if cal.startOfDay(for: date) < today {
                    buckets[i].pinSchedule = .none; changed = true
                }
            case .none, .daily, .daysOfWeek:
                break
            }
            if let oneOff = buckets[i].oneOffPinDate, cal.startOfDay(for: oneOff) < today {
                buckets[i].oneOffPinDate = nil; changed = true
            }
            if let skip = buckets[i].skipDate, cal.startOfDay(for: skip) < today {
                buckets[i].skipDate = nil; changed = true
            }
        }
        if changed { persistAll() }
    }

    // MARK: - Day templates: resolution

    /// The template id "running" on a day — a per-day swap wins,
    /// otherwise the default-week assignment for that weekday.
    func runningTemplateId(for day: Date) -> UUID? {
        let key = AgendaDayKey.key(for: day)
        if let swap = daySwaps.first(where: { $0.dayKey == key }) {
            return swap.templateId
        }
        let weekday = Calendar.current.component(.weekday, from: day)
        return weekTemplateAssignments.first(where: { $0.weekday == weekday })?.templateId
    }

    /// The template running on a day, resolved to the object.
    func runningTemplate(for day: Date) -> DayTemplate? {
        guard let id = runningTemplateId(for: day) else { return nil }
        return dayTemplates.first(where: { $0.id == id })
    }

    func template(by id: UUID) -> DayTemplate? {
        dayTemplates.first(where: { $0.id == id })
    }

    // MARK: - Day templates: CRUD

    @discardableResult
    func addTemplate(_ template: DayTemplate) -> DayTemplate {
        dayTemplates.append(template)
        persistAll()
        return template
    }

    func updateTemplate(_ template: DayTemplate) {
        guard let idx = dayTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        dayTemplates[idx] = template
        persistAll()
    }

    /// Delete a template and any week assignments / swap records that
    /// pointed at it. Already-stamped concrete items stay on their days
    /// (they're real single-date items now), honoring "stamps, not links."
    func deleteTemplate(_ template: DayTemplate) {
        dayTemplates.removeAll { $0.id == template.id }
        weekTemplateAssignments.removeAll { $0.templateId == template.id }
        daySwaps.removeAll { $0.templateId == template.id }
        persistAll()
    }

    /// Capture a day's current shape as a new named template. Reads the
    /// day's resolved tasks + buckets into element-shapes.
    @discardableResult
    func saveDayAsTemplate(_ day: Date, name: String, preview: String = "") -> DayTemplate {
        var elements: [DayTemplateElement] = []
        for task in tasksPinned(on: day) {
            elements.append(DayTemplateElement(
                kind: .task,
                title: task.title,
                category: task.category,
                pointValue: task.pointValue,
                timeWindow: task.timeWindow,
                partOfDay: task.partOfDay
            ))
        }
        for bucket in bucketsPinned(on: day) {
            elements.append(DayTemplateElement(
                kind: .bucket,
                title: bucket.title,
                category: bucket.category,
                pointValue: bucket.pointValue,
                timeWindow: bucket.timeWindow,
                partOfDay: bucket.partOfDay,
                candidateTitles: bucket.candidateTitles
            ))
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = DayTemplate(
            name: trimmed.isEmpty ? "New Template" : trimmed,
            previewLine: preview,
            elements: elements
        )
        return addTemplate(template)
    }

    // MARK: - Day templates: stamping & swapping

    /// Remove every template-stamped element (task or bucket) on a day,
    /// leaving manual additions (no stamp) in place.
    private func clearStampedElements(onDayKey key: String) {
        tasks.removeAll { $0.templateStamp?.dayKey == key }
        buckets.removeAll { $0.templateStamp?.dayKey == key }
    }

    /// Instantiate a template's elements onto a single day as real,
    /// single-date items, tagged with the stamp so a later swap can
    /// clear exactly these. Does NOT record a swap on its own — callers
    /// that represent a deliberate swap also write a `DaySwapRecord`.
    private func stampElements(of template: DayTemplate, onto day: Date) {
        let key = AgendaDayKey.key(for: day)
        let stamp = TemplateStamp(templateId: template.id, dayKey: key)
        let startOfDay = Calendar.current.startOfDay(for: day)
        for element in template.elements {
            switch element.kind {
            case .task:
                let task = FFTask(
                    title: element.title,
                    category: element.category,
                    pointValue: element.pointValue,
                    pinSchedule: .singleDate(startOfDay),
                    timeWindow: element.timeWindow,
                    partOfDay: element.partOfDay
                )
                var stamped = task
                stamped.templateStamp = stamp
                tasks.append(stamped)
            case .bucket:
                let bucket = Bucket(
                    title: element.title,
                    category: element.category,
                    pointValue: element.pointValue,
                    timeWindow: element.timeWindow,
                    partOfDay: element.partOfDay,
                    pinSchedule: .singleDate(startOfDay),
                    candidateTitles: element.candidateTitles,
                    templateStamp: stamp
                )
                buckets.append(bucket)
            }
        }
    }

    /// Swap a day to a template (the holiday case). Clears the day's
    /// previously-stamped items, stamps the new template's shape, and
    /// records a reversible swap remembering what was running before.
    /// Manual additions on the day are preserved.
    func swapDay(_ day: Date, to template: DayTemplate, applyToPattern: Bool = false) {
        let key = AgendaDayKey.key(for: day)
        let previousId = runningTemplateId(for: day)

        clearStampedElements(onDayKey: key)
        stampElements(of: template, onto: day)

        daySwaps.removeAll { $0.dayKey == key }
        daySwaps.append(DaySwapRecord(
            dayKey: key,
            templateId: template.id,
            previousTemplateId: previousId == template.id ? nil : previousId
        ))

        if applyToPattern {
            let weekday = Calendar.current.component(.weekday, from: day)
            setWeekAssignment(template, forWeekday: weekday, restampCurrentWeek: true)
        }

        persistAll()
    }

    /// One-tap reversal of a day swap: clear the swapped shape and, if a
    /// previous template was running, restore it; otherwise leave the
    /// day on its default-week assignment (re-materialized).
    func revertDaySwap(on day: Date) {
        let key = AgendaDayKey.key(for: day)
        guard let swap = daySwaps.first(where: { $0.dayKey == key }) else { return }
        clearStampedElements(onDayKey: key)
        daySwaps.removeAll { $0.dayKey == key }
        if let prevId = swap.previousTemplateId, let prev = template(by: prevId) {
            stampElements(of: prev, onto: day)
            daySwaps.append(DaySwapRecord(dayKey: key, templateId: prev.id, previousTemplateId: nil))
        }
        persistAll()
        materializeAssignedTemplateIfNeeded(for: day)
    }

    /// The label a previously-running swap reverts to, for the
    /// "↩ Back to [previous]" affordance. Nil when there's nothing to
    /// go back to.
    func swapPreviousTemplateName(on day: Date) -> String? {
        let key = AgendaDayKey.key(for: day)
        guard let swap = daySwaps.first(where: { $0.dayKey == key }) else { return nil }
        guard let prevId = swap.previousTemplateId else { return nil }
        return template(by: prevId)?.name
    }

    /// True when this day is currently running a deliberate swap.
    func dayHasSwap(_ day: Date) -> Bool {
        daySwaps.contains { $0.dayKey == AgendaDayKey.key(for: day) }
    }

    // MARK: - Week assignment

    /// Assign a template to a weekday in the default week. Optionally
    /// re-stamp the matching day in the currently-relevant week so the
    /// change is visible immediately.
    func setWeekAssignment(_ template: DayTemplate, forWeekday weekday: Int, restampCurrentWeek: Bool = true) {
        weekTemplateAssignments.removeAll { $0.weekday == weekday }
        weekTemplateAssignments.append(WeekTemplateAssignment(weekday: weekday, templateId: template.id))
        if restampCurrentWeek, let day = dayInCurrentWeek(forWeekday: weekday) {
            // Only materialize if the day isn't a deliberate swap.
            if !dayHasSwap(day) {
                let key = AgendaDayKey.key(for: day)
                clearStampedElements(onDayKey: key)
                stampElements(of: template, onto: day)
            }
        }
        persistAll()
    }

    /// Clear a weekday's default assignment (and any auto-materialized
    /// stamp for it in the current week).
    func clearWeekAssignment(forWeekday weekday: Int) {
        weekTemplateAssignments.removeAll { $0.weekday == weekday }
        if let day = dayInCurrentWeek(forWeekday: weekday), !dayHasSwap(day) {
            clearStampedElements(onDayKey: AgendaDayKey.key(for: day))
        }
        persistAll()
    }

    func weekAssignmentTemplateId(forWeekday weekday: Int) -> UUID? {
        weekTemplateAssignments.first(where: { $0.weekday == weekday })?.templateId
    }

    private func dayInCurrentWeek(forWeekday weekday: Int) -> Date? {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return nil }
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: interval.start) else { continue }
            if cal.component(.weekday, from: day) == weekday { return day }
        }
        return nil
    }

    /// Lazily materialize a day's default-week template if it hasn't been
    /// stamped yet and isn't a deliberate swap — this is how "similar
    /// days self-assemble" from their named shapes. No-op when there's no
    /// assignment, the day already carries stamped items, or it's swapped.
    func materializeAssignedTemplateIfNeeded(for day: Date) {
        let key = AgendaDayKey.key(for: day)
        guard !dayHasSwap(day) else { return }
        let alreadyStamped = tasks.contains { $0.templateStamp?.dayKey == key }
            || buckets.contains { $0.templateStamp?.dayKey == key }
        guard !alreadyStamped else { return }
        let weekday = Calendar.current.component(.weekday, from: day)
        guard let assignmentId = weekTemplateAssignments.first(where: { $0.weekday == weekday })?.templateId,
              let template = template(by: assignmentId) else { return }
        stampElements(of: template, onto: day)
        persistAll()
    }
}
