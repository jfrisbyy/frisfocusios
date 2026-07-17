//
//  QuickNoteComposerView.swift
//  FrisFocus
//
//  Lightweight inline writing surface for the homepage note zone.
//  Meaningful text creates a note once; every later edit persists immediately.
//

import SwiftUI
import UIKit

struct QuickNoteComposerView: View {
    @Environment(Store.self) private var store

    @Binding var isPresented: Bool
    @Binding var draftNoteID: UUID?
    let onExpand: (Note) -> Void

    @State private var noteText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("What wants to be remembered?")
                        .font(.serifItalic(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.38))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $noteText)
                    .focused($isFocused)
                    .font(.serif(17, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 118)
                    .padding(.horizontal, -1)
                    .accessibilityLabel("Quick note")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.38))
        .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.48), lineWidth: 1)
        }
        .shadow(color: Theme.sunWarm.opacity(0.12), radius: 12, y: 4)
        .onChange(of: noteText) { _, _ in
            persistDraft()
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard isPresented else { return }
                isFocused = true
            }
        }
        .onDisappear {
            persistDraft()
            draftNoteID = nil
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(draftNoteID == nil ? Theme.textPrimary.opacity(0.18) : Theme.alertGreen)
                    .frame(width: 5, height: 5)
                Text(draftNoteID == nil ? "Autosaves as you write" : "Saved")
                    .font(.sans(10, weight: .medium))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary.opacity(0.48))
            }

            Spacer(minLength: 0)

            Button(action: expand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        draftNoteID == nil
                            ? Theme.textPrimary.opacity(0.24)
                            : Theme.textPrimary.opacity(0.68)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draftNoteID == nil)
            .accessibilityLabel("Expand into full note")
            .accessibilityHint("Opens this note with photos, voice memos, folders, tags, and pinning")

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.58))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close quick note")
        }
        .frame(height: 32)
    }

    private func persistDraft() {
        let meaningfulText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !meaningfulText.isEmpty else {
            if let id = draftNoteID,
               let existing = store.notes.first(where: { $0.id == id }) {
                store.deleteNote(existing)
            }
            draftNoteID = nil
            return
        }

        if let id = draftNoteID,
           var existing = store.notes.first(where: { $0.id == id }) {
            guard existing.body != noteText else { return }
            existing.body = noteText
            store.updateNote(existing)
        } else {
            let note = Note(createdAt: Date(), body: noteText)
            store.addNote(note)
            draftNoteID = note.id
        }
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persistDraft()
        isFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }

    private func expand() {
        persistDraft()
        guard let id = draftNoteID,
              let note = store.notes.first(where: { $0.id == id }) else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isFocused = false
        isPresented = false
        onExpand(note)
    }
}
