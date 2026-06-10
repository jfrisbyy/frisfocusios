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

    @State private var newSeasonName: String = ""
    @State private var confirmNewSeason: Bool = false

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
                    TextField("New season name", text: $newSeasonName)
                        .font(.sans(16, weight: .regular))
                    Button {
                        confirmNewSeason = true
                    } label: {
                        Label("Start from this season's setup", systemImage: "arrow.uturn.forward")
                            .foregroundStyle(Theme.alertGreen)
                    }
                } header: {
                    Text("New season")
                } footer: {
                    Text("Carries your categories and daily/weekly targets forward into a fresh season instead of rebuilding from scratch. Your task library stays. Milestones reset.")
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
            .confirmationDialog(
                "Start a new season from this one's setup?",
                isPresented: $confirmNewSeason,
                titleVisibility: .visible
            ) {
                Button("Start new season") {
                    store.startNewSeasonFromCurrent(
                        name: newSeasonName.isEmpty ? nil : newSeasonName
                    )
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your categories and targets carry forward. The day count restarts and milestones reset.")
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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.warmWheat)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
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
