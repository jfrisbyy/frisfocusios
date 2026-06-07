//
//  ManageFoldersSheetView.swift
//  FrisFocus
//
//  Full folder management sheet. Each row shows the folder's tint, its
//  name, and how many notes are currently filed in it. Tapping a row
//  expands an inline drawer where the user can rename, recolour, or
//  delete the folder. A "+ New folder" row at the bottom shares the
//  same create flow as FolderPickerSheetView.
//
//  Delete is two-step: tap the trash → confirmation dialog. When the
//  folder still has notes, the dialog offers both "move notes to no
//  folder" and "delete folder and notes" so destructive intent is
//  explicit.
//

import SwiftUI
import UIKit

struct ManageFoldersSheetView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingFolderId: UUID? = nil
    @State private var isCreating: Bool = false
    @State private var newName: String = ""
    @State private var newColor: FolderColor = .purple
    @State private var pendingDelete: NoteFolder? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paperCream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        if store.folders.isEmpty {
                            emptyHint
                        }

                        ForEach(store.sortedFolders) { folder in
                            folderRow(folder)
                            Divider().background(Theme.textPrimary.opacity(0.08))
                        }

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

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Manage folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
            .confirmationDialog(
                pendingDeleteTitle,
                isPresented: deleteDialogBinding,
                presenting: pendingDelete,
                actions: deleteActions,
                message: deleteMessage
            )
        }
    }

    // MARK: - Empty hint

    @ViewBuilder
    private var emptyHint: some View {
        VStack(spacing: 6) {
            EyebrowText(text: "No folders yet", opacity: 0.5)
            Text("Create one below to start grouping notes.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 32)
    }

    // MARK: - Folder row + drawer

    @ViewBuilder
    private func folderRow(_ folder: NoteFolder) -> some View {
        let isEditing = (editingFolderId == folder.id)
        VStack(spacing: 0) {
            Button(action: { toggleEditing(for: folder) }) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(folder.colorKey.dotColor)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        let count = store.notesCount(in: folder)
                        Text("\(count) note\(count == 1 ? "" : "s")")
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }

                    Spacer()

                    Image(systemName: isEditing ? "chevron.up" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                FolderEditDrawer(
                    folder: folder,
                    onDelete: { pendingDelete = folder }
                )
                .id(folder.id)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleEditing(for folder: NoteFolder) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            editingFolderId = (editingFolderId == folder.id) ? nil : folder.id
        }
    }

    // MARK: - Create drawer

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
        store.addFolder(name: newName, colorKey: newColor)
        withAnimation {
            isCreating = false
            newName = ""
            newColor = .purple
        }
    }

    // MARK: - Delete

    private var pendingDeleteTitle: String {
        guard let folder = pendingDelete else { return "" }
        return "Delete \(folder.name)?"
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    @ViewBuilder
    private func deleteActions(_ folder: NoteFolder) -> some View {
        let count = store.notesCount(in: folder)
        if count > 0 {
            Button("Move \(count) note\(count == 1 ? "" : "s") to no folder", role: .destructive) {
                store.deleteFolder(folder, deleteNotes: false)
                editingFolderId = nil
            }
            Button("Delete folder and \(count) note\(count == 1 ? "" : "s")", role: .destructive) {
                store.deleteFolder(folder, deleteNotes: true)
                editingFolderId = nil
            }
        } else {
            Button("Delete folder", role: .destructive) {
                store.deleteFolder(folder, deleteNotes: false)
                editingFolderId = nil
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private func deleteMessage(_ folder: NoteFolder) -> some View {
        let count = store.notesCount(in: folder)
        if count > 0 {
            Text("This folder has \(count) note\(count == 1 ? "" : "s").")
        } else {
            Text("This folder is empty.")
        }
    }
}

// MARK: - Edit drawer for a single folder

/// Local state lives in this child view so editing one folder's name
/// doesn't fight with another row's. The store is the source of truth;
/// changes are written on commit (Save) so the user can back out without
/// dirtying anything.
private struct FolderEditDrawer: View {
    @Environment(Store.self) private var store

    let folder: NoteFolder
    let onDelete: () -> Void

    @State private var workingName: String = ""
    @State private var workingColor: FolderColor = .purple
    @State private var initialized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EyebrowText(text: "Edit folder", opacity: 0.55)

            TextField("Folder name", text: $workingName)
                .font(.sans(16))
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.12))
                        .frame(height: 0.5)
                }

            ColorSwatchRow(selected: $workingColor)

            HStack {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Delete")
                            .font(.sans(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.alertRed)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: save) {
                    Text("Save")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Theme.warmWheat.opacity(0.7))
        .onAppear {
            if !initialized {
                workingName = folder.name
                workingColor = folder.colorKey
                initialized = true
            }
        }
    }

    private var canSave: Bool {
        !workingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if workingName != folder.name {
            store.renameFolder(folder, to: workingName)
        }
        if workingColor != folder.colorKey {
            store.recolorFolder(folder, to: workingColor)
        }
    }
}

#Preview {
    Color.black.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ManageFoldersSheetView()
                .environment(Store())
        }
}
