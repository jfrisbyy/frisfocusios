//
//  AgendaDayView.swift
//  FrisFocus
//
//  The S9 agenda — one day drawn as soft Morning / Afternoon / Evening
//  bands holding fixed time blocks, flexible buckets, and soft-placed
//  tasks, plus an Anytime tray. A week strip navigates days; the day
//  header shows its running template with a Swap action. The witness
//  model holds throughout: the grid reflects and arranges, it never
//  enforces or grades *when* — nothing ever turns red or reads "late."
//
//  Reached from the schedule icon above Today's Plan (list/agenda
//  toggle). Promotable to the default day landing via a control here.
//

import SwiftUI
import UIKit

/// A reference to a draggable agenda element, encoded as a small string
/// payload for drag-and-drop between bands and the tray.
enum AgendaElementRef: Hashable {
    case task(UUID)
    case bucket(UUID)

    var transferString: String {
        switch self {
        case .task(let id):   return "task:\(id.uuidString)"
        case .bucket(let id): return "bucket:\(id.uuidString)"
        }
    }

    init?(transferString: String) {
        let parts = transferString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "task":   self = .task(id)
        case "bucket": self = .bucket(id)
        default:       return nil
        }
    }
}

struct AgendaDayView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called to flip back to the flat Today's Plan list.
    var onSwitchToList: (() -> Void)? = nil

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var fulfillBucket: Bucket?
    @State private var editBucket: Bucket?
    @State private var scheduleTask: FFTask?
    @State private var showNewBucket: Bool = false
    @State private var showTemplateLibrary: Bool = false
    @State private var showSaveTemplate: Bool = false
    @State private var dropTarget: PartOfDay?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeekStripView(selectedDay: $selectedDay)
                        .padding(.horizontal, 18)

                    dayHeader
                        .padding(.horizontal, 18)

                    bandsStack
                        .padding(.horizontal, 18)

                    anytimeTray
                        .padding(.horizontal, 18)

                    dayFooter
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                }
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let onSwitchToList {
                            onSwitchToList()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    }
                    .accessibilityLabel("Switch to list view")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
            .onChange(of: selectedDay) { _, day in
                store.materializeAssignedTemplateIfNeeded(for: day)
            }
            .onAppear {
                store.materializeAssignedTemplateIfNeeded(for: selectedDay)
            }
        }
        .sheet(item: $fulfillBucket) { bucket in
            BucketFulfillSheet(bucket: bucket)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editBucket) { bucket in
            BucketEditorSheet(existing: bucket)
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $scheduleTask) { task in
            TaskScheduleSheet(task: task)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewBucket) {
            BucketEditorSheet(defaultDay: selectedDay)
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTemplateLibrary) {
            DayTemplateLibrarySheet(day: selectedDay)
                .environment(store)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveDayAsTemplateSheet(day: selectedDay)
                .environment(store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Day header

    @ViewBuilder
    private var dayHeader: some View {
        let template = store.runningTemplate(for: selectedDay)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.headerFormatter.string(from: selectedDay))
                        .font(.serif(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let template {
                        HStack(spacing: 5) {
                            Image(systemName: "square.on.square.dashed")
                                .font(.system(size: 10, weight: .semibold))
                            Text("running \(template.name)")
                                .font(.sans(11, weight: .medium))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    } else {
                        Text("no template")
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                }
                Spacer(minLength: 8)
                swapButton
            }

            if let prev = store.swapPreviousTemplateName(on: selectedDay) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        store.revertDaySwap(on: selectedDay)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back to \(prev)")
                            .font(.sans(11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.alertGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.alertGreen.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var swapButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showTemplateLibrary = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("Swap day")
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.textPrimary.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Swap this day's template")
    }

    // MARK: - Bands

    @ViewBuilder
    private var bandsStack: some View {
        VStack(spacing: 16) {
            ForEach(PartOfDay.bands) { band in
                bandSection(band)
            }
        }
    }

    @ViewBuilder
    private func bandSection(_ band: PartOfDay) -> some View {
        let fixed = fixedTasks(in: band)
        let bucketList = bucketsInBand(band)
        let soft = softTasks(in: band)
        let isEmpty = fixed.isEmpty && bucketList.isEmpty && soft.isEmpty

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: band.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text(band.displayName.uppercased())
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.10))
                    .frame(height: 0.5)
            }

            if isEmpty {
                Text("open")
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 8) {
                    ForEach(fixed) { task in
                        FixedBlockRow(task: task, interactive: isToday) { complete(task) }
                            .contextMenu { taskMenu(task) }
                            .draggable(AgendaElementRef.task(task.id).transferString)
                    }
                    ForEach(bucketList) { bucket in
                        BucketBlockRow(bucket: bucket) { fulfillBucket = bucket }
                            .contextMenu { bucketMenu(bucket) }
                            .draggable(AgendaElementRef.bucket(bucket.id).transferString)
                    }
                    ForEach(soft) { task in
                        SoftTaskRow(task: task, band: band, interactive: isToday) { complete(task) }
                            .contextMenu { taskMenu(task) }
                            .draggable(AgendaElementRef.task(task.id).transferString)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(dropTarget == band ? 0.9 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    dropTarget == band ? Theme.alertGreen.opacity(0.5) : Theme.textPrimary.opacity(0.06),
                    lineWidth: dropTarget == band ? 1.2 : 0.5
                )
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, into: band)
        } isTargeted: { targeted in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                dropTarget = targeted ? band : (dropTarget == band ? nil : dropTarget)
            }
        }
    }

    // MARK: - Anytime tray

    @ViewBuilder
    private var anytimeTray: some View {
        let chips = anytimeTasks()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: PartOfDay.anytime.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text("ANYTIME")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Spacer(minLength: 0)
                Text("off the clock")
                    .font(.serifItalic(11))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }

            if chips.isEmpty {
                Text("Nothing time-less — drag a task here to take it off the clock.")
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowChips(chips) { task in
                    TrayChip(task: task, interactive: isToday) { complete(task) }
                        .contextMenu { taskMenu(task) }
                        .draggable(AgendaElementRef.task(task.id).transferString)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.paperCream.opacity(dropTarget == .anytime ? 1 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    dropTarget == .anytime ? Theme.alertGreen.opacity(0.5) : Theme.textPrimary.opacity(0.08),
                    lineWidth: dropTarget == .anytime ? 1.2 : 0.6
                )
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, into: .anytime)
        } isTargeted: { targeted in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                dropTarget = targeted ? .anytime : (dropTarget == .anytime ? nil : dropTarget)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var dayFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                footerButton(title: "Add bucket", systemImage: "plus.rectangle.on.rectangle") {
                    showNewBucket = true
                }
                footerButton(title: "Save as template", systemImage: "square.and.arrow.down") {
                    showSaveTemplate = true
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.agendaIsDefaultDayView.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.agendaIsDefaultDayView ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.agendaIsDefaultDayView ? Theme.alertGreen : Theme.textPrimary.opacity(0.4))
                    Text("Set agenda as my default day view")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func footerButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.sans(12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context menus

    @ViewBuilder
    private func taskMenu(_ task: FFTask) -> some View {
        Button {
            scheduleTask = task
        } label: {
            Label("Edit schedule", systemImage: "slider.horizontal.3")
        }
        Menu {
            ForEach(PartOfDay.allCases) { part in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        store.setPartOfDay(part, forTaskId: task.id)
                    }
                } label: {
                    Label(part.displayName, systemImage: task.partOfDay == part ? "checkmark" : part.symbol)
                }
            }
        } label: {
            Label("Move to…", systemImage: "arrow.up.and.down.text.horizontal")
        }
        if !task.isPinnedFor(selectedDay) {
            Button {
                store.pinTaskToToday(task)
            } label: {
                Label("Do today", systemImage: "pin")
            }
        } else {
            Button(role: .destructive) {
                store.unpinTaskFromToday(task)
            } label: {
                Label("Not today", systemImage: "pin.slash")
            }
        }
    }

    @ViewBuilder
    private func bucketMenu(_ bucket: Bucket) -> some View {
        Button {
            editBucket = bucket
        } label: {
            Label("Edit bucket", systemImage: "slider.horizontal.3")
        }
        Menu {
            ForEach(PartOfDay.allCases) { part in
                Button {
                    store.setPartOfDay(part, forBucketId: bucket.id)
                } label: {
                    Label(part.displayName, systemImage: bucket.partOfDay == part ? "checkmark" : part.symbol)
                }
            }
        } label: {
            Label("Move to…", systemImage: "arrow.up.and.down.text.horizontal")
        }
        Button(role: .destructive) {
            store.deleteBucket(bucket)
        } label: {
            Label("Delete bucket", systemImage: "trash")
        }
    }

    // MARK: - Element queries

    private func fixedTasks(in band: PartOfDay) -> [FFTask] {
        store.tasksPinned(on: selectedDay)
            .filter { $0.timeWindow != nil && PartOfDay.band(forMinutes: $0.timeWindow!.startMinutes) == band }
            .sorted { ($0.timeWindow?.startMinutes ?? 0) < ($1.timeWindow?.startMinutes ?? 0) }
    }

    private func softTasks(in band: PartOfDay) -> [FFTask] {
        store.tasksPinned(on: selectedDay)
            .filter { $0.timeWindow == nil && $0.partOfDay == band }
            .sorted { $0.title < $1.title }
    }

    private func anytimeTasks() -> [FFTask] {
        store.tasksPinned(on: selectedDay)
            .filter { $0.timeWindow == nil && $0.partOfDay == .anytime }
            .sorted { $0.title < $1.title }
    }

    private func bucketsInBand(_ band: PartOfDay) -> [Bucket] {
        store.bucketsPinned(on: selectedDay).filter { $0.resolvedBand == band }
    }

    // MARK: - Actions

    private func complete(_ task: FFTask) {
        guard isToday else { return }
        guard !store.hasLogEntryToday(forTaskId: task.id) else {
            store.uncompleteTask(task)
            return
        }
        if task.requiresQuantityLogging {
            // Quantity tasks are completed from the list/needs-you flow;
            // here a tap honors the simplest case with no amount.
            store.captureUndo("Completed \u{201C}\(task.title)\u{201D}")
            store.completeTask(task)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.captureUndo("Completed \u{201C}\(task.title)\u{201D}")
            store.completeTask(task)
        }
    }

    /// Resolve a dropped payload onto a band (or the tray). Sets the
    /// element's soft placement; fixed-timed tasks keep their window.
    private func handleDrop(_ items: [String], into band: PartOfDay) -> Bool {
        dropTarget = nil
        guard let raw = items.first, let ref = AgendaElementRef(transferString: raw) else { return false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            switch ref {
            case .task(let id):
                store.setPartOfDay(band, forTaskId: id)
            case .bucket(let id):
                store.setPartOfDay(band, forBucketId: id)
            }
        }
        return true
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}

// MARK: - Week strip

struct WeekStripView: View {
    @Environment(Store.self) private var store
    @Binding var selectedDay: Date

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDay) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekDays, id: \.self) { day in
                dayPill(day)
            }
        }
    }

    @ViewBuilder
    private func dayPill(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let hasShape = store.runningTemplate(for: day) != nil
            || !store.tasksPinned(on: day).isEmpty
            || !store.bucketsPinned(on: day).isEmpty

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedDay = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text(Self.weekdayFormatter.string(from: day).uppercased())
                    .font(.sans(9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle((isSelected ? Theme.warmWheat : Theme.textPrimary).opacity(isSelected ? 0.9 : 0.5))
                Text(Self.dayNumFormatter.string(from: day))
                    .font(.serif(16, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.warmWheat : Theme.textPrimary.opacity(0.85))
                Circle()
                    .fill(hasShape ? (isSelected ? Theme.warmWheat : Theme.alertGreen) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? Theme.alertGreen.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AgendaDateLabels.full.string(from: day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let dayNumFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
}

enum AgendaDateLabels {
    static let full: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; return f
    }()
}

// MARK: - Simple wrapping chip layout

/// A lightweight wrapping flow layout for the Anytime tray chips.
struct FlowChips<Item: Identifiable, Content: View>: View {
    private let items: [Item]
    private let content: (Item) -> Content

    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// Wrapping chip rows use the shared `FlowLayout` (Views/Circles).
