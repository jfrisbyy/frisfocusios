//
//  AddPromptView.swift
//  FrisFocus
//
//  Dashed-border row inviting the user to add a thought. Real button —
//  tapping it opens the New Note form via the supplied `action`. Light
//  press scale-down keeps the editorial feel without looking loud.
//

import SwiftUI
import UIKit

struct AddPromptView: View {
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))

                Text("Add a thought, a verse, an evening reflection")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Add a new note")
    }

    private func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }
}

#Preview {
    AddPromptView(action: {})
        .padding()
        .background(Theme.paperCream)
}
