//
//  NoteFormatting.swift
//  FrisFocus
//
//  Shared list/heading/bold formatting for note bodies. The note body
//  is stored as plain text with literal markers so it stays a simple
//  String everywhere (model, autosave, search) and renders identically
//  in the editor and in every read-only preview.
//
//  Markers (all literal characters, 1:1 with the displayed text so the
//  editor can restyle in place without ever shifting the caret):
//    • leading tabs ("\t")  → nesting level
//    • "• "                 → bullet
//    • "- "                 → dash
//    • "N. " / "N) "        → numbered
//    • "☐ " / "☑ "          → checkbox (unchecked / checked)
//    • "# "                 → heading
//    • **bold**             → inline bold
//

import SwiftUI
import UIKit

/// The semantic marker a single line carries.
enum NoteMarker: Equatable {
    case none
    case bullet
    case dash
    case numbered(Int, closeParen: Bool)
    case checkbox(Bool)
    case heading
}

/// One parsed line: its nesting level, marker, the literal marker prefix
/// (after the indentation tabs), and the content that follows it.
struct NoteLineParse {
    let indent: Int
    let marker: NoteMarker
    let markerString: String
    let content: Substring
}

enum NoteFormatting {

    // MARK: - Styling config

    /// Fonts and colors used to render a styled body. Built once per
    /// surface (editor / preview) from the app theme.
    struct Config {
        let bodyFont: UIFont
        let headingFont: UIFont
        let textColor: UIColor
        let accentColor: UIColor
        let checkedColor: UIColor
        let dimColor: UIColor
        let lineSpacing: CGFloat
        let tabWidth: CGFloat
        let markerIndent: CGFloat

        var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: bodyFont, .foregroundColor: textColor]
        }

        func bolded(_ font: UIFont) -> UIFont {
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(.traitBold)
            if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: desc, size: font.pointSize)
            }
            return font
        }

        /// The journal look used across the note surfaces.
        static func journal(
            bodySize: CGFloat,
            lineSpacing: CGFloat,
            italic: Bool
        ) -> Config {
            Config(
                bodyFont: NoteFormatting.uiFont(size: bodySize, weight: .regular, italic: italic, serif: true),
                headingFont: NoteFormatting.uiFont(size: bodySize + 5, weight: .semibold, italic: false, serif: true),
                textColor: UIColor(Theme.textPrimary),
                accentColor: UIColor(Theme.sunShadow),
                checkedColor: UIColor(Theme.alertGreen),
                dimColor: UIColor(Theme.textPrimary.opacity(0.3)),
                lineSpacing: lineSpacing,
                tabWidth: 22,
                markerIndent: 16
            )
        }
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight, italic: Bool, serif: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        var desc = base.fontDescriptor
        if serif, let d = desc.withDesign(.serif) { desc = d }
        var traits = desc.symbolicTraits
        if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        if let d = desc.withSymbolicTraits(traits) { desc = d }
        return UIFont(descriptor: desc, size: size)
    }

    // MARK: - Parsing

    /// Split a line into its leading tab indentation and the remainder.
    static func indentLevel(of line: Substring) -> (level: Int, rest: Substring) {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "\t" {
            level += 1
            idx = line.index(after: idx)
        }
        return (level, line[idx...])
    }

    static func parse(_ line: Substring) -> NoteLineParse {
        let (level, rest) = indentLevel(of: line)

        if rest.hasPrefix("# ") {
            return NoteLineParse(indent: level, marker: .heading, markerString: "# ", content: rest.dropFirst(2))
        }
        if rest.hasPrefix("☐ ") {
            return NoteLineParse(indent: level, marker: .checkbox(false), markerString: "☐ ", content: rest.dropFirst(2))
        }
        if rest.hasPrefix("☑ ") {
            return NoteLineParse(indent: level, marker: .checkbox(true), markerString: "☑ ", content: rest.dropFirst(2))
        }
        if rest.hasPrefix("• ") {
            return NoteLineParse(indent: level, marker: .bullet, markerString: "• ", content: rest.dropFirst(2))
        }
        if rest.hasPrefix("- ") {
            return NoteLineParse(indent: level, marker: .dash, markerString: "- ", content: rest.dropFirst(2))
        }
        if let numbered = parseNumbered(rest) {
            return NoteLineParse(
                indent: level,
                marker: .numbered(numbered.value, closeParen: numbered.closeParen),
                markerString: numbered.markerString,
                content: rest[numbered.contentStart...]
            )
        }
        return NoteLineParse(indent: level, marker: .none, markerString: "", content: rest)
    }

    private static func parseNumbered(
        _ rest: Substring
    ) -> (value: Int, closeParen: Bool, markerString: String, contentStart: Substring.Index)? {
        var idx = rest.startIndex
        var digits = ""
        while idx < rest.endIndex, rest[idx].isNumber {
            digits.append(rest[idx])
            idx = rest.index(after: idx)
        }
        guard !digits.isEmpty, let value = Int(digits), idx < rest.endIndex else { return nil }
        let delimiter = rest[idx]
        guard delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = rest.index(after: idx)
        guard afterDelimiter < rest.endIndex, rest[afterDelimiter] == " " else { return nil }
        let contentStart = rest.index(after: afterDelimiter)
        let markerString = "\(digits)\(delimiter) "
        return (value, delimiter == ")", markerString, contentStart)
    }

    // MARK: - Styled rendering

    /// Build a styled attributed string the same length as `text` (no
    /// character is added or removed), so the editor can apply it onto
    /// existing storage without moving the caret.
    static func attributed(_ text: String, cfg: Config) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            result.append(attributedLine(Substring(line), cfg: cfg))
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: cfg.baseAttributes))
            }
        }
        return result
    }

    private static func attributedLine(_ line: Substring, cfg: Config) -> NSAttributedString {
        let parsed = parse(line)
        let isHeading = parsed.marker == .heading
        let contentFont = isHeading ? cfg.headingFont : cfg.bodyFont

        let result = NSMutableAttributedString()

        if parsed.indent > 0 {
            result.append(NSAttributedString(
                string: String(repeating: "\t", count: parsed.indent),
                attributes: cfg.baseAttributes
            ))
        }

        var checked = false
        switch parsed.marker {
        case .none:
            break
        case .heading:
            result.append(NSAttributedString(
                string: parsed.markerString,
                attributes: [.font: cfg.headingFont, .foregroundColor: cfg.dimColor]
            ))
        case .checkbox(let on):
            checked = on
            result.append(NSAttributedString(
                string: parsed.markerString,
                attributes: [.font: cfg.bodyFont, .foregroundColor: on ? cfg.checkedColor : cfg.accentColor]
            ))
        case .bullet, .dash, .numbered:
            result.append(NSAttributedString(
                string: parsed.markerString,
                attributes: [.font: cfg.bodyFont, .foregroundColor: cfg.accentColor]
            ))
        }

        let contentColor = checked ? cfg.textColor.withAlphaComponent(0.5) : cfg.textColor
        result.append(inlineStyled(
            String(parsed.content),
            font: contentFont,
            color: contentColor,
            strike: checked,
            cfg: cfg
        ))

        let para = NSMutableParagraphStyle()
        para.lineSpacing = cfg.lineSpacing
        let indentPts = CGFloat(parsed.indent) * cfg.tabWidth
        para.headIndent = indentPts + (parsed.marker == .none ? 0 : cfg.markerIndent)
        para.firstLineHeadIndent = indentPts
        result.addAttribute(
            .paragraphStyle,
            value: para,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    /// Apply inline **bold** styling. The `**` delimiters stay visible but
    /// dimmed; the text between a pair is bold.
    private static func inlineStyled(
        _ content: String,
        font: UIFont,
        color: UIColor,
        strike: Bool,
        cfg: Config
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let parts = content.components(separatedBy: "**")
        let boldFont = cfg.bolded(font)

        for (i, part) in parts.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(
                    string: "**",
                    attributes: [.font: font, .foregroundColor: cfg.dimColor]
                ))
            }
            // Odd-indexed segments sit between a balanced pair of `**`.
            let isBold = i % 2 == 1
            var attrs: [NSAttributedString.Key: Any] = [
                .font: isBold ? boldFont : font,
                .foregroundColor: color,
            ]
            if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: part, attributes: attrs))
        }
        return result
    }
}

/// Read-only rendering of a note body for previews (library, home feed,
/// linked-note sheets). Mirrors the editor styling exactly.
struct NoteBodyText: View {
    let text: String
    var size: CGFloat = 16
    var lineSpacing: CGFloat = 6
    var italic: Bool = true
    var lineLimit: Int? = nil

    var body: some View {
        let cfg = NoteFormatting.Config.journal(
            bodySize: size,
            lineSpacing: lineSpacing,
            italic: italic
        )
        Text(AttributedString(NoteFormatting.attributed(text, cfg: cfg)))
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}
