//
//  FocusStartSheet.swift
//  FrisFocus
//
//  F1 — entry sheet for a focus block. Pick a duration (25 / 45 / 60
//  or custom), an optional label, and optionally link a personal task
//  to credit on a clean block. Submitting hands control to
//  `FocusModeView` via the `onStart` callback so the host can swap
//  presentation modes (sheet → full-screen cover).
//

import SwiftUI
import UIKit

struct FocusStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(FocusBlockingService.self) private var blocking

    let onStart: (TimeInterval, String?, [FocusTaskAttachment]) -> Void

    @State private var selectedMinutes: Int = 45
    @State private var customMinutes: Int = 30
    @State private var useCustom: Bool = false
    @State private var label: String = ""
    /// Ordered list of attached task ids — preserves tap order in the
    /// running screen's task tray.
    @State private var selectedTaskIds: [UUID] = []
    @State private var showBlockList = false

    private let presets: [Int] = [25, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionHeader("Duration")
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { m in
                            durationChip(m, selected: !useCustom && selectedMinutes == m) {
                                useCustom = false
                                selectedMinutes = m
                            }
                        }
                        customChip
                    }
                    if useCustom {
                        Stepper(
                            value: $customMinutes,
                            in: 5...180,
                            step: 5
                        ) {
                            Text("\(customMinutes) min")
                                .font(.serif(18, weight: .regular))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.top, 2)
                    }

                    sectionHeader("Label (optional)")
                    TextField("Writing, reading, deep work…", text: $label)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.warmWheat)
                        )

                    sectionHeader("Silence apps")
                    silenceRow

                    if !store.tasks.isEmpty {
                        sectionHeader("Attach tasks (optional)")
                        Text("Check them off yourself during the session — they count toward your day.")
                            .font(.serifItalic(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        VStack(spacing: 6) {
                            ForEach(store.tasks) { task in
                                taskRow(task)
                            }
                        }
                    }

                    Button(action: start) {
                        Text("Start focus")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.warmWheat)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.textPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showBlockList) {
                FocusBlockListView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sans(10, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    @ViewBuilder
    private func durationChip(_ m: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text("\(m)m")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.textPrimary : Theme.warmWheat)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            useCustom = true
        } label: {
            Text("Custom")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(useCustom ? Theme.warmWheat : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(useCustom ? Theme.textPrimary : Theme.warmWheat)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskRow(_ task: FFTask) -> some View {
        let isSelected = selectedTaskIds.contains(task.id)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                selectedTaskIds.removeAll { $0 == task.id }
            } else {
                selectedTaskIds.append(task.id)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: task.category.hexColor) ?? Theme.textPrimary)
                    .frame(width: 7, height: 7)
                Text(task.title)
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.alertGreen.opacity(0.10) : Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var silenceRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBlockList = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: blocking.isEnabled && blocking.hasSelection ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(blocking.isEnabled && blocking.hasSelection ? Theme.alertGreen : Theme.textPrimary.opacity(0.45))
                Text(blocking.isEnabled ? blocking.summaryLine : "Off")
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.warmWheat)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action

    private func start() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let minutes = useCustom ? customMinutes : selectedMinutes
        let duration = TimeInterval(max(1, minutes) * 60)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        // Solo sessions have no audience, so every attachment is private.
        let attachments = selectedTaskIds.map { FocusTaskAttachment(taskId: $0, shared: false) }
        Task {
            await blocking.ensureAuthorizedForSessionStart()
            onStart(duration, trimmed.isEmpty ? nil : trimmed, attachments)
            dismiss()
        }
    }
}
