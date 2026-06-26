//
//  DayTemplateLibrarySheet.swift
//  FrisFocus
//
//  The Swap-day surface and template library. Lists saved day-shapes
//  (the running one marked CURRENT), each with a one-line preview, and
//  stamps a chosen shape onto the day — replacing that one day's
//  template items while leaving the regular pattern and other days
//  untouched. Stamping is reversible; the user is always asked first.
//  A scope choice widens a swap to a weekday pattern.
//

import SwiftUI
import UIKit

struct DayTemplateLibrarySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date

    @State private var pendingTemplate: DayTemplate?
    @State private var applyToPattern: Bool = false
    @State private var showNewTemplate: Bool = false

    private var currentId: UUID? { store.runningTemplateId(for: day) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    if store.dayTemplates.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.dayTemplates) { template in
                            templateRow(template)
                        }
                    }
                    newFromScratchButton
                    weekAssignmentSection
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Set \(Self.dayName.string(from: day)) to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .sheet(isPresented: $showNewTemplate) {
            SaveDayAsTemplateSheet(day: day, mode: .blank)
                .environment(store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            pendingTemplate.map { "Set this day to \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stamp onto this day") {
                if let t = pendingTemplate { swap(to: t, pattern: false) }
            }
            Button("Apply to every \(Self.weekdayName.string(from: day))") {
                if let t = pendingTemplate { swap(to: t, pattern: true) }
            }
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
        } message: {
            if let t = pendingTemplate {
                Text("Stamps \(t.name)'s shape onto the day. Your current items won't show — you can swap back anytime.")
            }
        }
    }

    private var intro: some View {
        Text("Stamps a shape onto the day. Your current items won't show — you can swap back anytime.")
            .font(.serifItalic(13))
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        Text("No templates yet. Save a day's shape as a template, or start one from scratch.")
            .font(.serifItalic(13))
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func templateRow(_ template: DayTemplate) -> some View {
        let isCurrent = currentId == template.id
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isCurrent { return }
            pendingTemplate = template
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(template.name)
                            .font(.serif(17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if isCurrent {
                            Text("CURRENT")
                                .font(.sans(8, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.alertGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.alertGreen.opacity(0.12)))
                        }
                    }
                    Text(previewLine(template))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !isCurrent {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Theme.alertGreen.opacity(0.06) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Theme.alertGreen.opacity(0.3) : Theme.textPrimary.opacity(0.07),
                        lineWidth: isCurrent ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteTemplate(template)
            } label: {
                Label("Delete template", systemImage: "trash")
            }
        }
    }

    private var newFromScratchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showNewTemplate = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("New template from scratch")
                    .font(.sans(13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Week assignment

    @ViewBuilder
    private var weekAssignmentSection: some View {
        if !store.dayTemplates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowText(text: "Default week", opacity: 0.5)
                Text("Assign a shape to each weekday so similar days assemble themselves.")
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(1...7, id: \.self) { weekday in
                    weekdayAssignmentRow(weekday)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.4))
            )
        }
    }

    @ViewBuilder
    private func weekdayAssignmentRow(_ weekday: Int) -> some View {
        let assignedId = store.weekAssignmentTemplateId(forWeekday: weekday)
        HStack(spacing: 10) {
            Text(Calendar.current.weekdaySymbols[weekday - 1])
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .frame(width: 92, alignment: .leading)
            Menu {
                Button("None") { store.clearWeekAssignment(forWeekday: weekday) }
                ForEach(store.dayTemplates) { template in
                    Button(template.name) {
                        store.setWeekAssignment(template, forWeekday: weekday)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(assignedId.flatMap { store.template(by: $0)?.name } ?? "None")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(assignedId == nil ? Theme.textPrimary.opacity(0.4) : Theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.05))
                )
            }
        }
    }

    // MARK: - Helpers

    private func previewLine(_ template: DayTemplate) -> String {
        if !template.previewLine.trimmingCharacters(in: .whitespaces).isEmpty {
            return template.previewLine
        }
        let names = template.elements.prefix(3).map { $0.title.lowercased() }
        if names.isEmpty { return "an empty day" }
        return names.joined(separator: " · ")
    }

    private func swap(to template: DayTemplate, pattern: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.3)) {
            store.swapDay(day, to: template, applyToPattern: pattern)
        }
        pendingTemplate = nil
        dismiss()
    }

    private static let dayName: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let weekdayName: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

// MARK: - Save as template

struct SaveDayAsTemplateSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Mode { case captureDay, blank }

    let day: Date
    var mode: Mode = .captureDay

    @State private var name: String = ""
    @State private var preview: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(mode == .captureDay
                         ? "Capture this day's shape as a reusable template."
                         : "Name a new, empty template — add its shape by saving a day onto it later.")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)

                    field(label: "Name", placeholder: "Work Day", text: $name)
                    field(label: "Preview line (optional)", placeholder: "deep work · gym · early night", text: $preview)
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(mode == .captureDay ? "Save as template" : "New template")
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
            }
        }
    }

    @ViewBuilder
    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(text: label, opacity: 0.5)
            TextField(placeholder, text: text)
                .font(.serif(17, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        switch mode {
        case .captureDay:
            store.saveDayAsTemplate(day, name: trimmed, preview: preview)
        case .blank:
            store.addTemplate(DayTemplate(name: trimmed, previewLine: preview))
        }
        dismiss()
    }
}
