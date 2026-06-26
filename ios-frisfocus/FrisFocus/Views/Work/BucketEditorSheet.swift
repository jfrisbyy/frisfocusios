//
//  BucketEditorSheet.swift
//  FrisFocus
//
//  Create or edit a bucket — a time-bound, content-open block. Name,
//  area, point value, which days it repeats, a hard time window or a
//  soft band, and the candidate activities that fit inside it.
//

import SwiftUI
import UIKit

struct BucketEditorSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil when creating a new bucket.
    private let existing: Bucket?
    private let defaultDay: Date?

    @State private var title: String = ""
    @State private var category: Category = .fitness
    @State private var pointValue: Int = 5
    @State private var draft: ScheduleDraft
    @State private var useTimeWindow: Bool
    @State private var partOfDay: PartOfDay = .anytime
    @State private var candidates: [String] = []
    @State private var newCandidate: String = ""

    init(existing: Bucket) {
        self.existing = existing
        self.defaultDay = nil
        _title = State(initialValue: existing.title)
        _category = State(initialValue: existing.category)
        _pointValue = State(initialValue: existing.pointValue)
        _candidates = State(initialValue: existing.candidateTitles)
        _partOfDay = State(initialValue: existing.partOfDay == .anytime ? .morning : existing.partOfDay)
        _useTimeWindow = State(initialValue: existing.timeWindow != nil)
        // Reuse the shared schedule draft by mapping the bucket onto a
        // throwaway task that carries the same schedule + window.
        let proxy = FFTask(
            title: existing.title,
            category: existing.category,
            pointValue: existing.pointValue,
            pinSchedule: existing.pinSchedule,
            timeWindow: existing.timeWindow
        )
        _draft = State(initialValue: ScheduleDraft(task: proxy))
    }

    init(defaultDay: Date? = nil) {
        self.existing = nil
        self.defaultDay = defaultDay
        var proxy = FFTask(title: "", category: .fitness, pointValue: 5)
        if let day = defaultDay {
            proxy.pinSchedule = .singleDate(Calendar.current.startOfDay(for: day))
        }
        _draft = State(initialValue: ScheduleDraft(task: proxy))
        _useTimeWindow = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    areaPicker
                    valueStepper
                    scheduleCard
                    placementCard
                    candidatesCard
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(existing == nil ? "New bucket" : "Edit bucket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canSave)
                }
                if existing != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            if let existing { store.deleteBucket(existing) }
                            dismiss()
                        } label: {
                            Label("Delete bucket", systemImage: "trash")
                                .font(.sans(13, weight: .medium))
                                .foregroundStyle(Theme.alertRed)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "Name", opacity: 0.5)
            TextField("Movement block", text: $title)
                .font(.serif(18, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
        }
    }

    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "Area", opacity: 0.5)
            FlowLayout(spacing: 8) {
                ForEach(Category.allCases, id: \.self) { cat in
                    let selected = category == cat
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        category = cat
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: store.categoryColorHex(cat))).frame(width: 7, height: 7)
                            Text(store.categoryDisplayName(cat))
                                .font(.sans(13, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(selected ? Color(hex: store.categoryColorHex(cat)) : Theme.textPrimary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var valueStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: "Worth (honoring the block)", opacity: 0.5)
            HStack(spacing: 16) {
                Stepper(value: $pointValue, in: 1...50) {
                    Text("\(pointValue) points")
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Which days", opacity: 0.5)
            ScheduleEditorView(draft: $draft)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
    }

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $useTimeWindow.animation(.easeInOut(duration: 0.2))) {
                Text("Commit a time window")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.alertGreen)

            if useTimeWindow {
                Text("Uses the time window set above. The bucket is placed at its real time.")
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A vibe of when")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    HStack(spacing: 8) {
                        ForEach(PartOfDay.bands) { band in
                            let selected = partOfDay == band
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                partOfDay = band
                            } label: {
                                Text(band.displayName)
                                    .font(.sans(13, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selected ? Theme.textPrimary : Theme.textPrimary.opacity(0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.45))
        )
    }

    private var candidatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "What fits (optional)", opacity: 0.5)
            ForEach(candidates, id: \.self) { candidate in
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: store.categoryColorHex(category))).frame(width: 6, height: 6)
                    Text(candidate)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Button {
                        candidates.removeAll { $0 == candidate }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
            }
            HStack(spacing: 10) {
                TextField("Add a fitting activity", text: $newCandidate)
                    .font(.sans(14, weight: .medium))
                    .submitLabel(.done)
                    .onSubmit(addCandidate)
                Button(action: addCandidate) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(trimmedCandidate.isEmpty ? Theme.textPrimary.opacity(0.25) : Theme.alertGreen)
                }
                .buttonStyle(.plain)
                .disabled(trimmedCandidate.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.4))
            )
        }
    }

    // MARK: - Helpers

    private var trimmedCandidate: String {
        newCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addCandidate() {
        guard !trimmedCandidate.isEmpty else { return }
        candidates.append(trimmedCandidate)
        newCandidate = ""
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let window = useTimeWindow ? draft.resolvedTimeWindow : nil
        var schedule = draft.resolvedSchedule
        // A new bucket with no day chosen defaults to the day it's
        // created on so it shows up immediately.
        if case .none = schedule, existing == nil, let day = defaultDay {
            schedule = .singleDate(Calendar.current.startOfDay(for: day))
        }
        let resolvedPart: PartOfDay = useTimeWindow ? .anytime : partOfDay

        if let existing {
            var updated = existing
            updated.title = trimmed
            updated.category = category
            updated.pointValue = pointValue
            updated.pinSchedule = schedule
            updated.timeWindow = window
            updated.partOfDay = resolvedPart
            updated.candidateTitles = candidates
            store.updateBucket(updated)
        } else {
            let bucket = Bucket(
                title: trimmed,
                category: category,
                pointValue: pointValue,
                timeWindow: window,
                partOfDay: resolvedPart,
                pinSchedule: schedule,
                candidateTitles: candidates
            )
            store.addBucket(bucket)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
