//
//  CarryForwardPromptView.swift
//  FrisFocus
//
//  The morning "bring yesterday's leftovers forward" sheet. Shows the
//  unfinished, pointed to-dos whose due day has passed and lets the user
//  pick which ones to re-date to today (dropping them into Today's Plan)
//  or dismiss them for the day.
//

import SwiftUI

struct CarryForwardPromptView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let candidates: [Todo]

    @State private var selected: Set<UUID> = []

    private var allSelected: Bool {
        !candidates.isEmpty && selected.count == candidates.count
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header
            list
            actions
        }
        .background(Theme.warmWheat)
        .onAppear {
            // Default to everything selected — the common case is "carry
            // it all forward," and unchecking a couple is quick.
            selected = Set(candidates.map(\.id))
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Theme.textMuted.opacity(0.5))
            .frame(width: 38, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 18)
    }

    private var header: some View {
        VStack(spacing: 8) {
            EyebrowText(text: "A new day")
            Text("Bring yesterday's to-dos forward?")
                .font(.serif(24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("These didn't get done. Pick the ones you still want, and they'll move into today's plan.")
                .font(.sans(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.bottom, 18)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(candidates) { todo in
                    row(for: todo)
                }
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(for todo: Todo) -> some View {
        let isOn = selected.contains(todo.id)
        return Button {
            toggle(todo.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? Theme.alertGreen : Theme.textMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(.serif(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(dueLabel(for: todo))
                        .font(.sans(12))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if let points = todo.pointValue {
                    Text("+\(points)")
                        .font(.serif(15, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.paperCream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(isOn ? Theme.alertGreen.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                store.carryTodosForward(selected)
                dismiss()
            } label: {
                Text(addLabel)
                    .font(.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(selected.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    )
            }
            .disabled(selected.isEmpty)

            Button {
                store.dismissCarryForwardPrompt()
                dismiss()
            } label: {
                Text("Not today")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var addLabel: String {
        let count = selected.count
        if count == 0 { return "Select to bring forward" }
        return "Add \(count) to today"
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func dueLabel(for todo: Todo) -> String {
        guard let due = todo.dueDate else { return "carried over" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: due), to: today).day ?? 0
        switch days {
        case ..<1: return "due today"
        case 1: return "due yesterday"
        default: return "\(days) days ago"
        }
    }
}
