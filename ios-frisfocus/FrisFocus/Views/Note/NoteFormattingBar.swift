//
//  NoteFormattingBar.swift
//  FrisFocus
//
//  The discreet formatting controls for the note editor: a single
//  toggle icon that lives in the tool strip, plus a compact row of
//  options (bullet, dash, numbered, checkbox, heading, bold) that
//  springs open above the strip when tapped.
//

import SwiftUI
import UIKit

/// The toggle icon placed inline with the other note tools. Flips the
/// shared `expanded` state with a soft spring + haptic.
struct NoteFormatToggle: View {
    @Binding var expanded: Bool

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(expanded ? Theme.sunShadow : Theme.textPrimary.opacity(0.55))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Formatting")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            expanded.toggle()
        }
    }
}

/// The expandable row of formatting options. Render it above the tool
/// strip; it only shows when `expanded` is true.
struct NoteFormatOptionsRow: View {
    let controller: SmartNoteEditorController

    var body: some View {
        HStack(spacing: 2) {
            option("list.bullet", label: "Bullet list", action: .bullet)
            option("minus", label: "Dash list", action: .dash)
            option("list.number", label: "Numbered list", action: .numbered)
            option("checklist", label: "Checklist", action: .checkbox)
            option("textformat.size.larger", label: "Heading", action: .heading)
            option("bold", label: "Bold", action: .bold)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.sunWarm.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func option(_ icon: String, label: String, action: NoteFormatAction) -> some View {
        Button {
            controller.apply(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .frame(width: 46, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
