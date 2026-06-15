//
//  TypewriterText.swift
//  FrisFocus
//
//  Reveals an assistant reply progressively — text appears in small
//  batches for a brisk, natural cadence, with a faint blinking cursor at
//  the tail while it types. Used by the season-setup conversation for both
//  the large single-question layout and the longer scrollable replies.
//
//  Reveal restarts whenever `revealID` changes (a freshly received reply).
//  A `revealID` of 0 — or Reduce Motion being on — shows the full text
//  immediately with no typing, so resumed conversations never re-type old
//  content. The complete text is always exposed to VoiceOver.
//

import SwiftUI

struct TypewriterText: View {
    let fullText: String
    /// Bumped by the view model for each freshly received reply. 0 means
    /// "show in full immediately" (e.g. a resumed conversation).
    let revealID: Int
    var font: Font
    var color: Color
    var alignment: TextAlignment = .center
    var lineSpacing: CGFloat = 0
    let reduceMotion: Bool

    @State private var visibleCount: Int = 0
    @State private var isTyping: Bool = false
    @State private var cursorOn: Bool = true

    private var shown: String {
        guard visibleCount < fullText.count else { return fullText }
        let end = fullText.index(fullText.startIndex, offsetBy: max(0, visibleCount))
        return String(fullText[..<end])
    }

    private var content: AttributedString {
        var string = AttributedString(shown)
        if isTyping {
            var cursor = AttributedString("▌")
            cursor.foregroundColor = color.opacity(cursorOn ? 0.4 : 0.08)
            string.append(cursor)
        }
        return string
    }

    var body: some View {
        Text(content)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .lineSpacing(lineSpacing)
            .accessibilityLabel(fullText)
            .task(id: revealID) { await run() }
    }

    private func run() async {
        // Resume (revealID 0) or Reduce Motion → full text, no typing.
        if revealID == 0 || reduceMotion {
            isTyping = false
            cursorOn = false
            visibleCount = fullText.count
            return
        }

        let total = fullText.count
        guard total > 0 else {
            isTyping = false
            visibleCount = 0
            return
        }

        visibleCount = 0
        cursorOn = true
        isTyping = true

        // Batch size scales with length so any reply finishes in ~2s.
        let step = max(1, Int((Double(total) / 110.0).rounded(.up)))
        var iteration = 0

        while visibleCount < total {
            if Task.isCancelled {
                visibleCount = total
                break
            }
            visibleCount = min(total, visibleCount + step)
            iteration += 1
            if iteration % 10 == 0 { cursorOn.toggle() }
            // A subtle ease as the line completes.
            let nearEnd = visibleCount > total - step * 4
            try? await Task.sleep(for: .milliseconds(nearEnd ? 34 : 18))
        }

        isTyping = false
    }
}
