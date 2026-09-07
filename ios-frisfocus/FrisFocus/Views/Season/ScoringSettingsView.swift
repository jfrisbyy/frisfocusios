//
//  ScoringSettingsView.swift
//  FrisFocus
//
//  The season's scoring controls: the single value-based reminder
//  threshold (replacing per-task reminder toggles and the retired
//  priority tiers), the per-season categories editor (rename + recolor),
//  and the start-from-last-season copy-forward.
//

import SwiftUI
import UIKit

struct ScoringSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showImportPicker: Bool = false
    @State private var showSeasonSetup: Bool = false
    @State private var resumeSetup: Bool = false
    @State private var savedSetup: SetupConversationSnapshot? = SeasonSetupResumeStore.load()

    private var thresholdBinding: Binding<Int> {
        Binding(
            get: { store.reminderValueThreshold },
            set: { store.reminderValueThreshold = $0; store.persistAll() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showSeasonSetup = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.horizon.fill")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Theme.sunShadow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set your next season")
                                    .font(.sans(15, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Talk it through — the board builds itself")
                                    .font(.sans(12, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)

                    if let savedSetup {
                        Button {
                            resumeSetup = true
                            showSeasonSetup = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.uturn.forward")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Theme.sunShadow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(savedSetup.pausedLabel.map { "Continue where you left off · \($0)" }
                                        ?? "Continue where you left off")
                                        .font(.sans(15, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(savedSetup.hint)
                                        .font(.sans(12, weight: .regular))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Season setup")
                } footer: {
                    Text("A 10–15 minute conversation that builds your whole rubric — targets, tasks, negatives, boosters, and milestones. You review and edit everything before it starts.")
                }

                Section {
                    Stepper(value: thresholdBinding, in: 1...50) {
                        HStack {
                            Text("Remind me about items worth")
                            Spacer()
                            Text("\(store.reminderValueThreshold)+")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders surface only your higher-value unfinished tasks — never low-value habits. Gentle by design, with quiet hours respected. There are no per-task reminder toggles.")
                }

                Section {
                    NavigationLink {
                        CategoriesEditorView()
                    } label: {
                        Label("Edit categories", systemImage: "paintpalette")
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Rename and recolor this season's categories. Your changes apply everywhere they appear.")
                }

                Section {
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Start a new season", systemImage: "arrow.uturn.forward")
                            .foregroundStyle(Theme.alertGreen)
                    }
                    Button {
                        showSeasonSetup = true
                    } label: {
                        Label("Build one in conversation", systemImage: "bubble.left.and.text.bubble.right")
                            .foregroundStyle(Theme.textPrimary)
                    }
                } header: {
                    Text("New season")
                } footer: {
                    Text("Choose exactly what carries forward — tasks, boosters, negatives, routines, unfinished milestones, your categories, targets and schedule. Anything you leave behind stays with the season that finished.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Scoring & reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .fullScreenCover(isPresented: $showSeasonSetup, onDismiss: {
                resumeSetup = false
                savedSetup = SeasonSetupResumeStore.load()
            }) {
                SeasonSetupFlowView(startInResume: resumeSetup)
            }
            .sheet(isPresented: $showImportPicker) {
                SeasonImportPickerView { plan, name in
                    store.startNewSeason(importing: plan, name: name)
                    dismiss()
                }
                .environment(store)
            }
        }
    }
}

// MARK: - Categories editor

private struct CategoriesEditorView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.currentSeason.categories) { sc in
                    NavigationLink {
                        CategoryEditView(category: sc.category)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: store.categoryColorHex(sc.category)))
                                .frame(width: 14, height: 14)
                            Text(store.categoryDisplayName(sc.category))
                                .font(.sans(15, weight: .regular))
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.white)
                }
            } footer: {
                Text("Tap a category to rename or recolor it for this season.")
            }

            // A season could hold eight areas and there was no way to
            // reach the unused ones. The setup conversation decided the
            // whole set once, and if a part of life started mattering in
            // week three there was nowhere to put it — the only route to
            // an eighth area was starting a whole new season.
            if !unusedCategories.isEmpty {
                Section {
                    ForEach(unusedCategories, id: \.self) { category in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.addSeasonCategory(category)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(Color(hex: category.hexColor))
                                Text(category.displayName)
                                    .font(.sans(15, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.white)
                    }
                } header: {
                    Text("Add an area")
                } footer: {
                    Text("Areas you're not using this season. Adding one lets you file tasks under it — you can rename it to anything.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.warmWheat)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension CategoriesEditorView {
    /// The slots this season isn't using yet, in their natural order.
    var unusedCategories: [Category] {
        let inUse = Set(store.currentSeason.categories.map(\.category))
        return Category.allCases.filter { !inUse.contains($0) }
    }
}

private struct CategoryEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: Category

    @State private var name: String = ""

    /// A calm palette to recolor a category from.
    private let swatches: [String] = [
        "#7F77DD", "#D85A30", "#639922", "#185FA5", "#993556",
        "#BA7517", "#3F8E8E", "#854F0B", "#5F5E5A", "#B89A75"
    ]

    private var currentHex: String { store.categoryColorHex(category) }

    var body: some View {
        Form {
            Section {
                TextField(category.displayName, text: $name)
                    .font(.sans(16, weight: .regular))
            } header: {
                Text("Name")
            } footer: {
                Text("Leave blank to use the built-in name (\(category.displayName)).")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                    ForEach(swatches, id: \.self) { hex in
                        Button {
                            store.recolorSeasonCategory(category, hex: hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.textPrimary.opacity(currentHex.caseInsensitiveCompare(hex) == .orderedSame ? 0.9 : 0.0), lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)

                Button("Reset color") {
                    store.recolorSeasonCategory(category, hex: nil)
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
            } header: {
                Text("Color")
            }

            Section {
                let usage = store.seasonCategoryUsage(category)
                if usage == 0 {
                    Button(role: .destructive) {
                        if store.removeSeasonCategory(category) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    } label: {
                        Label("Remove from this season", systemImage: "minus.circle")
                    }
                } else {
                    // Refused rather than hidden: "why can't I remove
                    // this" is a better question to answer than to leave
                    // someone hunting for a control that isn't there.
                    Text("\(usage) thing\(usage == 1 ? "" : "s") still live here. Move or delete them first.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.warmWheat)
        .navigationTitle(store.categoryDisplayName(category))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = store.seasonCategoryRecord(category)?.customName ?? ""
        }
        .onDisappear {
            store.renameSeasonCategory(category, to: name.isEmpty ? nil : name)
        }
    }
}

#Preview {
    ScoringSettingsView()
        .environment(Store())
}
