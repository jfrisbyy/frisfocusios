//
//  AvoidanceManagerView.swift
//  FrisFocus
//
//  "Behaviors to reduce" — the standalone avoidance manager. Lists every
//  AvoidanceItem the user has added, shows week-to-date occurrence count
//  and points impact, and exposes a +1 log button per item plus an
//  inline add / edit / delete flow. Calm, factual, private — never
//  broadcast.
//

import SwiftUI
import UIKit

struct AvoidanceManagerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd: Bool = false
    @State private var editing: AvoidanceItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if store.avoidanceItems.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.avoidanceItems) { item in
                                AvoidanceItemCard(
                                    item: item,
                                    onLog: { logOccurrence(item) },
                                    onUndo: { undoLatest(item) },
                                    onEdit: { editing = item },
                                    onDelete: { delete(item) }
                                )
                            }
                        }
                    }

                    addButton

                    privacyFooter

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Theme.warmWheat)
            .navigationTitle("Behaviors to reduce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .sheet(isPresented: $showAdd) {
                AvoidanceItemFormView(editing: nil)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editing) { item in
                AvoidanceItemFormView(editing: item)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Private accounting")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Name a few things you'd like to reduce this season. Some cost points every time; others stay free until you pass a limit you set. Never shown to anyone else.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing tracked yet")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Add a behavior below to start counting.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAdd = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                Text("Add a behavior")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var privacyFooter: some View {
        Text("Behaviors and occurrences stay on this device. They never appear in friends' feeds, signals, or stories.")
            .font(.serifItalic(12))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func logOccurrence(_ item: AvoidanceItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.logAvoidanceOccurrence(item)
    }

    private func undoLatest(_ item: AvoidanceItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.undoLatestAvoidanceOccurrence(item)
    }

    private func delete(_ item: AvoidanceItem) {
        store.deleteAvoidanceItem(item)
    }
}

// MARK: - Item card

private struct AvoidanceItemCard: View {
    @Environment(Store.self) private var store
    let item: AvoidanceItem
    let onLog: () -> Void
    let onUndo: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitleText)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))

                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    Button("Edit", systemImage: "pencil") { onEdit() }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }

            if item.usesFreeAllowance {
                FrequencyMeter(
                    count: windowCount,
                    freeCount: item.freeCount,
                    window: item.window,
                    pointsLost: pointsThisWindow
                )
            } else {
                HStack(spacing: 8) {
                    statBlock(value: "\(occurrenceCount)", label: occurrenceLabel)
                    Divider()
                        .frame(height: 22)
                        .overlay(Theme.textPrimary.opacity(0.1))
                    statBlock(value: "\u{2212}\(pointsThisWeek)", label: "pts this week")
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button(action: onLog) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Log occurrence")
                            .font(.sans(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.warmWheat)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Theme.alertAmber)
                    )
                }
                .buttonStyle(.plain)

                if occurrenceCount > 0 {
                    Button(action: onUndo) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .regular))
                            Text("Undo last")
                                .font(.sans(12, weight: .regular))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var occurrenceCount: Int {
        store.occurrencesThisWeek(for: item).count
    }

    private var occurrenceLabel: String {
        occurrenceCount == 1 ? "time this week" : "times this week"
    }

    private var pointsThisWeek: Int {
        store.avoidancePointsThisWeek(for: item)
    }

    /// Occurrences inside the item's configured window (week or month).
    private var windowCount: Int {
        store.avoidanceCountInWindow(for: item)
    }

    /// Points deducted inside the item's window.
    private var pointsThisWindow: Int {
        store.avoidancePointsInWindow(for: item)
    }

    /// Line under the name describing the shape and its cost.
    private var subtitleText: String {
        switch item.negativeType {
        case .perInstance:
            return "\u{2212}\(item.pointsPerOccurrence) pts each time"
        case .frequencyThreshold:
            return "Free up to \(item.freeCount)/\(item.window.displayName) \u{00B7} \u{2212}\(item.pointsPerOccurrence) after"
        case .tiered:
            guard let first = item.tiers.first, let worst = item.tiers.last else {
                return "\u{2212}\(item.pointsPerOccurrence) pts each time"
            }
            return "\u{2212}\(abs(first.points)) for one \u{00B7} \u{2212}\(abs(worst.points)) at \(worst.threshold)+ in a day"
        }
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.sans(10, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
    }
}

// MARK: - Frequency meter
//
// The neutral running counter for a frequency-threshold negative. The
// free allowance is always visible *before* it's crossed, so the count
// approaching the line is never an ambush. Stays calm (grey) until the
// count exceeds the free count, then the overflow reads amber with the
// points lost.

private struct FrequencyMeter: View {
    let count: Int
    let freeCount: Int
    let window: NegativeWindow
    let pointsLost: Int

    private var over: Int { max(0, count - freeCount) }
    private var freeUsed: Int { min(count, max(0, freeCount)) }
    private var freeLeft: Int { max(0, freeCount - count) }
    private var isOver: Bool { over > 0 }

    /// Pips read cleanly for small allowances; large ones use a bar.
    private var usePips: Bool { freeCount + over <= 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if usePips { pips } else { bar }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pips: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(freeCount, 0), id: \.self) { i in
                Circle()
                    .fill(i < freeUsed ? Theme.textPrimary.opacity(0.5) : Color.clear)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().strokeBorder(Theme.textPrimary.opacity(0.28), lineWidth: 1)
                    )
            }
            if isOver {
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.16))
                    .frame(width: 1, height: 13)
                    .padding(.horizontal, 1)
                ForEach(0..<over, id: \.self) { _ in
                    Circle()
                        .fill(Theme.alertAmber)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let totalSlots = max(freeCount + over, 1)
            let unit = geo.size.width / CGFloat(totalSlots)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textPrimary.opacity(0.08))
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.4))
                        .frame(width: unit * CGFloat(freeUsed))
                    if isOver {
                        Capsule()
                            .fill(Theme.alertAmber)
                            .frame(width: unit * CGFloat(over))
                    }
                }
            }
        }
        .frame(height: 8)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Text("\(min(count, freeCount)) of \(freeCount) this \(window.displayName)")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.62))
            if isOver {
                Text("\u{00B7}").foregroundStyle(Theme.textPrimary.opacity(0.3))
                Text("\(over) over \u{00B7} \u{2212}\(pointsLost) pts")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.alertAmber)
            } else if freeLeft == 0 {
                Text("\u{00B7}").foregroundStyle(Theme.textPrimary.opacity(0.3))
                Text("at your limit")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
        }
    }
}

// MARK: - Add / edit form

private struct AvoidanceItemFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: AvoidanceItem?

    @State private var name: String
    @State private var pointsPerOccurrence: Int
    @State private var note: String
    @State private var category: Category?
    @State private var negativeType: NegativeType
    @State private var window: NegativeWindow
    @State private var freeCount: Int
    /// The second step of a tiered negative. Two steps covers every
    /// paired-row negative people actually keep by hand ("Alcohol" and
    /// "Alcohol 2+"); the model holds as many as anyone wants.
    @State private var escalateAt: Int
    @State private var escalatedPoints: Int

    init(editing: AvoidanceItem?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _pointsPerOccurrence = State(initialValue: editing?.pointsPerOccurrence ?? 5)
        _note = State(initialValue: editing?.note ?? "")
        _category = State(initialValue: editing?.category)
        _negativeType = State(initialValue: editing?.negativeType ?? .perInstance)
        _window = State(initialValue: editing?.window ?? .weekly)
        let existingFree = editing?.freeCount ?? 0
        _freeCount = State(initialValue: existingFree > 0 ? existingFree : 2)
        let escalation = (editing?.tiers.count ?? 0) > 1 ? editing?.tiers.last : nil
        _escalateAt = State(initialValue: escalation?.threshold ?? 2)
        _escalatedPoints = State(initialValue: escalation.map { abs($0.points) } ?? 15)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. doomscroll past midnight", text: $name, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Name something concrete you'd like to reduce.")
                }

                Section {
                    Picker("Shape", selection: $negativeType.animation(.easeInOut(duration: 0.2))) {
                        ForEach(NegativeType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if negativeType == .frequencyThreshold {
                        Picker("Window", selection: $window) {
                            Text("Per week").tag(NegativeWindow.weekly)
                            Text("Per month").tag(NegativeWindow.monthly)
                        }
                        .pickerStyle(.segmented)

                        Stepper(value: $freeCount, in: 1...30) {
                            HStack {
                                Text("Free up to")
                                Spacer()
                                Text("\(freeCount)\u{00D7}")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                } header: {
                    Text("Shape")
                } footer: {
                    Text(negativeType.blurb)
                }

                Section {
                    Stepper(value: $pointsPerOccurrence, in: 1...50) {
                        HStack {
                            Text(costRowLabel)
                            Spacer()
                            Text("\u{2212}\(pointsPerOccurrence) pts")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.alertAmber)
                        }
                    }

                    if negativeType == .tiered {
                        Stepper(value: $escalateAt, in: 2...10) {
                            HStack {
                                Text("Gets worse at")
                                Spacer()
                                Text("\(escalateAt)\u{00D7} a day")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        Stepper(value: $escalatedPoints, in: 1...80) {
                            HStack {
                                Text("Then it costs")
                                Spacer()
                                Text("\u{2212}\(escalatedPoints) pts")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.alertRed)
                            }
                        }
                    }

                    if negativeType == .frequencyThreshold {
                        Text(freqPreview)
                            .font(.serifItalic(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    }
                    if negativeType == .tiered {
                        Text(tieredPreview)
                            .font(.serifItalic(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    }
                } header: {
                    Text("Cost")
                } footer: {
                    Text(costFooter)
                }

                Section {
                    Picker("Area", selection: $category) {
                        Text("None").tag(Category?.none)
                        ForEach(store.currentSeason.categories.map(\.category), id: \.self) { cat in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: store.categoryColorHex(cat)))
                                    .frame(width: 8, height: 8)
                                Text(store.categoryDisplayName(cat))
                            }
                            .tag(Category?.some(cat))
                        }
                    }
                } header: {
                    Text("Area (optional)")
                } footer: {
                    Text("Link this negative to the area it pulls down.")
                }

                Section {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .font(.serifItalic(14))
                        .lineLimit(1...4)
                } header: {
                    Text("Note")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "Add behavior" : "Edit behavior")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var costRowLabel: String {
        switch negativeType {
        case .frequencyThreshold: return "Past the limit"
        case .tiered: return "One in a day"
        case .perInstance: return "Per occurrence"
        }
    }

    private var costFooter: String {
        switch negativeType {
        case .perInstance:
            return "How many points each logged occurrence quietly deducts from your weekly total."
        case .frequencyThreshold:
            return "The free ones stay neutral \u{2014} they never cost points. Each occurrence past the limit deducts this from your \(window.displayName)ly total."
        case .tiered:
            return "One in a day costs the smaller amount. Reaching the next step replaces it with the bigger one \u{2014} it doesn't stack on top."
        }
    }

    private var freqPreview: String {
        "First \(freeCount) this \(window.displayName) are free \u{00B7} each one after is \u{2212}\(pointsPerOccurrence) pts."
    }

    private var tieredPreview: String {
        let worse = max(escalatedPoints, pointsPerOccurrence)
        return "One in a day is \u{2212}\(pointsPerOccurrence). At \(escalateAt) the day becomes \u{2212}\(worse) altogether \u{2014} not \u{2212}\(pointsPerOccurrence + worse)."
    }

    /// The tier list this editor describes, or empty for other shapes.
    private var builtTiers: [NegativeTier] {
        guard negativeType == .tiered else { return [] }
        return [
            NegativeTier(threshold: 1, points: pointsPerOccurrence),
            // Never let the second step cost LESS than the first — a
            // negative that gets cheaper the more you do it is not a
            // thing anyone means.
            NegativeTier(threshold: escalateAt, points: max(escalatedPoints, pointsPerOccurrence)),
        ]
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let editing {
            var updated = editing
            updated.name = name
            updated.pointsPerOccurrence = pointsPerOccurrence
            updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            updated.category = category
            updated.negativeType = negativeType
            updated.window = window
            updated.freeCount = freeCount
            updated.tiers = builtTiers
            store.updateAvoidanceItem(updated)
        } else {
            store.addAvoidanceItem(
                name: name,
                pointsPerOccurrence: pointsPerOccurrence,
                note: note,
                category: category,
                negativeType: negativeType,
                window: window,
                freeCount: freeCount,
                tiers: builtTiers
            )
        }
        dismiss()
    }
}

#Preview {
    AvoidanceManagerView()
        .environment(Store())
}
