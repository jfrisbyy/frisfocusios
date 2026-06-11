//
//  ProofsInboxView.swift
//  FrisFocus
//
//  The real "Proofs" surface — a calm, editorial inbox of the people
//  you've privately traded notes and proofs with, backed by Supabase
//  (`MessageGraphService`) rather than the seeded local store. One row
//  per real friend (never per item), newest exchange first.
//
//  Each row shows the friend in their signature color (their photo when
//  they have one), their name, a one-line preview of the last thing
//  exchanged, how long ago, and a quiet dot when they've sent something
//  new. Tapping a person opens the live 1:1 thread (`ProofThreadView`);
//  a compose button starts a conversation with any real friend; a
//  press-and-hold fires straight into the camera to send that person a
//  proof. New messages arrive live via the service's realtime feed.
//

import SwiftUI
import UIKit

// MARK: - Signature color + avatar (shared by the live messaging surfaces)

extension RemoteProfile {
    /// A stable, warm signature color derived from the account id, so a
    /// friend without a photo still reads as a distinct, consistent
    /// person across the inbox, threads, and the player.
    var signatureColor: Color {
        let palette: [UInt32] = [
            0xD87D44, 0x8FB339, 0x5B8AA6, 0xC65B7C,
            0x9B6BC2, 0xCBA135, 0x4FA68B, 0xCF6A4A
        ]
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Color(hex: palette[Int(hash % UInt64(palette.count))])
    }
}

/// A friend's signature avatar: their photo when they have one, else
/// their initials on their stable per-person color.
struct RemoteAvatarView: View {
    let profile: RemoteProfile
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.07), lineWidth: 0.5))
    }

    private var initials: some View {
        ZStack {
            Circle().fill(profile.signatureColor)
            Text(profile.initials)
                .font(.sans(size * 0.34, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }
}

// MARK: - Inbox

struct ProofsInboxView: View {
    /// When set (from a tapped push), the inbox opens this person's 1:1
    /// thread automatically once its data has loaded.
    var initialPeerId: String? = nil
    /// The specific message the push was about. When it resolves to a
    /// proof, the auto-opened thread drops straight into the full-screen
    /// player — the notification lands you inside the moment.
    var initialMessageId: String? = nil

    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(\.dismiss) private var dismiss

    /// The real messaging backend. Owned here and shared into the thread
    /// so realtime + optimistic state stay consistent across both.
    @State private var message = MessageGraphService()
    /// The real friend graph — powers the new-conversation picker.
    @State private var friendGraph = FriendGraphService()

    /// The friend whose 1:1 thread is open full-screen, if any.
    @State private var openFriend: RemoteProfile?
    /// Drives the "start a new conversation" friend picker sheet.
    @State private var showPicker: Bool = false
    /// A friend chosen in the picker, opened once the picker has fully
    /// dismissed so the cover doesn't fight the sheet's animation.
    @State private var pendingThreadFriend: RemoteProfile?
    /// The friend a press-and-hold targeted — drives the camera cover.
    @State private var proofFriend: RemoteProfile?
    /// Ensures a push-delivered `initialPeerId` only auto-opens once.
    @State private var didTryInitialPeer: Bool = false
    /// The message id handed to the auto-opened thread, consumed once.
    @State private var pendingInitialMessageId: String?

    private var myId: String? { auth.user?.id }

    private var conversations: [DirectConversationSummary] {
        guard let myId else { return [] }
        return message.conversations(myUserId: myId).filter { !moderation.isBlocked($0.friend.id) }
    }

    var body: some View {
        @Bindable var message = message

        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            if myId == nil {
                signedOut
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    if message.isLoading && conversations.isEmpty {
                        loading
                    } else if conversations.isEmpty {
                        emptyState
                    } else {
                        Text("Tap to open · hold a name to send a proof")
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.bottom, 4)

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 10) {
                                ForEach(conversations) { convo in
                                    ProofConversationRow(
                                        summary: convo,
                                        isMine: convo.latest.isMine(myId ?? ""),
                                        onTap: { open(convo.friend) },
                                        onLongPress: { sendProof(convo.friend) }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.pageHorizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 44)
                            .animation(.easeOut(duration: 0.25), value: conversations.count)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onDisappear { message.stopRealtime() }
        .fullScreenCover(item: $openFriend, onDismiss: {
            pendingInitialMessageId = nil
        }) { friend in
            ProofThreadView(
                friend: friend,
                message: message,
                myUserId: myId ?? "",
                initialProofMessageId: pendingInitialMessageId
            )
            .environment(store)
            .environment(auth)
            .environment(moderation)
        }
        .fullScreenCover(item: $proofFriend) { friend in
            CaptureView(
                mode: .generalPost,
                liveProofRecipientName: friend.displayName,
                onSendLiveProof: { data, isVideo, duration, caption in
                    guard let myId else { return }
                    await message.sendProof(
                        to: friend.id,
                        data: data,
                        mediaKind: isVideo ? .video : .photo,
                        durationSeconds: duration,
                        caption: caption,
                        myUserId: myId
                    )
                }
            )
            .environment(store)
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            // Open the chosen thread only after the picker has closed, so
            // the full-screen cover doesn't collide with the sheet's
            // dismissal.
            if let friend = pendingThreadFriend {
                pendingThreadFriend = nil
                openFriend = friend
            }
        }) {
            NewProofFriendPicker(
                friends: friendGraph.friends.filter { !moderation.isBlocked($0.id) },
                isLoading: friendGraph.isLoading
            ) { friend in
                pendingThreadFriend = friend
                showPicker = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Something went wrong", isPresented: $message.showError) {
            Button("OK") { }
        } message: {
            Text(message.errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Actions

    private func load() async {
        guard let myId else { return }
        await message.load(myUserId: myId)
        message.startRealtime(myUserId: myId)
        await friendGraph.load(myUserId: myId)
        await openInitialPeerIfNeeded(myId: myId)
    }

    /// Auto-open the 1:1 thread for a push-delivered peer id, resolving the
    /// profile from the messages we just loaded, then the friend graph,
    /// then a direct fetch. Runs at most once.
    private func openInitialPeerIfNeeded(myId: String) async {
        guard !didTryInitialPeer,
              let peerId = initialPeerId,
              !peerId.isEmpty,
              peerId != myId else { return }
        didTryInitialPeer = true
        guard !moderation.isBlocked(peerId) else { return }
        pendingInitialMessageId = initialMessageId
        if let profile = message.profile(for: peerId) ?? friendGraph.friends.first(where: { $0.id == peerId }) {
            openFriend = profile
        } else if let fetched = await friendGraph.fetchProfile(id: peerId) {
            openFriend = fetched
        }
    }

    private func open(_ friend: RemoteProfile) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openFriend = friend
    }

    private func startNew() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showPicker = true
    }

    /// Press-and-hold on a conversation card — jump straight to the
    /// camera to send a proof to just that person.
    private func sendProof(_ friend: RemoteProfile) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        proofFriend = friend
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PRIVATELY SHARED")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("Proofs")
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            Button(action: startNew) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new conversation")

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

    // MARK: - States

    private var loading: some View {
        VStack {
            Spacer()
            ProgressView().tint(Theme.textPrimary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.textPrimary.opacity(0.05))
                    .frame(width: 64, height: 64)
                Image(systemName: "paperplane")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            Text("No proofs yet")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Send a friend a proof of a real moment, or a quiet note. Your conversations live here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: startNew) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil").font(.sans(13, weight: .semibold))
                    Text("Start a conversation").font(.sans(14, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule(style: .continuous).fill(Theme.textPrimary))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Sign in to message friends")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Your private proofs and notes live in your account, in sync across your devices.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Done")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule(style: .continuous).fill(Theme.textPrimary))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

// MARK: - Conversation row

/// One person in the Proofs inbox: signature-color avatar, name, a
/// one-line preview of the latest exchange, the elapsed time, and a
/// quiet unread dot. Tapping opens the live 1:1 thread.
private struct ProofConversationRow: View {
    let summary: DirectConversationSummary
    let isMine: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressed: Bool = false

    private var friend: RemoteProfile { summary.friend }
    private var latest: DirectMessage { summary.latest }
    private var isUnread: Bool { summary.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            RemoteAvatarView(profile: friend, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if isUnread {
                        Circle()
                            .fill(friend.signatureColor)
                            .frame(width: 7, height: 7)
                    }

                    Spacer(minLength: 4)

                    Text(DirectShareFormat.elapsed(from: latest.createdAt))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .layoutPriority(1)
                }

                previewLine
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isUnread ? 0.78 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.18), value: pressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(
            minimumDuration: 0.4,
            maximumDistance: 16,
            pressing: { isPressing in pressed = isPressing },
            perform: { onLongPress() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Conversation with \(friend.displayName)")
        .accessibilityValue(previewText + (isUnread ? ". Unread." : ""))
        .accessibilityHint("Double tap to open.")
        .accessibilityAction(named: "Send a proof") { onLongPress() }
    }

    @ViewBuilder
    private var previewLine: some View {
        HStack(spacing: 5) {
            if latest.isProof {
                Image(systemName: latest.mediaKind == .video ? "video.fill" : "camera.fill")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(isUnread ? 0.85 : 0.55))
            }
            Text(previewText)
                .font(.sans(13, weight: isUnread ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(isUnread ? 0.92 : 0.65))
                .lineLimit(1)
        }
    }

    /// "You: Made the 6am class" / "Photo proof" / "Note" — a calm
    /// one-liner from the current user's point of view.
    private var previewText: String {
        let caption = latest.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let core: String
        if let caption, !caption.isEmpty {
            core = caption
        } else if latest.isProof {
            core = latest.mediaKind == .video ? "Video proof" : "Photo proof"
        } else {
            core = "Note"
        }
        return isMine ? "You: \(core)" : core
    }
}

// MARK: - New conversation picker

/// A calm friend picker for starting (or jumping back into) a private
/// conversation. Lists the user's real friends by name; tapping one
/// hands the chosen friend back so the inbox can open their thread. A
/// friendly nudge points to the Friends screen when there are none yet.
private struct NewProofFriendPicker: View {
    @Environment(\.dismiss) private var dismiss

    let friends: [RemoteProfile]
    let isLoading: Bool
    let onPick: (RemoteProfile) -> Void

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if friends.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(friends) { friend in
                                pickerRow(friend)
                            }
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 44)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SEND PRIVATELY")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("New conversation")
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
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

    private func pickerRow(_ friend: RemoteProfile) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(friend)
        } label: {
            HStack(spacing: 12) {
                RemoteAvatarView(profile: friend, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let email = friend.email, email != friend.displayName {
                        Text(email)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Message \(friend.displayName)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if isLoading {
                ProgressView().tint(Theme.textPrimary)
            } else {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.05)).frame(width: 64, height: 64)
                    Image(systemName: "person.2")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                Text("No friends yet")
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add a friend by email from the Friends screen, then you can send them proofs and notes here.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ProofsInboxView()
        .environment(Store())
        .environment(AuthManager())
}
