//
//  NewTodoFormView.swift
//  FrisFocus
//
//  Full-height form sheet for creating or editing a To-do — a one-time
//  item that may or may not be dated, may or may not carry a point
//  reward. Pointed To-dos due today (or past-due) land in Today's
//  Plan; everything else lives quietly in the To-do list (a future
//  screen). No category, no tier — To-dos are deliberately simpler
//  than Tasks. Pass `editing:` to update an existing To-do in place.
//

import SwiftUI

struct NewTodoFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: Todo?
    let onSave: () -> Void

    @State private var title: String
    @State private var hasDate: Bool
    @State private var dueDate: Date
    @State private var hasPoints: Bool
    @State private var pointValue: Int

    init(editing: Todo? = nil, onSave: @escaping () -> Void) {
        self.editing = editing
        self.onSave = onSave
        _title = State(initialValue: editing?.title ?? "")
        _hasDate = State(initialValue: editing.map { $0.dueDate != nil } ?? true)
        _dueDate = State(initialValue: editing?.dueDate ?? Date())
        _hasPoints = State(initialValue: editing?.pointValue != nil)
        _pointValue = State(initialValue: editing?.pointValue ?? 2)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Call grandma", text: $title, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Title")
                }

                Section {
                    Toggle("Has a date", isOn: $hasDate.animation(.easeInOut(duration: 0.2)))
                    if hasDate {
                        DatePicker(
                            "Due",
                            selection: $dueDate,
                            displayedComponents: [.date]
                        )
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text(hasDate
                         ? "Dated To-dos appear on Today's Plan when due."
                         : "Undated To-dos live in your To-do list until you're ready.")
                }

                Section {
                    Toggle("Worth points", isOn: $hasPoints.animation(.easeInOut(duration: 0.2)))
                    if hasPoints {
                        Stepper(value: $pointValue, in: 1...10) {
                            HStack {
                                Text("Bonus")
                                Spacer()
                                Text("+\(pointValue) pts")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                } header: {
                    Text("Reward")
                } footer: {
                    Text(hasPoints
                         ? "Optional bonus added to your day when completed."
                         : "Pointless To-dos are still list-tracked — just no reward.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "New to-do" : "Edit to-do")
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

    // MARK: - Derived

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing, let idx = store.todos.firstIndex(where: { $0.id == editing.id }) {
            store.todos[idx].title = trimmedTitle
            store.todos[idx].dueDate = hasDate ? dueDate : nil
            store.todos[idx].pointValue = hasPoints ? pointValue : nil
        } else {
            let todo = Todo(
                title: trimmedTitle,
                dueDate: hasDate ? dueDate : nil,
                pointValue: hasPoints ? pointValue : nil
            )
            store.todos.append(todo)
        }
        store.persistAll()

        dismiss()
        onSave()
    }
}

#Preview {
    NewTodoFormView { }
        .environment(Store())
}
