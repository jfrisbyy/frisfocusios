//
//  DirectInboxView.swift
//  FrisFocus
//
//  The "Proofs" surface — a calm, editorial inbox of the people you've
//  privately traded with, one row per friend (never per item). Reached
//  from the small paper-plane button in the Friends area of the Circles
//  page.
//
//  Each row shows the friend in their signature color, their name, a
//  preview of the last thing exchanged (a note's text or a photo/video
//  proof), how long ago, and a quiet dot when they've sent something
//  new. Tapping a person opens the 1:1 thread (`DirectThreadView`),
//  where proofs and notes render together inline. A compose button up
//  top starts a conversation with any friend.
//
//  Proofs sent to a whole circle are intentionally NOT listed here —
//  this surface is person-to-person; circle proofs live in the circle.
//
//  No backend yet — the conversation list and unread counts are derived
//  from the recorded `DirectShare`s on the fly.
//

import AVFoundation
import SwiftUI
import UIKit
import Combine

struct DirectInboxView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The friend whose 1:1 thread is open full-screen, if any.
    @State private var openThread: Friend?
    /// Drives the "start a new conversation" friend picker sheet.
    @State private var showPicker: Bool = false
    /// A friend chosen in the picker, opened once the picker has fully
    /// dismissed so the cover doesn't fight the sheet's animation.
    @State private var pendingThreadFriend: Friend?
    /// The friend a press-and-hold targeted — drives the camera cover
    /// so holding a card fires straight into a proof to that person.
    @State private var proofFriend: Friend?
    /// The friend whose profile is open, if any (tapping their photo).
    @State private var profileTarget: ProfileTarget?

    private var conversations: [DirectConversation] { store.directConversations }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                if conversations.isEmpty {
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
                                ConversationRow(
                                    conversation: convo,
                                    onTap: { open(convo.friend) },
                                    onLongPress: { sendProof(convo.friend) },
                                    onOpenProfile: { openProfile(convo.friend) }
                                )
                            }
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 44)
                    }
                }
            }
        }
        .fullScreenCover(item: $openThread) { friend in
            DirectThreadView(friend: friend)
                .environment(store)
        }
        .fullScreenCover(item: $proofFriend) { friend in
            CaptureView(mode: .generalPost, initialDirectFriendId: friend.id)
                .environment(store)
        }
        .profileDestination($profileTarget, store: store)
        .sheet(isPresented: $showPicker, onDismiss: {
            // Open the chosen thread only after the picker has closed,
            // so the full-screen cover doesn't collide with the sheet's
            // dismissal.
            if let friend = pendingThreadFriend {
                pendingThreadFriend = nil
                openThread = friend
            }
        }) {
            NewProofPickerView { friend in
                pendingThreadFriend = friend
                showPicker = false
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func open(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openThread = friend
    }

    private func startNew() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showPicker = true
    }

    /// Press-and-hold on a conversation card — jump straight to the
    /// camera to send a proof to just that person.
    private func sendProof(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        proofFriend = friend
    }

    /// Tapping a person's photo opens their profile; the rest of the
    /// row still opens the conversation.
    private func openProfile(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        profileTarget = .friend(friend)
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

    // MARK: - Empty state

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
}

// MARK: - Conversation row

/// One person in the Proofs inbox: signature-color avatar, name, a
/// one-line preview of the latest exchange, the elapsed time, and a
/// quiet unread dot. Tapping opens the 1:1 thread.
private struct ConversationRow: View {
    @Environment(Store.self) private var store
    let conversation: DirectConversation
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onOpenProfile: () -> Void

    @State private var pressed: Bool = false

    private var friend: Friend { conversation.friend }
    private var latest: DirectShare { conversation.latest }
    private var isUnread: Bool { conversation.unreadCount > 0 }
    private var isMine: Bool { latest.authorId == store.currentUserId }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenProfile()
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(friend.displayName)'s profile")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if isUnread {
                        Circle()
                            .fill(Color(hex: friend.accentColorHex))
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

    private var avatar: some View {
        ZStack {
            Circle().fill(Color(hex: friend.accentColorHex))
            Text(friend.initials)
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 52, height: 52)
        .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5))
    }

    @ViewBuilder
    private var previewLine: some View {
        HStack(spacing: 5) {
            if latest.isProof {
                Image(systemName: mediaGlyph)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(isUnread ? 0.85 : 0.55))
            }
            Text(previewText)
                .font(.sans(13, weight: isUnread ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(isUnread ? 0.92 : 0.65))
                .lineLimit(1)
        }
    }

    private var mediaGlyph: String {
        store.mediaAsset(forDirectShare: latest)?.type == .video ? "video.fill" : "camera.fill"
    }

    /// "You: Made the 6am class" / "Photo proof" / "Sent you a note" —
    /// a calm one-liner from the current user's point of view.
    private var previewText: String {
        let caption = latest.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let caption, !caption.isEmpty {
            body = caption
        } else if latest.isProof {
            body = store.mediaAsset(forDirectShare: latest)?.type == .video ? "Video proof" : "Photo proof"
        } else {
            body = "Note"
        }
        return isMine ? "You: \(body)" : body
    }
}

// MARK: - New conversation picker

/// A calm friend picker for starting (or jumping back into) a private
/// conversation. Lists every friend by name; tapping one hands the
/// chosen friend back so the inbox can open their thread.
private struct NewProofPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onPick: (Friend) -> Void

    private var friends: [Friend] {
        store.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

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

    private func pickerRow(_ friend: Friend) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPick(friend)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: friend.accentColorHex))
                    Text(friend.initials)
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let season = friend.currentSeasonName {
                        Text(season)
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
}

// MARK: - Full-screen proof player

/// Identifiable wrapper so a proof play-queue can drive a
/// `fullScreenCover(item:)`. The id is the first proof's id — stable
/// for the life of the presentation.
struct ProofPlayback: Identifiable {
    let shares: [DirectShare]
    let id: UUID

    init(shares: [DirectShare]) {
        self.shares = shares
        self.id = shares.first?.id ?? UUID()
    }
}

/// A calm, timed player for one or more proofs. Photos linger a few
/// seconds, videos play their length; a thin segmented bar tracks
/// progress. Tapping advances, holding pauses, swiping down leaves —
/// and when the last proof finishes the player exits on its own. It
/// never opens the camera. Each proof is stamped watched as it plays,
/// which flips its chat pill to the "Reply with a proof" state back in
/// the thread.
struct DirectShareViewerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let shares: [DirectShare]

    // MARK: Playback state

    @State private var currentIndex: Int = 0
    /// 25 Hz segment progress, boxed so ticks re-render only the bars
    /// leaf — not this whole player (see `PlaybackClock`).
    @State private var clock = PlaybackClock()
    @State private var isPaused: Bool = false
    /// Interactive dismissal — the card scales, rounds, and follows the
    /// finger; the backdrop fades; release is velocity-aware.
    @State private var drag = PlayerDragMetrics()
    @State private var crossedDismissThreshold: Bool = false
    @State private var pressStart: Date?

    private let tick: TimeInterval = 0.04
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()
    private let photoDuration: TimeInterval = 5.0

    // MARK: Derived

    private var currentShare: DirectShare? {
        guard currentIndex >= 0 && currentIndex < shares.count else { return nil }
        return shares[currentIndex]
    }

    private var currentMedia: MediaAsset? {
        guard let share = currentShare else { return nil }
        return store.mediaAsset(forDirectShare: share)
    }

    /// Decoded once per segment (onAppear / index change). The old
    /// computed property re-read and re-decoded the file from disk on
    /// every body evaluation.
    @State private var loadedImage: UIImage?

    private func loadCurrentImage() {
        guard let url = currentMedia?.resolvedLocalURL else {
            loadedImage = nil
            return
        }
        loadedImage = DirectShareFormat.image(at: url)
    }

    private var currentDuration: TimeInterval {
        if let media = currentMedia, media.type == .video,
           let dur = media.durationSeconds, dur > 0 {
            return dur
        }
        return photoDuration
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            ZStack {
                // The backdrop stays put and fades as the card is dragged.
                Color.black
                    .opacity(drag.backdropOpacity)
                    .ignoresSafeArea()

                playerCard(bottomInset: bottomInset)
                    .playerCardEffect(drag)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .onReceive(timer) { _ in tickProgress() }
        .onAppear {
            if shares.isEmpty {
                DispatchQueue.main.async { dismiss() }
                return
            }
            loadCurrentImage()
            markCurrentViewed()
        }
        .onChange(of: currentIndex) { _, _ in
            loadCurrentImage()
            markCurrentViewed()
        }
    }

    // MARK: - Card

    /// The full-bleed player card: media, gesture layer, and chrome.
    /// Separated from the backdrop so interactive dismissal can scale
    /// and round it as one piece.
    private func playerCard(bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black

            mediaLayer

            // Transparent gesture receiver behind the chrome. Tap zones,
            // hold-to-pause and swipe-down dismiss all route through it.
            GeometryReader { geo in
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(unifiedGesture(width: geo.size.width))
            }

            VStack(spacing: 0) {
                progressBars
                    .padding(.horizontal, 10)
                    .padding(.top, 54)

                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 12)

                Spacer()

                captionOverlay
                    .padding(.bottom, bottomInset)
            }
        }
    }

    // MARK: - Progress bars

    private var progressBars: some View {
        SegmentedProgressBars(count: shares.count, currentIndex: currentIndex, clock: clock)
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaLayer: some View {
        if let media = currentMedia, media.type == .video, let url = media.resolvedLocalURL {
            // Video proofs play on a loop, with sound, letterboxed to
            // their true shape. Holding to pause stops the clip too.
            VideoLoopView(url: url, gravity: .resizeAspect, isPaused: isPaused)
                .id(url)
        } else if let image = loadedImage {
            // Shape-aware: show the whole card centered with a blurred
            // copy filling the edges — no over-zoom cropping.
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 42, opaque: true)
                        .overlay(Color.black.opacity(0.28))

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        } else {
            captionOnlyBackground
        }
    }

    private var captionOnlyBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x2A2438),
                    Color(hex: 0x4A3C50),
                    Color(hex: 0x6B4D52)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let caption = currentShare?.caption, !caption.isEmpty {
                Text(caption)
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Caption overlay

    @ViewBuilder
    private var captionOverlay: some View {
        if loadedImage != nil,
           let caption = currentShare?.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            Text(caption)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textCream)
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 1)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let share = currentShare {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.directShareCounterpartLabel(share))
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                    Text(DirectShareFormat.elapsed(from: share.createdAt))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.75))
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
    }

    // MARK: - Playback

    private func markCurrentViewed() {
        guard let share = currentShare else { return }
        store.markProofViewed(share.id)
    }

    private func tickProgress() {
        guard !isPaused, currentShare != nil else { return }
        let increment = tick / max(0.1, currentDuration)
        clock.progress += increment
        if clock.progress >= 1 {
            advance()
        }
    }

    private func advance() {
        if currentIndex + 1 >= shares.count {
            dismiss()
            return
        }
        currentIndex += 1
        clock.progress = 0
    }

    private func goPrev() {
        if currentIndex == 0 {
            clock.progress = 0
        } else {
            currentIndex -= 1
            clock.progress = 0
        }
    }

    private func goNext() { advance() }

    // MARK: - Unified press / tap / drag gesture

    private func unifiedGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    isPaused = true
                }
                if value.translation.height > 0 {
                    drag.translation = value.translation
                    let past = value.translation.height > 150
                    if past != crossedDismissThreshold {
                        crossedDismissThreshold = past
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    drag.translation = .zero
                }
            }
            .onEnded { value in
                let start = pressStart ?? Date()
                let pressDuration = Date().timeIntervalSince(start)
                let movement = hypot(value.translation.width, value.translation.height)
                pressStart = nil
                crossedDismissThreshold = false

                // Velocity-aware: a long pull or a quick flick both leave.
                if PlayerDragMetrics.shouldDismiss(translation: value.translation, predicted: value.predictedEndTranslation) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    return
                }

                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { drag.translation = .zero }
                isPaused = false

                // Short, low-movement release = tap. Long holds just
                // resume playback.
                if pressDuration < 0.25 && movement < 10 {
                    if value.startLocation.x < width / 3 {
                        goPrev()
                    } else {
                        goNext()
                    }
                }
            }
    }
}

// MARK: - Shared formatting helpers

enum DirectShareFormat {
    static func image(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// "just now" / "12 min ago" / "3 hr ago" / "2 d ago" — warmth of
    /// elapsed time rather than a countdown, matching the story player.
    static func elapsed(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "1 d ago" : "\(days) d ago"
    }
}

#Preview {
    DirectInboxView()
        .environment(Store())
}
