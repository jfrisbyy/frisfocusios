//
//  SharePreviewView.swift
//  FrisFocus
//
//  Post-capture preview — the composed moment framed in the final 9:16
//  story shape (WYSIWYG with what posts), with the same destination
//  picker a normal proof gets:
//
//   • The destination pill — "Friends · 24h" by default — opens the
//     familiar chooser: the 24-hour story and/or hand-picked friends
//     and circles, any combination. Everything in-app is the CLEAN
//     card: no attribution line, no wordmark; identity is implicit.
//   • "Share outside" — the native iOS share sheet (Instagram,
//     iMessage, save to camera roll). The composite ALWAYS carries the
//     attribution line: orb glyph + "@USERNAME · FRISFOCUS". This rule
//     is baked into the destination, never a toggle.
//
//  One renderer, a destination parameter — identical overlay
//  composition, attribution added only for external/save. Everything
//  composites locally; zero API calls.
//

import AVFoundation
import SwiftUI
import UIKit

/// Where the composed card goes when sent in-app. Mirrors the proof
/// editor's audience model: the public 24 h story plus any number of
/// hand-picked friends and circles.
private struct ShareCardAudience: Equatable {
    var everyone: Bool
    var friendIds: Set<UUID>
    var circleIds: Set<UUID>

    static let initial = ShareCardAudience(everyone: true, friendIds: [], circleIds: [])

    var isPristineEveryone: Bool {
        everyone && friendIds.isEmpty && circleIds.isEmpty
    }

    var hasPrivateRecipients: Bool {
        !friendIds.isEmpty || !circleIds.isEmpty
    }
}

struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: CaptureResult
    let context: ShareDayContext
    let options: ShareOverlayOptions
    let username: String
    /// Called after a successful post/share so the camera dismisses too.
    let onFinished: () -> Void

    @State private var isWorking: Bool = false
    @State private var sharePayload: SharePayload?
    @State private var postedConfirmation: String?

    // Destination state — the same any-combination model as a proof.
    @State private var audience: ShareCardAudience = .initial
    @State private var showAudiencePanel: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // The story-shaped card — exactly the frame that posts.
                storyCard
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomArea
            }

            if isWorking {
                workingVeil
            }

            if let postedConfirmation {
                postedToast(postedConfirmation)
            }
        }
        .statusBarHidden()
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showAudiencePanel)
    }

    // MARK: - Story card (9:16 — WYSIWYG with the export)

    /// The captured media center-cropped into the 9:16 story shape with
    /// the live overlay on top — previewing the CLEAN in-app card (the
    /// attribution line only exists on the external composite).
    private var storyCard: some View {
        mediaLayer
            .overlay {
                ShareOverlayView(
                    context: context,
                    options: options,
                    mode: .render(attributed: false),
                    username: username,
                    bottomPadding: 26
                )
                .allowsHitTesting(false)
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaLayer: some View {
        switch result {
        case .photo(let image):
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        case .video(let url, _, _):
            VideoLoopView(url: url, gravity: .resizeAspectFill)
                .id(url)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel("Retake")

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var bottomArea: some View {
        VStack(spacing: 12) {
            if showAudiencePanel {
                audiencePanel
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                destinationPill

                Button {
                    sendInApp()
                } label: {
                    HStack(spacing: 7) {
                        Text("Send")
                            .font(.sans(15, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x2C2C2A))
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(Capsule().fill(Color(hex: 0xFAEEDA)))
                }
                .accessibilityLabel("Send to \(audienceTitle)")
                .accessibilityHint("Sends the clean card, without the watermark")
            }
            .padding(.horizontal, 20)

            Button {
                shareOutside()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Share outside · adds @\(username.uppercased()) · FRISFOCUS")
                        .font(.sans(12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .accessibilityLabel("Share outside")
            .accessibilityHint("Opens the share sheet with your attributed card")
        }
        .padding(.bottom, 20)
        .disabled(isWorking)
    }

    // MARK: - Destination pill

    private var destinationPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAudiencePanel.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(destinationTint.opacity(0.22))
                        .frame(width: 30, height: 30)
                    Image(systemName: audienceIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(destinationTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(audienceTitle)
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(audienceSubtitle)
                        .font(.sans(10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Image(systemName: showAudiencePanel ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(Capsule().fill(Color.white.opacity(showAudiencePanel ? 0.16 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send to \(audienceTitle). Tap to change.")
    }

    private var audienceIcon: String {
        if audience.isPristineEveryone { return "person.2.fill" }
        let friendCount = audience.friendIds.count
        let circleCount = audience.circleIds.count
        if !audience.everyone && friendCount == 1 && circleCount == 0 { return "person.fill" }
        if !audience.everyone && friendCount == 0 && circleCount == 1 { return "circle.hexagongrid.fill" }
        return "person.3.fill"
    }

    private var destinationTint: Color {
        audience.isPristineEveryone ? Color(hex: 0xD87D44) : Color(hex: 0x8FB339)
    }

    private var audienceTitle: String {
        if audience.isPristineEveryone { return "Friends · 24h" }
        return summaryLabel(tokens: audienceTokens, empty: "Select destination")
    }

    private var audienceSubtitle: String {
        if audience.isPristineEveryone { return "Clean card · no watermark" }
        if audience.everyone { return "Story + a copy to each" }
        let count = audience.friendIds.count + audience.circleIds.count
        return count <= 1 ? "A private send · just them" : "A private send to each"
    }

    private var selectedCircles: [FFCircle] {
        audience.circleIds
            .compactMap { store.circle(by: $0) }
            .sorted { $0.name < $1.name }
    }

    private var selectedFriends: [Friend] {
        audience.friendIds
            .compactMap { store.friend(by: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var audienceTokens: [String] {
        var tokens: [String] = []
        if audience.everyone { tokens.append("Friends · 24h") }
        tokens.append(contentsOf: selectedCircles.map { $0.name })
        tokens.append(contentsOf: selectedFriends.map { $0.displayName })
        return tokens
    }

    private var privateTokens: [String] {
        selectedCircles.map { $0.name } + selectedFriends.map { $0.displayName }
    }

    private func summaryLabel(tokens: [String], empty: String) -> String {
        guard let first = tokens.first else { return empty }
        if tokens.count == 1 { return first }
        let others = tokens.count - 1
        return "\(first) + \(others) other\(others == 1 ? "" : "s")"
    }

    // MARK: - Audience chooser panel

    private var myCircles: [FFCircle] {
        store.circles.filter { $0.memberIds.contains(store.currentUserId) }
    }

    private var audiencePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Send to")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Button {
                    showAudiencePanel = false
                } label: {
                    Text("Done")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFAEEDA))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    audienceOptionRow(
                        icon: "person.2.fill",
                        title: "Friends · 24h",
                        subtitle: "Your public story",
                        tint: Color(hex: 0xD87D44),
                        selected: audience.everyone
                    ) { toggleEveryone() }

                    if !store.friends.isEmpty {
                        panelSectionLabel("FRIENDS")
                        ForEach(store.friends) { friend in
                            audienceFriendRow(friend)
                        }
                    }

                    if !myCircles.isEmpty {
                        panelSectionLabel("CIRCLES")
                        ForEach(myCircles) { circle in
                            audienceCircleRow(circle)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: 280)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0x1E1C1B).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 18, y: 8)
    }

    private func panelSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func audienceOptionRow(
        icon: String,
        title: String,
        subtitle: String?,
        tint: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func audienceFriendRow(_ friend: Friend) -> some View {
        let selected = audience.friendIds.contains(friend.id)
        return Button { toggleFriend(friend.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: friend.accentColorHex)).frame(width: 34, height: 34)
                    Text(friend.initials)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                }
                Text(friend.displayName)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(friend.displayName)
        .accessibilityValue(selected ? "selected" : "not selected")
    }

    private func audienceCircleRow(_ circle: FFCircle) -> some View {
        let selected = audience.circleIds.contains(circle.id)
        let count = circle.memberIds.count
        return Button { toggleCircle(circle.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: 0xC59A5C).opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC59A5C))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(circle.name)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text("\(count) member\(count == 1 ? "" : "s")")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(circle.name)
        .accessibilityValue(selected ? "selected" : "not selected")
    }

    private func checkMark(_ selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.3), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if selected {
                Circle().fill(Theme.alertGreen).frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    // MARK: - Audience selection

    private func toggleEveryone() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            audience.everyone.toggle()
            normalizeAudience()
        }
    }

    private func toggleFriend(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            if audience.isPristineEveryone { audience.everyone = false }
            if audience.friendIds.contains(id) {
                audience.friendIds.remove(id)
            } else {
                audience.friendIds.insert(id)
            }
            normalizeAudience()
        }
    }

    private func toggleCircle(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            if audience.isPristineEveryone { audience.everyone = false }
            if audience.circleIds.contains(id) {
                audience.circleIds.remove(id)
            } else {
                audience.circleIds.insert(id)
            }
            normalizeAudience()
        }
    }

    /// Never leave the send button with nowhere to go: if everything
    /// gets deselected, fall back to the public story.
    private func normalizeAudience() {
        if !audience.everyone && !audience.hasPrivateRecipients {
            audience.everyone = true
        }
    }

    // MARK: - Veil + toast

    private var workingVeil: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Composing…")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.opacity)
    }

    private func postedToast(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0xFFC668))
                Text(text)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .padding(.bottom, 140)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Destinations

    /// Composes the CLEAN card once (no attribution — it stays inside
    /// the app) and delivers it to every chosen destination: a story
    /// post and/or one private send per selected friend and circle.
    private func sendInApp() {
        guard !isWorking else { return }
        isWorking = true
        if showAudiencePanel { showAudiencePanel = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            let mediaData: Data?
            let mediaType: MediaType
            let duration: Double?

            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    context: context,
                    options: options,
                    username: username,
                    attributed: false
                )
                mediaData = composed?.jpegData(compressionQuality: 0.9)
                mediaType = .photo
                duration = nil

            case .video(let url, _, let dur):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    context: context,
                    options: options,
                    username: username,
                    attributed: false,
                    animated: !reduceMotion
                )
                mediaData = try? Data(contentsOf: composedURL ?? url)
                mediaType = .video
                duration = dur
            }

            guard let mediaData else {
                isWorking = false
                return
            }

            var toast = "Posted to your people"
            if audience.everyone {
                store.postMedia(
                    imageData: mediaData,
                    type: mediaType,
                    caption: nil,
                    circleId: nil,
                    attachedCircleTaskId: nil,
                    durationSeconds: duration
                )
            }
            if audience.hasPrivateRecipients {
                store.sendDirect(
                    imageData: mediaData,
                    type: mediaType,
                    caption: nil,
                    friendIds: Array(audience.friendIds),
                    circleIds: Array(audience.circleIds),
                    durationSeconds: duration
                )
                toast = audience.everyone
                    ? "Posted + sent to \(summaryLabel(tokens: privateTokens, empty: "your picks"))"
                    : "Sent to \(summaryLabel(tokens: privateTokens, empty: "your picks"))"
            }

            isWorking = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.25)) { postedConfirmation = toast }
            try? await Task.sleep(for: .seconds(0.9))
            onFinished()
        }
    }

    /// External — attributed composite into the native share sheet
    /// (which also covers save-to-camera-roll, equally attributed).
    private func shareOutside() {
        guard !isWorking else { return }
        isWorking = true
        if showAudiencePanel { showAudiencePanel = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    context: context,
                    options: options,
                    username: username,
                    attributed: true
                )
                isWorking = false
                if let composed {
                    sharePayload = SharePayload(items: [composed])
                }

            case .video(let url, _, _):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    context: context,
                    options: options,
                    username: username,
                    attributed: true,
                    animated: !reduceMotion
                )
                isWorking = false
                if let composedURL {
                    sharePayload = SharePayload(items: [composedURL])
                } else {
                    // Compositing unavailable (no hardware decode path) —
                    // never strand the user; share the raw clip.
                    sharePayload = SharePayload(items: [url])
                }
            }
        }
    }
}

// MARK: - Share sheet plumbing

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
