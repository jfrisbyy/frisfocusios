//
//  ProofThreadView.swift
//  FrisFocus
//
//  The real, private 1:1 thread between the signed-in user and one
//  actual friend — backed by Supabase (`MessageGraphService`) and
//  updating live. A calm way to share a real moment (a proof) or a
//  quiet note with one person.
//
//  Notes (text) and proofs (media) are both `DirectMessage`s; they
//  render together in one stream — notes as bubbles, proofs as quiet
//  pills. Sending a note writes a text row; "Send a proof" opens the
//  capture flow wired straight to this friend through the service's
//  private storage.
//

import SwiftUI
import UIKit

struct ProofThreadView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let friend: RemoteProfile
    /// Shared with the inbox so realtime + optimistic state stay in sync.
    let message: MessageGraphService
    let myUserId: String

    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool
    @State private var showCapture: Bool = false
    /// The proof open full-screen in the player, if any.
    @State private var playerProof: DirectMessage?

    private var thread: [DirectMessage] {
        message.thread(withFriendId: friend.id, myUserId: myUserId)
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                Divider().overlay(Theme.textPrimary.opacity(0.08))

                if thread.isEmpty {
                    emptyState
                } else {
                    threadScroll
                }

                composer
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView(
                mode: .generalPost,
                liveProofRecipientName: friend.displayName,
                onSendLiveProof: { data, isVideo, duration, caption in
                    await message.sendProof(
                        to: friend.id,
                        data: data,
                        mediaKind: isVideo ? .video : .photo,
                        durationSeconds: duration,
                        caption: caption,
                        myUserId: myUserId
                    )
                }
            )
            .environment(store)
        }
        .fullScreenCover(item: $playerProof) { proof in
            ProofPlayerView(proof: proof, friend: friend, message: message, myUserId: myUserId)
        }
        .onAppear {
            Task { await message.markThreadRead(withFriendId: friend.id, myUserId: myUserId) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                RemoteAvatarView(profile: friend, size: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("PRIVATELY")
                        .font(.sans(9, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Text(friend.displayName)
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Thread

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(thread) { item in
                        ProofThreadBubble(
                            message: item,
                            friend: friend,
                            isMine: item.isMine(myUserId),
                            onOpenProof: { openProof(item) },
                            onReplyWithProof: { replyWithProof() }
                        )
                        .id(item.id)
                    }
                    Color.clear.frame(height: 4).id(bottomAnchor)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .onAppear { scrollToBottom(proxy) }
            .onChange(of: thread.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { scrollToBottom(proxy) }
            }
        }
    }

    private let bottomAnchor = "thread.bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(bottomAnchor, anchor: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle().fill(friend.signatureColor.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "paperplane")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(friend.signatureColor.opacity(0.85))
            }
            Text("Just you two")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Send \(friend.displayName) a proof of a real moment, or a quiet note.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCapture = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.textPrimary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send a proof to \(friend.displayName)")

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Message \(friend.displayName)…")
                        .foregroundColor(Theme.textPrimary.opacity(0.45)),
                    axis: .horizontal
                )
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .tint(friend.signatureColor)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit(sendNote)

                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: sendNote) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(friend.signatureColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            Theme.warmWheat
                .overlay(Rectangle().fill(Theme.textPrimary.opacity(0.06)).frame(height: 0.5), alignment: .top)
        )
    }

    private func sendNote() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        draft = ""
        Task { await message.sendNote(to: friend.id, text: trimmed, myUserId: myUserId) }
    }

    /// Open the tapped proof full-screen. The player marks an incoming
    /// proof watched as it plays, flipping its pill to "Reply with a
    /// proof"; an own proof simply replays.
    private func openProof(_ proof: DirectMessage) {
        guard proof.isProof else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        playerProof = proof
    }

    /// Fire the camera at this friend to send a proof back — the
    /// deliberate, opt-in reply (the player never opens it for you).
    private func replyWithProof() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showCapture = true
    }
}

// MARK: - Bubble

private struct ProofThreadBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: DirectMessage
    let friend: RemoteProfile
    let isMine: Bool
    let onOpenProof: () -> Void
    let onReplyWithProof: () -> Void

    private var accent: Color { friend.signatureColor }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if message.isProof {
                    proofPill
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: message.isWatched)
                } else {
                    messageBubble
                }
                Text(ProofThreadFormat.elapsed(from: message.createdAt))
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 48) }
        }
    }

    private var messageBubble: some View {
        Text(message.body ?? "")
            .font(.sans(15, weight: .regular))
            .foregroundStyle(isMine ? Theme.textCream : Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isMine ? Theme.textPrimary : Color.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(isMine ? 0 : 0.08), lineWidth: 0.5)
            )
    }

    // MARK: - Proof pill
    //
    // The proof's media is never shown inline — only a quiet marker.
    // Tapping a received proof opens the full-screen player; once
    // watched, the line flips into a "Reply with a proof" button. Your
    // own proofs stay tappable to re-watch.

    @ViewBuilder
    private var proofPill: some View {
        if isMine {
            proofChip(
                icon: "checkmark.seal.fill",
                title: "You sent a proof",
                tint: Theme.textCream,
                background: Theme.textPrimary,
                bordered: false,
                action: onOpenProof
            )
            .accessibilityLabel("You sent a proof. Tap to watch again.")
        } else if !message.isWatched {
            proofChip(
                icon: "camera.fill",
                title: "\(friend.displayName) sent a proof",
                subtitle: "Tap to view",
                tint: Theme.textPrimary,
                background: Color.white.opacity(0.85),
                bordered: true,
                showChevron: true,
                accentDot: true,
                action: onOpenProof
            )
            .accessibilityLabel("\(friend.displayName) sent a proof. Tap to view.")
        } else {
            proofChip(
                icon: "arrowshape.turn.up.left.fill",
                title: "Reply with a proof",
                tint: Theme.textCream,
                background: accent,
                bordered: false,
                action: onReplyWithProof
            )
            .accessibilityLabel("Reply to \(friend.displayName) with a proof")
        }
    }

    private func proofChip(
        icon: String,
        title: String,
        subtitle: String? = nil,
        tint: Color,
        background: Color,
        bordered: Bool,
        showChevron: Bool = false,
        accentDot: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Image(systemName: icon)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(tint)
                    if accentDot {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 9, y: -8)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(tint)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(tint.opacity(0.7))
                    }
                }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(bordered ? 0.08 : 0), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formatting

enum ProofThreadFormat {
    static func elapsed(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days)d ago"
    }
}
