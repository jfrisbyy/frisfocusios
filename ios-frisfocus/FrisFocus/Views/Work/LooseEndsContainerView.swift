//
//  LooseEndsContainerView.swift
//  FrisFocus
//
//  ONE shared white container holding all Loose End rows with hairline
//  dividers between them — NOT separate cards. Each row toggles its
//  To-do through the Store; pointed completions ripple to the day's
//  score immediately.
//

import SwiftUI
import UIKit

struct LooseEndsContainerView: View {
    let items: [Todo]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                LooseEndRow(todo: item)

                if index < items.count - 1 {
                    Divider()
                        .background(Theme.textPrimary.opacity(0.08))
                        .padding(.leading, 50)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Row

private struct LooseEndRow: View {
    @Environment(Store.self) private var store
    let todo: Todo

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                checkbox
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Mark \(todo.title) incomplete" : "Complete \(todo.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(todo.isCompleted ? 0.5 : 1.0))
                    .strikethrough(todo.isCompleted, color: Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                Text(todo.dueText)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 8)

            if let points = todo.pointValue {
                Text("+\(points)")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(todo.isCompleted ? 0.4 : 1.0))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.25), value: todo.isCompleted)
    }

    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            if todo.isCompleted {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.alertGreen)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.warmWheat)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
        .contentShape(Rectangle())
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.toggleTodo(todo)
    }
}

#Preview {
    let store = Store()
    LooseEndsContainerView(items: store.looseEnds)
        .padding()
        .background(Theme.warmWheat)
        .environment(store)
}
