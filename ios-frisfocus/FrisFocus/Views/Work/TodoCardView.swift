//
//  TodoCardView.swift
//  FrisFocus
//
//  The hero to-do card in Today's Plan (e.g. "Call grandma").
//  Visually identical to the Task card EXCEPT:
//    - SQUARE checkbox (not circle)
//    - Calendar icon + "To-do · {due}" in the metadata row
//    - Point value rendered with a `+` prefix when present
//    - No category dot, no category name, no tier pill
//
//  Overdue To-dos (dueDate < today, not completed) recolour the
//  metadata row and checkbox stroke in `Theme.alertRed` so they
//  read as the most urgent items in the plan.
//
//  Tapping the checkbox flips `todo.isCompleted` via the Store and
//  (if pointed) records a LogEntry. Haptic on every toggle.
//

import SwiftUI
import UIKit

struct TodoCardView: View {
    @Environment(Store.self) private var store
    let todo: Todo
    /// Glass-on-sky appearance for the season detail — mirrors
    /// `TaskCardView`'s `onSky` so the two card types always match.
    var onSky: Bool = false

    @State private var showShareCapture: Bool = false
    @State private var showEdit: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var isOverdue: Bool {
        guard !todo.isCompleted, let due = todo.dueDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: due) < cal.startOfDay(for: Date())
    }

    private var ink: Color { onSky ? Theme.textCream : Theme.textPrimary }

    /// Proofs pinned to this to-do for today — round mini previews under
    /// the title, matching the task card.
    private var todayProofPins: [ProofPin] {
        store.proofPins(forTodoId: todo.id, on: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            checkbox

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(ink.opacity(todo.isCompleted ? 0.5 : 1.0))
                    .strikethrough(todo.isCompleted, color: ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(metadataColor)

                    Text("To-do · \(todo.dueText)")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(metadataColor)
                }

                TaskProofPreviewRow(pins: todayProofPins, ink: ink)
            }

            Spacer(minLength: 8)

            if let points = todo.pointValue {
                Text("+\(points)")
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(ink.opacity(todo.isCompleted ? 0.4 : 1.0))
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(onSky ? Color.white.opacity(0.10) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    onSky ? Color.white.opacity(0.16) : Theme.textPrimary.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .animation(.easeInOut(duration: 0.25), value: todo.isCompleted)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(todo.isCompleted ? "Mark \(todo.title) incomplete" : "Complete \(todo.title)")
        .onTapGesture {
            toggle()
        }
        .contextMenu {
            Button {
                showShareCapture = true
            } label: {
                Label("Proof", systemImage: "camera")
            }

            Button {
                toggle()
            } label: {
                Label(
                    todo.isCompleted ? "Mark incomplete" : "Complete",
                    systemImage: todo.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }

            Divider()

            Button {
                showEdit = true
            } label: {
                Label("Edit to-do", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete to-do", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(todo.title)\u{201D}?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete to-do", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                store.deleteTodo(todo)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Any points it earned are removed too.")
        }
        .sheet(isPresented: $showEdit) {
            NewTodoFormView(editing: todo) { }
                .environment(store)
        }
        .fullScreenCover(isPresented: $showShareCapture) {
            CaptureView(
                mode: .generalPost,
                initialTaskSticker: TaskStickerBlock(todo: todo)
            )
            .environment(store)
        }
    }

    /// Calendar icon + date tint. Overdue items go full alert red;
    /// everything else uses the standard 60 % textPrimary.
    private var metadataColor: Color {
        if isOverdue { return onSky ? Color(hex: 0xFF9B8A) : Theme.alertRed }
        return ink.opacity(0.6)
    }

    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            if todo.isCompleted {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(onSky ? Color(hex: 0x9BC25B) : Theme.alertGreen)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(onSky ? Color(hex: 0x1E3007) : Theme.warmWheat)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(checkboxStroke, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
        .contentShape(Rectangle())
    }

    private var checkboxStroke: Color {
        if isOverdue { return (onSky ? Color(hex: 0xFF9B8A) : Theme.alertRed).opacity(0.45) }
        return ink.opacity(0.35)
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.toggleTodo(todo)
    }
}

#Preview {
    let store = Store()
    let sample = store.todos.first { ($0.dueDate ?? .distantFuture) < Date() } ?? store.todos[0]
    return TodoCardView(todo: sample)
        .padding()
        .background(Theme.warmWheat)
        .environment(store)
}
