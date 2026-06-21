//
//  SmartNoteEditor.swift
//  FrisFocus
//
//  A UITextView-backed note body editor with list smarts:
//   • return continues bullet / dash / numbered / checkbox lines
//   • return on an empty list line drops the marker (or outdents)
//   • tab nests, shift-tab outdents
//   • checkbox glyphs are tappable to tick / untick
//   • a controller exposes formatting commands for the toolbar
//
//  The body stays plain text with literal markers (see NoteFormatting),
//  so the binding, autosave, and previews are unchanged. Styling is
//  applied as attributes only — never inserting or removing characters —
//  so the caret never jumps while typing.
//

import SwiftUI
import UIKit

/// Formatting actions the toolbar can request the editor to perform.
enum NoteFormatAction {
    case bullet
    case dash
    case numbered
    case checkbox
    case heading
    case bold
}

/// Bridge between the SwiftUI toolbar and the live UITextView.
@MainActor
final class SmartNoteEditorController {
    weak var coordinator: SmartNoteEditor.Coordinator?

    func focus() { coordinator?.focus() }
    func apply(_ action: NoteFormatAction) { coordinator?.apply(action) }
}

struct SmartNoteEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var controller: SmartNoteEditorController
    var bodySize: CGFloat
    var lineSpacing: CGFloat
    var italic: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = SmartNoteTextView()
        textView.onOutdent = { [weak coordinator = context.coordinator] in
            coordinator?.outdentCurrentLine()
        }
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = UIColor(Theme.sunShadow)
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = UILabel()
        placeholderLabel.numberOfLines = 0
        placeholderLabel.text = placeholder
        placeholderLabel.font = context.coordinator.cfg.bodyFont
        placeholderLabel.textColor = UIColor(Theme.textPrimary.opacity(0.32))
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -8),
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        context.coordinator.textView = textView
        controller.coordinator = context.coordinator

        context.coordinator.commit(text, caret: nil, to: textView, syncBinding: false)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.coordinator = context.coordinator
        context.coordinator.placeholderLabel?.text = placeholder

        if uiView.text != text {
            let caret = (text as NSString).length
            context.coordinator.commit(text, caret: caret, to: uiView, syncBinding: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SmartNoteEditor
        weak var textView: UITextView?
        weak var placeholderLabel: UILabel?

        init(_ parent: SmartNoteEditor) {
            self.parent = parent
        }

        var cfg: NoteFormatting.Config {
            .journal(bodySize: parent.bodySize, lineSpacing: parent.lineSpacing, italic: parent.italic)
        }

        func focus() {
            textView?.becomeFirstResponder()
        }

        // MARK: Live styling (attributes only — caret-safe)

        func restyle(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let plain = textView.text ?? ""
            let styled = NoteFormatting.attributed(plain, cfg: cfg)
            let storage = textView.textStorage
            guard storage.length == styled.length else {
                let caret = textView.selectedRange
                textView.attributedText = styled
                textView.selectedRange = caret
                return
            }
            storage.beginEditing()
            styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, range, _ in
                storage.setAttributes(attrs, range: range)
            }
            storage.endEditing()
        }

        /// Replace the whole body, restyle, restore the caret, and (when a
        /// structural edit) push the new plain text to the binding.
        func commit(_ newText: String, caret: Int?, to textView: UITextView, syncBinding: Bool) {
            textView.attributedText = NoteFormatting.attributed(newText, cfg: cfg)
            textView.typingAttributes = cfg.baseAttributes
            if let caret {
                let clamped = max(0, min(caret, (newText as NSString).length))
                textView.selectedRange = NSRange(location: clamped, length: 0)
            }
            if syncBinding { parent.text = newText }
            updatePlaceholder(textView)
        }

        func updatePlaceholder(_ textView: UITextView) {
            placeholderLabel?.isHidden = !(textView.text ?? "").isEmpty
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            restyle(textView)
            parent.text = textView.text ?? ""
            updatePlaceholder(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard textView.markedTextRange == nil, range.length == 0 else { return true }
            if text == "\n" { return handleReturn(textView, at: range.location) }
            if text == "\t" { return handleIndent(textView, at: range, outdent: false) }
            return true
        }

        // MARK: Return / list continuation

        private func handleReturn(_ textView: UITextView, at caret: Int) -> Bool {
            let plain = textView.text ?? ""
            var lines = plain.components(separatedBy: "\n")
            let (lineIndex, _) = lineAndColumn(forOffset: caret, in: plain)
            guard lineIndex < lines.count else { return true }

            let parsed = NoteFormatting.parse(Substring(lines[lineIndex]))
            guard parsed.marker != .none, parsed.marker != .heading else {
                if parsed.marker == .heading { return true }
                return true
            }

            let contentEmpty = parsed.content.trimmingCharacters(in: .whitespaces).isEmpty

            if contentEmpty {
                // Empty list item + return: outdent one level, or drop the
                // marker entirely when already at the top level.
                if parsed.indent > 0 {
                    lines[lineIndex] = String(repeating: "\t", count: parsed.indent - 1) + parsed.markerString
                } else {
                    lines[lineIndex] = ""
                }
                let renumbered = renumber(lines)
                let newCaret = offset(forLine: lineIndex, column: (renumbered[lineIndex] as NSString).length, in: renumbered)
                commit(renumbered.joined(separator: "\n"), caret: newCaret, to: textView, syncBinding: true)
                return false
            }

            // Continue the list onto a fresh line.
            let indentTabs = String(repeating: "\t", count: parsed.indent)
            let nextMarker = continuationMarker(for: parsed.marker)
            let newPrefix = indentTabs + nextMarker

            let (_, column) = lineAndColumn(forOffset: caret, in: plain)
            let lineNS = lines[lineIndex] as NSString
            let head = lineNS.substring(to: min(column, lineNS.length))
            let tail = lineNS.substring(from: min(column, lineNS.length))

            lines[lineIndex] = head
            lines.insert(newPrefix + tail, at: lineIndex + 1)

            let renumbered = renumber(lines)
            let caretColumn = (renumbered[lineIndex + 1] as NSString).length - (tail as NSString).length
            let newCaret = offset(forLine: lineIndex + 1, column: caretColumn, in: renumbered)
            commit(renumbered.joined(separator: "\n"), caret: newCaret, to: textView, syncBinding: true)
            UISelectionFeedbackGenerator().selectionChanged()
            return false
        }

        private func continuationMarker(for marker: NoteMarker) -> String {
            switch marker {
            case .bullet: return "• "
            case .dash: return "- "
            case .checkbox: return "☐ "
            case .numbered(let value, let closeParen): return "\(value + 1)\(closeParen ? ")" : ".") "
            case .none, .heading: return ""
            }
        }

        // MARK: Indent / outdent

        private func handleIndent(_ textView: UITextView, at range: NSRange, outdent: Bool) -> Bool {
            let plain = textView.text ?? ""
            var lines = plain.components(separatedBy: "\n")
            let (startLine, startCol) = lineAndColumn(forOffset: range.location, in: plain)
            guard startLine < lines.count else { return true }

            let parsed = NoteFormatting.parse(Substring(lines[startLine]))
            // Tab only nests inside a list; elsewhere it's a normal tab.
            guard parsed.marker != .none, parsed.marker != .heading else { return true }

            if outdent {
                guard parsed.indent > 0 else { return false }
                lines[startLine] = String(lines[startLine].dropFirst())
            } else {
                lines[startLine] = "\t" + lines[startLine]
            }

            let renumbered = renumber(lines)
            let newCol = max(0, startCol + (outdent ? -1 : 1))
            let newCaret = offset(forLine: startLine, column: newCol, in: renumbered)
            commit(renumbered.joined(separator: "\n"), caret: newCaret, to: textView, syncBinding: true)
            UISelectionFeedbackGenerator().selectionChanged()
            return false
        }

        // MARK: Renumbering

        /// Recompute numbered-list values so they count up within each
        /// nesting level, resetting when a list block is broken.
        private func renumber(_ lines: [String]) -> [String] {
            var counters: [Int: Int] = [:]
            var result = lines
            for i in 0..<result.count {
                let parsed = NoteFormatting.parse(Substring(result[i]))
                switch parsed.marker {
                case .numbered(_, let closeParen):
                    let level = parsed.indent
                    counters[level, default: 0] += 1
                    for key in counters.keys where key > level { counters[key] = 0 }
                    let n = counters[level] ?? 1
                    let marker = "\(n)\(closeParen ? ")" : ".") "
                    result[i] = String(repeating: "\t", count: level) + marker + String(parsed.content)
                case .none:
                    counters.removeAll()
                case .bullet, .dash, .checkbox, .heading:
                    let level = parsed.indent
                    for key in counters.keys where key >= level { counters[key] = 0 }
                }
            }
            return result
        }

        // MARK: Formatting commands

        func apply(_ action: NoteFormatAction) {
            guard let textView else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switch action {
            case .bullet: toggleLineMarker(textView, to: "• ")
            case .dash: toggleLineMarker(textView, to: "- ")
            case .numbered: toggleLineMarker(textView, to: "1. ")
            case .checkbox: toggleLineMarker(textView, to: "☐ ")
            case .heading: toggleLineMarker(textView, to: "# ")
            case .bold: toggleBold(textView)
            }
        }

        private func toggleLineMarker(_ textView: UITextView, to marker: String) {
            let plain = textView.text ?? ""
            var lines = plain.components(separatedBy: "\n")
            let selection = textView.selectedRange
            let (startLine, _) = lineAndColumn(forOffset: selection.location, in: plain)
            let (endLine, _) = lineAndColumn(forOffset: selection.location + selection.length, in: plain)
            guard startLine < lines.count else { return }

            // If every line in range already carries this marker, strip it.
            let range = startLine...min(endLine, lines.count - 1)
            let allHaveMarker = range.allSatisfy { idx in
                let parsed = NoteFormatting.parse(Substring(lines[idx]))
                return matches(parsed.marker, marker: marker)
            }

            for idx in range {
                let parsed = NoteFormatting.parse(Substring(lines[idx]))
                let indent = String(repeating: "\t", count: parsed.indent)
                if allHaveMarker {
                    lines[idx] = indent + String(parsed.content)
                } else {
                    lines[idx] = indent + marker + String(parsed.content)
                }
            }

            let renumbered = renumber(lines)
            let newCaret = offset(forLine: endLine, column: (renumbered[min(endLine, renumbered.count - 1)] as NSString).length, in: renumbered)
            commit(renumbered.joined(separator: "\n"), caret: newCaret, to: textView, syncBinding: true)
        }

        private func matches(_ markerCase: NoteMarker, marker: String) -> Bool {
            switch (markerCase, marker) {
            case (.bullet, "• "): return true
            case (.dash, "- "): return true
            case (.checkbox, "☐ "): return true
            case (.heading, "# "): return true
            case (.numbered, let m) where m.hasPrefix("1"): return true
            default: return false
            }
        }

        private func toggleBold(_ textView: UITextView) {
            let plain = textView.text as NSString? ?? ""
            let selection = textView.selectedRange
            if selection.length == 0 {
                let insertion = "****"
                let newText = plain.replacingCharacters(in: selection, with: insertion)
                commit(newText, caret: selection.location + 2, to: textView, syncBinding: true)
            } else {
                let selected = plain.substring(with: selection)
                let wrapped = "**\(selected)**"
                let newText = plain.replacingCharacters(in: selection, with: wrapped)
                commit(newText, caret: selection.location + (wrapped as NSString).length, to: textView, syncBinding: true)
            }
        }

        // MARK: Checkbox taps

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let location = gesture.location(in: textView)
            let point = CGPoint(
                x: location.x - textView.textContainerInset.left,
                y: location.y - textView.textContainerInset.top
            )
            let layoutManager = textView.layoutManager
            guard textView.textStorage.length > 0 else { return }
            let charIndex = layoutManager.characterIndex(
                for: point,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let ns = textView.text as NSString
            guard charIndex < ns.length else { return }
            let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
            let line = ns.substring(with: lineRange)
            let parsed = NoteFormatting.parse(Substring(line))
            guard case .checkbox(let checked) = parsed.marker else { return }

            // Only toggle when the tap landed on the glyph itself.
            let glyphIndex = lineRange.location + parsed.indent
            if charIndex <= glyphIndex + 1 {
                let glyphRange = NSRange(location: glyphIndex, length: 1)
                let newGlyph = checked ? "☐" : "☑"
                let newText = ns.replacingCharacters(in: glyphRange, with: newGlyph)
                let caret = textView.selectedRange.location
                commit(newText, caret: caret, to: textView, syncBinding: true)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        /// Outdent the line the caret sits on (shift-tab on a hardware
        /// keyboard). No-op when the line isn't an indented list item.
        func outdentCurrentLine() {
            guard let textView else { return }
            _ = handleIndent(textView, at: textView.selectedRange, outdent: true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: Offset helpers (UTF-16, matching NSRange)

        private func lineAndColumn(forOffset offset: Int, in text: String) -> (line: Int, column: Int) {
            let lines = text.components(separatedBy: "\n")
            var remaining = offset
            for (i, line) in lines.enumerated() {
                let length = (line as NSString).length
                if remaining <= length { return (i, remaining) }
                remaining -= length + 1
            }
            let last = max(0, lines.count - 1)
            return (last, (lines[last] as NSString).length)
        }

        private func offset(forLine line: Int, column: Int, in lines: [String]) -> Int {
            var offset = 0
            for i in 0..<min(line, lines.count) {
                offset += (lines[i] as NSString).length + 1
            }
            return offset + column
        }
    }
}

/// UITextView subclass that adds a shift-tab key command for outdenting
/// when a hardware keyboard is attached.
final class SmartNoteTextView: UITextView {
    var onOutdent: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: "\t",
                modifierFlags: .shift,
                action: #selector(performOutdent)
            )
        ]
    }

    @objc private func performOutdent() {
        onOutdent?()
    }
}
