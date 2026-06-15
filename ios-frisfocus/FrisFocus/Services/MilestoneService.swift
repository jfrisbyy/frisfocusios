//
//  MilestoneService.swift
//  FrisFocus
//
//  Milestones are scored: a deliberately large, one-time reward that
//  lands on the day it's achieved. Completing one writes a `.milestone`
//  LogEntry so its value folds into that day's total (and therefore the
//  week and season totals) exactly like a task completion — even when the
//  value far exceeds the daily target. Un-completing pulls the entry back.
//
//  Milestones can also be broken into smaller steps. By default steps
//  are progress-only checkmarks; when a milestone opts into "points per
//  step", each step's value is credited (as a `.milestoneStep` entry)
//  on the day it's checked, and the remainder lands at completion.
//
//  Each carries a documented journey too — photos and voice memos in
//  `attachments`, plus linked journal notes — all managed here so every
//  mutation persists and refreshes the milestone nudges.
//

import Foundation
import SwiftUI
import UIKit

extension Store {
    // MARK: - Scoring

    /// Sum of step credits already written for a milestone.
    private func creditedStepPoints(for milestoneId: UUID) -> Int {
        logEntries
            .filter { $0.milestoneId == milestoneId && $0.entryType == .milestoneStep }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    /// Mark a milestone achieved today, crediting its reward once.
    /// For "points per step" milestones only the not-yet-credited
    /// remainder lands, so step credits never double-count. The credit
    /// lands on today's local day. No-op if already completed.
    func completeMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        guard currentSeason.milestones[idx].completedDate == nil else { return }

        let now = Date()
        currentSeason.milestones[idx].completedDate = now
        currentSeason.milestones[idx].status = .cleared

        let target = currentSeason.milestones[idx]
        let value: Int
        if target.pointsPerStep {
            value = max(0, target.pointValue - creditedStepPoints(for: target.id))
        } else {
            value = target.pointValue
        }
        if value != 0 {
            logEntries.append(
                LogEntry(
                    date: now,
                    taskId: nil,
                    todoId: nil,
                    milestoneId: milestone.id,
                    pointsEarned: value,
                    entryType: .milestone
                )
            )
        }

        let clearedCount = currentSeason.milestones.filter { $0.isCompleted }.count
        recordMilestoneSignal(
            title: currentSeason.milestones[idx].title,
            done: clearedCount,
            total: currentSeason.milestones.count
        )

        // Milestone-ending seasons complete the moment the last milestone
        // lands. Offer (never force) starting the next season — nothing is
        // wiped until the user acts on the prompt.
        if currentSeason.resolvedEndMode == .milestones,
           !currentSeason.milestones.isEmpty,
           currentSeason.milestones.allSatisfy({ $0.isCompleted }) {
            showSeasonCompletePrompt = true
        }

        persistAll()
        refreshMilestoneNudges()
    }

    /// Undo a milestone completion, removing its completion credit so
    /// the score reflects the new state honestly. Step credits stay —
    /// the steps are still checked.
    func uncompleteMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        currentSeason.milestones[idx].completedDate = nil
        currentSeason.milestones[idx].status = .inMotion
        logEntries.removeAll { $0.milestoneId == milestone.id && $0.entryType == .milestone }
        persistAll()
        refreshMilestoneNudges()
    }

    // MARK: - CRUD

    /// Append a new milestone to the current season. Milestones start
    /// unscheduled (`weekNumber` 1) and carry an optional `targetDate`
    /// the user can set from the editor.
    @discardableResult
    func addMilestone(title: String, targetDate: Date? = nil, pointValue: Int, pointsPerStep: Bool = false) -> Milestone {
        var milestone = Milestone(
            seasonId: currentSeason.id,
            weekNumber: 1,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .upcoming,
            pointValue: max(0, pointValue)
        )
        milestone.targetDate = targetDate
        milestone.pointsPerStep = pointsPerStep
        currentSeason.milestones.append(milestone)
        persistAll()
        refreshMilestoneNudges()
        return milestone
    }

    /// Update a milestone in place. If the value changes while the
    /// milestone is already completed, its credited LogEntry is
    /// re-stamped (to the remainder, for points-per-step milestones)
    /// so the score stays in sync.
    func updateMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        var updated = milestone
        updated.title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.weekNumber = max(1, milestone.weekNumber)
        updated.pointValue = max(0, milestone.pointValue)
        currentSeason.milestones[idx] = updated

        if updated.isCompleted {
            let value: Int
            if updated.pointsPerStep {
                value = max(0, updated.pointValue - creditedStepPoints(for: updated.id))
            } else {
                value = updated.pointValue
            }
            if let entryIdx = logEntries.firstIndex(where: { $0.milestoneId == updated.id && $0.entryType == .milestone }) {
                logEntries[entryIdx].pointsEarned = value
            }
        }
        persistAll()
        refreshMilestoneNudges()
    }

    /// Delete a milestone, any credit it produced, and its on-disk
    /// journey media.
    func deleteMilestone(_ milestone: Milestone) {
        for attachment in milestone.attachments {
            MilestoneMediaStore.delete(attachment)
        }
        currentSeason.milestones.removeAll { $0.id == milestone.id }
        logEntries.removeAll { $0.milestoneId == milestone.id }
        persistAll()
        refreshMilestoneNudges()
    }

    /// Look up a milestone by id in the current season.
    func milestone(by id: UUID) -> Milestone? {
        currentSeason.milestones.first { $0.id == id }
    }

    // MARK: - Steps

    /// Append a step to the end of a milestone's list.
    func addMilestoneStep(to milestoneId: UUID, title: String, pointValue: Int = 0) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextIndex = (currentSeason.milestones[idx].steps.map(\.orderIndex).max() ?? -1) + 1
        currentSeason.milestones[idx].steps.append(
            MilestoneStep(title: trimmed, orderIndex: nextIndex, pointValue: max(0, pointValue))
        )
        persistAll()
    }

    /// Edit a step's title and/or per-step value. If the value changes
    /// while the step is checked on a points-per-step milestone, its
    /// credited entry is re-stamped.
    func updateMilestoneStep(_ step: MilestoneStep, in milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }),
              let sIdx = currentSeason.milestones[mIdx].steps.firstIndex(where: { $0.id == step.id })
        else { return }
        var updated = step
        updated.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.pointValue = max(0, step.pointValue)
        currentSeason.milestones[mIdx].steps[sIdx] = updated

        if currentSeason.milestones[mIdx].pointsPerStep, updated.isCompleted,
           let entryIdx = logEntries.firstIndex(where: { $0.milestoneStepId == updated.id }) {
            logEntries[entryIdx].pointsEarned = updated.pointValue
        }
        persistAll()
    }

    /// Remove a step and reverse any credit it produced.
    func deleteMilestoneStep(_ step: MilestoneStep, from milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        currentSeason.milestones[mIdx].steps.removeAll { $0.id == step.id }
        logEntries.removeAll { $0.milestoneStepId == step.id }
        persistAll()
    }

    /// Reorder steps (List `.onMove` semantics) and rewrite indices.
    func moveMilestoneSteps(in milestoneId: UUID, from source: IndexSet, to destination: Int) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        var ordered = currentSeason.milestones[mIdx].sortedSteps
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, step) in ordered.enumerated() {
            if let sIdx = currentSeason.milestones[mIdx].steps.firstIndex(where: { $0.id == step.id }) {
                currentSeason.milestones[mIdx].steps[sIdx].orderIndex = i
            }
        }
        persistAll()
    }

    /// Check / uncheck a step. On a "points per step" milestone,
    /// checking credits the step's value to today via a
    /// `.milestoneStep` entry; unchecking removes exactly that credit.
    func toggleMilestoneStep(_ step: MilestoneStep, in milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }),
              let sIdx = currentSeason.milestones[mIdx].steps.firstIndex(where: { $0.id == step.id })
        else { return }

        if currentSeason.milestones[mIdx].steps[sIdx].isCompleted {
            currentSeason.milestones[mIdx].steps[sIdx].completedDate = nil
            logEntries.removeAll { $0.milestoneStepId == step.id }
        } else {
            let now = Date()
            currentSeason.milestones[mIdx].steps[sIdx].completedDate = now
            let value = currentSeason.milestones[mIdx].steps[sIdx].pointValue
            if currentSeason.milestones[mIdx].pointsPerStep, value != 0 {
                logEntries.append(
                    LogEntry(
                        date: now,
                        taskId: nil,
                        todoId: nil,
                        milestoneId: milestoneId,
                        milestoneStepId: step.id,
                        pointsEarned: value,
                        entryType: .milestoneStep
                    )
                )
            }
            if currentSeason.milestones[mIdx].status == .upcoming {
                currentSeason.milestones[mIdx].status = .inMotion
            }
        }
        persistAll()
    }

    // MARK: - Journey attachments

    /// Save a picked photo to disk and attach it to the milestone.
    @discardableResult
    func addMilestonePhoto(_ image: UIImage, to milestoneId: UUID) -> MilestoneAttachment? {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }),
              let attachment = MilestoneMediaStore.savePhoto(image)
        else { return nil }
        currentSeason.milestones[mIdx].attachments.append(attachment)
        persistAll()
        return attachment
    }

    /// Attach an already-recorded voice memo (file in Documents).
    @discardableResult
    func addMilestoneVoiceMemo(filename: String, duration: TimeInterval, to milestoneId: UUID) -> MilestoneAttachment? {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return nil }
        let attachment = MilestoneAttachment(kind: .voiceMemo, filename: filename, duration: duration)
        currentSeason.milestones[mIdx].attachments.append(attachment)
        persistAll()
        return attachment
    }

    /// Remove a journey attachment and its on-disk file.
    func deleteMilestoneAttachment(_ attachment: MilestoneAttachment, from milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        currentSeason.milestones[mIdx].attachments.removeAll { $0.id == attachment.id }
        MilestoneMediaStore.delete(attachment)
        persistAll()
    }

    // MARK: - Linked notes

    /// Link an existing journal note to the milestone (idempotent).
    func linkNote(_ noteId: UUID, to milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }),
              !currentSeason.milestones[mIdx].linkedNoteIds.contains(noteId)
        else { return }
        currentSeason.milestones[mIdx].linkedNoteIds.append(noteId)
        persistAll()
    }

    /// Remove a note link (the note itself stays in the journal).
    func unlinkNote(_ noteId: UUID, from milestoneId: UUID) {
        guard let mIdx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        currentSeason.milestones[mIdx].linkedNoteIds.removeAll { $0 == noteId }
        persistAll()
    }

    /// The linked notes that still exist, newest first.
    func linkedNotes(for milestone: Milestone) -> [Note] {
        milestone.linkedNoteIds
            .compactMap { id in notes.first { $0.id == id } }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Journey ordering helpers

    /// The milestones in week order — the journey the zone renders.
    var journeyMilestones: [Milestone] {
        currentSeason.milestones.sorted {
            if $0.weekNumber != $1.weekNumber { return $0.weekNumber < $1.weekNumber }
            return $0.title < $1.title
        }
    }

    /// The first not-yet-completed milestone in week order — the one
    /// "in motion" that gets the warm emphasis on the homepage.
    var nextMilestoneInMotion: Milestone? {
        journeyMilestones.first { !$0.isCompleted }
    }

    // MARK: - Nudges

    /// Re-schedule the single gentle local notification per milestone
    /// whose target week hasn't started yet; cancel the rest.
    func refreshMilestoneNudges() {
        MilestoneNudgeService.refresh(for: currentSeason)
    }

    // MARK: - Season total

    /// The running season total — every point logged since the season
    /// started: daily task points, booster bonuses, penalties, avoidance
    /// deductions, milestone step credits, and milestone completions all
    /// fold in naturally because each writes a `LogEntry`.
    var seasonTotalScore: Int {
        let start = Calendar.current.startOfDay(for: currentSeason.startDate)
        return logEntries
            .filter { $0.date >= start }
            .map(\.pointsEarned)
            .reduce(0, +)
    }
}
