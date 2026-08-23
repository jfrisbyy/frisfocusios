//
//  CheerComposerView.swift
//  FrisFocus
//
//  The small bottom sheet that sends a cheer to a friend. Opened from
//  the friend detail's gesture bar `Cheer` capsule. A cheer is a gift,
//  not a thread: one short line + one tap. The sheet exposes a text
//  field, three suggested quick phrases, and a single send button.
//  The composer never sends an empty string — trimming happens in
//  `Store.sendCheer` so a stray Return key can't write a ghost row.
//

import SwiftUI
import UIKit

struct CheerComposerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let friend: Friend

    @State private var message: String = ""
    @FocusState private var fieldFocused: Bool

    /// Quick phrases the user can tap to either fill the field
    /// directly or send-and-dismiss. Tapping a chip fills the field
    /// so the user can still tweak before sending; the dedicated
    /// send button is the only thing that writes the cheer.
    private let chips: [String] = [
        "keep going",
        "proud of you",
        "go get it"
    ]

    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters still available under the cheer cap.
    private var remaining: Int {
        Cheer.maxMessageLength - message.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            field

            chipsRow

            Spacer(minLength: 0)

            sendButton
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEND A CHEER")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Text("A word for \(friend.displayName)\u{2019}s day")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Lands on their home today, then fades. No reply, no thread \u{2014} just a gift.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 5) {
            TextField(
                "Send \(friend.displayName) a word\u{2026}",
                text: $message,
                axis: .vertical
            )
            .font(.serifItalic(16, weight: .regular))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.textPrimary)
            .focused($fieldFocused)
            .lineLimit(3, reservesSpace: true)
            .submitLabel(.send)
            .onSubmit { send() }
            .onChange(of: message) { _, newValue in
                // Hard cap — a cheer is a quick word, not a letter.
                if newValue.count > Cheer.maxMessageLength {
                    message = String(newValue.prefix(Cheer.maxMessageLength))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        remaining <= 0
                            ? Theme.alertRed.opacity(0.45)
                            : Theme.textPrimary.opacity(0.12),
                        lineWidth: 0.5
                    )
            )

            Text("\(message.count)/\(Cheer.maxMessageLength)")
                .font(.sans(10, weight: .medium))
                .foregroundStyle(
                    remaining <= 10
                        ? Theme.alertRed.opacity(0.8)
                        : Theme.textPrimary.opacity(0.4)
                )
                .monospacedDigit()
                .opacity(message.isEmpty ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: message.isEmpty)
                .accessibilityLabel("\(remaining) characters left")
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { phrase in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    message = phrase
                } label: {
                    Text(phrase)
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.65))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "hands.clap.fill")
                    .font(.sans(13, weight: .semibold))
                Text("Send cheer")
                    .font(.sans(14, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(trimmed.isEmpty
                          ? Theme.textPrimary.opacity(0.35)
                          : Theme.textPrimary)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
        .accessibilityLabel("Send cheer to \(friend.displayName)")
    }

    private func send() {
        let text = trimmed
        guard !text.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.sendCheer(to: friend, message: text)
        dismiss()
    }
}

#Preview {
    let store = Store()
    return Color.black.opacity(0.2)
        .sheet(isPresented: .constant(true)) {
            if let aaron = store.friends.first {
                CheerComposerView(friend: aaron)
                    .environment(store)
            }
        }
}
