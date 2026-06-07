//
//  FolderPickerSheetView.swift
//  FrisFocus
//
//  Sheet that lets a form pick one of the user's folders (or "no
//  folder" for unfiled notes). The sheet itself doubles as the
//  "create folder" entry point — tapping the row at the bottom opens
//  an inline name + color-swatch drawer that adds a new folder to
//  the Store and selects it.
//
//  Used by every form that needs a folder field (NewNoteFormView,
//  NewVoiceMemoFormView, NoteDetailEditView).
//

import SwiftUI
import UIKit

struct FolderPickerSheetView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The folder id the parent form should end up with. Nil = unfiled.
    @Binding var selectedFolderId: UUID?

    @State private var isCreating: Bool = false
    @State private var newName: String = ""
    @State private var newColor: FolderColor = .purple

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paperCream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        FolderPickerRow(
                            name: "No folder",
                            color: nil,
                            isSelected: selectedFolderId == nil,
                            action: { pick(nil) }
                        )

                        ForEach(store.sortedFolders) { folder in
                            Divider().background(Theme.textPrimary.opacity(0.08))
                            FolderPickerRow(
                                name: folder.name,
                                color: folder.colorKey,
                                isSelected: selectedFolderId == folder.id,
                                action: { pick(folder.id) }
                            )
                        }

                        Divider().background(Theme.textPrimary.opacity(0.08))

                        if isCreating {
                            createDrawer
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            Button(action: { withAnimation { isCreating = true } }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("New folder")
                                        .font(.sans(15, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Inline create

    @ViewBuilder
    private var createDrawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            EyebrowText(text: "New folder", opacity: 0.55)

            TextField("Folder name", text: $newName)
                .font(.sans(16))
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.12))
                        .frame(height: 0.5)
                }

            ColorSwatchRow(selected: $newColor)

            HStack {
                Button(action: cancelCreate) {
                    Text("Cancel")
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: createFolder) {
                    Text("Create")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(canCreate ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Theme.warmWheat.opacity(0.7))
    }

    private var canCreate: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func cancelCreate() {
        withAnimation {
            isCreating = false
            newName = ""
            newColor = .purple
        }
    }

    private func createFolder() {
        guard canCreate else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let folder = store.addFolder(name: newName, colorKey: newColor)
        selectedFolderId = folder.id
        dismiss()
    }

    // MARK: - Picker action

    private func pick(_ id: UUID?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedFolderId = id
        dismiss()
    }
}

// MARK: - Single row

private struct FolderPickerRow: View {
    let name: String
    let color: FolderColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.5)
                        .frame(width: 14, height: 14)
                    if let color {
                        Circle()
                            .fill(color.dotColor)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(name)
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color swatch row

/// Single row of the eight palette options. Tapping a swatch updates
/// the binding immediately. Used by both folder pickers and the
/// manage-folders edit drawer.
struct ColorSwatchRow: View {
    @Binding var selected: FolderColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FolderColor.allCases) { color in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selected = color
                }) {
                    ZStack {
                        Circle()
                            .fill(color.dotColor)
                            .frame(width: 26, height: 26)
                        if selected == color {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2.2)
                                .frame(width: 22, height: 22)
                            Circle()
                                .strokeBorder(color.dotColor.opacity(0.55), lineWidth: 1)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(color.displayName)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedId: UUID? = nil
    return Color.black.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            FolderPickerSheetView(selectedFolderId: $selectedId)
                .environment(Store())
        }
}
