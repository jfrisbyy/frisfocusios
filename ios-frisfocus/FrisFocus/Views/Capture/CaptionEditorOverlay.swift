//
//  CaptionEditorOverlay.swift
//  FrisFocus
//
//  The shared caption-editing overlay used by the proof editor and the
//  overlay-post preview. One single styled text field — the user types
//  directly into the big preview, restyled live by the style and color
//  pickers below — instead of a separate preview + plain input box.
//

import SwiftUI
import UIKit

struct CaptionEditorOverlay: View {
    @Binding var text: String
    @Binding var style: CaptionStyle
    @Binding var color: Color?
    let onCancel: () -> Void
    let onDone: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDone() }

            VStack(spacing: 18) {
                Spacer()

                StyledCaptionField(text: $text, style: style, color: color, focused: $focused)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)

                Spacer()

                stylePicker
                    .padding(.bottom, 2)

                colorPickerRow
                    .padding(.bottom, 6)

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Color.white.opacity(0.75))
                    .font(.sans(14, weight: .medium))

                    Spacer()

                    Button("Done") {
                        onDone()
                    }
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.textPrimary))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .transition(.opacity)
        .onAppear {
            // Pop the keyboard after the overlay renders.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
        }
    }

    // MARK: - Style picker

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CaptionStyle.allCases) { option in
                    styleChip(option)
                }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 64)
    }

    private func styleChip(_ option: CaptionStyle) -> some View {
        let isSelected = option == style
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.14)) {
                style = option
            }
        } label: {
            VStack(spacing: 4) {
                CaptionBlockText(
                    block: CaptionBlock(text: option.glyphSample, style: option)
                )
                .scaleEffect(0.55)
                .frame(width: 50, height: 32)
                .clipped()

                Text(option.label)
                    .font(.sans(9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
            }
            .frame(width: 64)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.textCream : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label) style")
    }

    // MARK: - Color picker

    private var colorPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 11) {
                autoColorChip
                ForEach(Array(captionPalette.enumerated()), id: \.offset) { _, swatch in
                    colorSwatch(swatch)
                }
                spectrumChip
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 46)
    }

    private var autoColorChip: some View {
        let selected = (color == nil)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            color = nil
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 30, height: 30)
                Image(systemName: "a.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(4)
            .overlay(
                Circle().strokeBorder(selected ? Theme.textCream : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Automatic color")
    }

    private func colorSwatch(_ swatch: Color) -> some View {
        let selected = (color == swatch)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            color = swatch
        } label: {
            Circle()
                .fill(swatch)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6))
                .padding(4)
                .overlay(
                    Circle().strokeBorder(selected ? Theme.textCream : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caption color")
    }

    private var spectrumChip: some View {
        let custom = (color != nil) && !captionPalette.contains(where: { $0 == color })
        return ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 30, height: 30)
            ColorPicker(
                "",
                selection: Binding(
                    get: { color ?? .white },
                    set: { color = $0 }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .scaleEffect(0.82)
            .frame(width: 26, height: 26)
        }
        .padding(4)
        .overlay(
            Circle().strokeBorder(custom ? Theme.textCream : Color.clear, lineWidth: 2)
        )
        .accessibilityLabel("More colors")
    }
}

// MARK: - Styled field

/// A `TextField` dressed exactly like `CaptionBlockText` for the chosen
/// style — the single live preview the user types into. A clear
/// measuring `Text` drives the layout so filled backgrounds hug the
/// typed content; the field renders the glyphs and caret on top.
private struct StyledCaptionField: View {
    @Binding var text: String
    let style: CaptionStyle
    let color: Color?
    var focused: FocusState<Bool>.Binding

    private let placeholder = "type something"
    private let fontSize: CGFloat = 24

    var body: some View {
        switch style {
        case .classic:
            field(font: .serif(fontSize, weight: .medium), ink: plainInk(.white))
                .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

        case .bold:
            field(font: .sans(fontSize - 1, weight: .black), ink: plainInk(.white), uppercased: true)
                .shadow(color: Color.black.opacity(0.65), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

        case .subtitle:
            field(font: .sans(fontSize - 4, weight: .semibold), ink: onFill(.white))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(fill(Color.black.opacity(0.78)))

        case .highlight:
            field(font: .sans(fontSize - 2, weight: .heavy), ink: onFill(Theme.textPrimary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(fill(Theme.textCream))

        case .outline:
            field(font: .sans(fontSize, weight: .black), ink: plainInk(.white))
                .background {
                    ZStack {
                        ForEach(outlineOffsets, id: \.self) { offset in
                            Text(displayText)
                                .font(.sans(fontSize, weight: .black))
                                .foregroundStyle(Color.black)
                                .multilineTextAlignment(.center)
                                .offset(x: offset.x, y: offset.y)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

        case .typewriter:
            field(
                font: .system(size: fontSize - 4, weight: .medium, design: .monospaced),
                ink: onFill(Theme.textPrimary)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(fill(Theme.textCream.opacity(0.94)))

        case .neon:
            let neonText = color ?? Color(hex: 0xFFE7F2)
            let glow = color ?? Color(hex: 0xFF3D8B)
            let glowFar = color ?? Color(hex: 0x6E66FF)
            field(font: .sans(fontSize, weight: .bold), ink: neonText)
                .shadow(color: glow.opacity(0.95), radius: 6)
                .shadow(color: glow.opacity(0.85), radius: 14)
                .shadow(color: glowFar.opacity(0.55), radius: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

        case .tag:
            HStack(spacing: 4) {
                Text("#")
                    .font(.sans(fontSize - 6, weight: .heavy))
                    .foregroundStyle(onFill(Theme.alertGreen))
                field(font: .sans(fontSize - 4, weight: .semibold), ink: onFill(.white))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(fill(Color.black.opacity(0.55)))
            )
            .overlay(
                Capsule().strokeBorder((color ?? Theme.alertGreen).opacity(0.55), lineWidth: 0.8)
            )
        }
    }

    private var displayText: String {
        text.isEmpty ? placeholder : text
    }

    /// The measuring `Text` (clear ink) with the live `TextField`
    /// overlaid at the exact same size, font, and alignment.
    private func field(font: Font, ink: Color, uppercased: Bool = false) -> some View {
        let binding = uppercased
            ? Binding<String>(
                get: { text.uppercased() },
                set: { text = $0.uppercased() }
            )
            : $text
        let measured = uppercased ? displayText.uppercased() : displayText

        return Text(measured)
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(.clear)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                TextField(
                    "",
                    text: binding,
                    prompt: Text(uppercased ? placeholder.uppercased() : placeholder)
                        .foregroundStyle(ink.opacity(0.5)),
                    axis: .vertical
                )
                .font(font)
                .foregroundStyle(ink)
                .tint(ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(uppercased ? .characters : .sentences)
                .focused(focused)
            }
    }

    private var outlineOffsets: [CGPoint] {
        [
            CGPoint(x: -1.5, y: 0), CGPoint(x: 1.5, y: 0),
            CGPoint(x: 0, y: -1.5), CGPoint(x: 0, y: 1.5),
            CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
            CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)
        ]
    }

    /// Plain-style text fill: the chosen color, or `def` when Auto.
    private func plainInk(_ def: Color) -> Color {
        color ?? def
    }

    /// Filled-style background: the chosen color, or the style's
    /// natural `def` background when Auto.
    private func fill(_ def: Color) -> Color {
        color ?? def
    }

    /// Text drawn on top of a filled background — the style's natural
    /// `def` when Auto, otherwise an auto-contrasting black/white.
    private func onFill(_ def: Color) -> Color {
        color == nil ? def : contrastingInk(on: color!)
    }
}
