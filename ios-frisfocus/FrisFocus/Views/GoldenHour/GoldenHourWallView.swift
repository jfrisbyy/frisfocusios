//
//  GoldenHourWallView.swift
//  FrisFocus
//
//  The ephemeral wall: a grid of today's captures that exists for
//  exactly one hour from the fire instant, then vanishes for good.
//
//  Rules enforced here visually (and by the sweep for real):
//   • Post-to-see — everyone else's tiles stay blurred until you've
//     posted yours. Missed the window? The wall stays blurred forever.
//   • Members who missed show as dim "missed it" slots; while the
//     5-minute window is still open they show as "still has time".
//   • A "wall closes in mm:ss" timer + draining bar sit at the top.
//   • Tapping a capture opens it full-screen (photo or looping clip).
//

import SwiftUI
import UIKit

struct GoldenHourWallView: View {
    let moment: GoldenHourMoment

    @Environment(GoldenHourService.self) private var service
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(\.dismiss) private var dismiss

    @State private var fullScreenPost: GoldenHourPost?
    @State private var reportTarget: ReportTarget?
    @State private var blockCandidate: RemoteProfile?

    private var myUserId: String { auth.user?.id ?? "" }
    private var circle: GoldenCircle? { service.circle(moment.circleId) }
    private var iPosted: Bool {
        service.post(circleId: moment.circleId, day: moment.day, userId: myUserId) != nil
    }

    var body: some View {
        ZStack {
            GoldenTheme.ink.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                wall(now: context.date)
            }

            if !iPosted {
                missedOverlay
            }
        }
        .onAppear {
            service.cancelClosingReminder(circleId: moment.circleId, day: moment.day)
        }
        .fullScreenCover(item: $fullScreenPost) { post in
            GoldenHourMediaViewer(post: post)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName
            )
        }
        .confirmationDialog(
            "Block \(blockCandidate?.displayName ?? "this member")?",
            isPresented: Binding(
                get: { blockCandidate != nil },
                set: { if !$0 { blockCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { candidate in
            Button("Block \(candidate.displayName)", role: .destructive) {
                Task { await moderation.block(candidate.id, myUserId: myUserId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They won't be able to message you or send requests, and you won't see each other's shared moments.")
        }
    }

    // MARK: - Wall

    @ViewBuilder
    private func wall(now: Date) -> some View {
        let phase = moment.phase(at: now)
        let posts = service.posts(circleId: moment.circleId, day: moment.day)
            .filter { !moderation.isBlocked($0.userId) && !moderation.isGoldenHourHidden($0.id) }
        let postedIds = Set(posts.map(\.userId))
        let waiting = (circle?.members ?? []).filter { !postedIds.contains($0.id) && !moderation.isBlocked($0.id) }

        VStack(spacing: 0) {
            header

            // The draining hour.
            VStack(spacing: 7) {
                GoldenDrainBar(
                    remaining: max(0, moment.wallClosesAt.timeIntervalSince(now)) / GoldenHourSchedule.viewingWindow
                )
                HStack {
                    if phase == .live {
                        HStack(spacing: 5) {
                            Circle().fill(GoldenTheme.gold).frame(width: 6, height: 6)
                            Text("Capturing — \(GoldenHourSchedule.countdownString(until: moment.captureClosesAt, from: now)) left")
                                .font(.sans(11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(GoldenTheme.gold)
                        }
                    }
                    Spacer()
                    Text("WALL CLOSES IN \(GoldenHourSchedule.wallCountdownString(until: moment.wallClosesAt, from: now))")
                        .font(.sans(11, weight: .bold).monospacedDigit())
                        .tracking(1.2)
                        .foregroundStyle(GoldenTheme.cream.opacity(0.75))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(.vertical, showsIndicators: false) {
                if posts.isEmpty {
                    // The wall before first light — name the moment so an
                    // empty grid never reads as something broken.
                    VStack(spacing: 5) {
                        Text("No light on the wall yet")
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(GoldenTheme.cream)
                        Text("The first capture opens it.")
                            .font(.sans(12.5, weight: .regular))
                            .foregroundStyle(GoldenTheme.cream.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 46)
                    .padding(.bottom, 8)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(posts) { post in
                        GoldenPostTile(
                            post: post,
                            profile: circle?.profile(post.userId),
                            isMine: post.userId == myUserId,
                            isBlurred: !iPosted,
                            onTap: {
                                guard iPosted, post.mediaPath != nil else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                fullScreenPost = post
                            },
                            onReport: {
                                reportTarget = ReportTarget(
                                    reportedUserId: post.userId,
                                    messageId: nil,
                                    subjectName: circle?.profile(post.userId)?.displayName ?? "this member"
                                )
                            },
                            onHide: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                moderation.hideGoldenHourPost(post.id)
                            },
                            onBlock: {
                                blockCandidate = circle?.profile(post.userId)
                            }
                        )
                    }
                    ForEach(waiting) { member in
                        GoldenEmptySlot(
                            profile: member,
                            stillHasTime: phase == .live,
                            captureClosesAt: moment.captureClosesAt,
                            now: now
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                footer(posts: posts)
                    .padding(.top, 22)
                    .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOLDEN HOUR")
                    .font(.sans(10, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(GoldenTheme.gold)
                Text(circle?.name ?? "Your circle")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(GoldenTheme.cream)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoldenTheme.cream)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(GoldenTheme.inkRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the wall")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func footer(posts: [GoldenHourPost]) -> some View {
        let attendance = service.attendance(circleId: moment.circleId, day: moment.day)
        let streak = service.streak(circleId: moment.circleId, userId: myUserId)
        VStack(spacing: 10) {
            Text(attendance.made == 1 ? "1 made it" : "\(attendance.made) made it")
                .font(.serif(16, weight: .medium))
                .foregroundStyle(GoldenTheme.cream.opacity(0.85))
            if streak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Your streak: \(streak)")
                        .font(.sans(12, weight: .semibold))
                }
                .foregroundStyle(GoldenTheme.gold)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(GoldenTheme.gold.opacity(0.14)))
            }
            Text("Everything here is deleted when the timer ends. No archive, no replay.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(GoldenTheme.cream.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Missed overlay

    /// Shown only when the capture window has closed and the user never
    /// posted: the wall is there, ticking, but stays blurred forever.
    private var missedOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(GoldenTheme.gold)
            Text("Today's Golden Hour has passed")
                .font(.serif(21, weight: .medium))
                .foregroundStyle(GoldenTheme.cream)
            Text("The wall stays blurred this time — it belongs to the ones who caught the light. Tomorrow's hour is yours.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(GoldenTheme.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(26)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(GoldenTheme.inkRaised.opacity(0.96))
                .shadow(color: Color.black.opacity(0.4), radius: 22, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(GoldenTheme.gold.opacity(0.35), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Post tile

private struct GoldenPostTile: View {
    let post: GoldenHourPost
    let profile: RemoteProfile?
    let isMine: Bool
    let isBlurred: Bool
    let onTap: () -> Void
    var onReport: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil

    @Environment(GoldenHourService.self) private var service
    @State private var signedURL: URL?

    var body: some View {
        Button(action: onTap) {
            Color(GoldenTheme.inkRaised == Color.clear ? .black : .black)
                .frame(height: 200)
                .overlay { media.allowsHitTesting(false) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) { caption }
                .overlay(alignment: .topTrailing) { spareBadge }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isMine ? GoldenTheme.gold.opacity(0.7) : GoldenTheme.gold.opacity(0.18),
                            lineWidth: isMine ? 1.4 : 0.8
                        )
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isMine {
                Button {
                    onReport?()
                } label: {
                    Label("Report", systemImage: "flag")
                }
                Button {
                    onHide?()
                } label: {
                    Label("Hide this capture", systemImage: "eye.slash")
                }
                Button(role: .destructive) {
                    onBlock?()
                } label: {
                    Label("Block \(profile?.displayName ?? "member")", systemImage: "hand.raised")
                }
            }
        }
        .task(id: post.mediaPath) {
            guard let path = post.mediaPath, signedURL == nil, post.mediaKind == .photo else { return }
            signedURL = await service.signedURL(forMediaPath: path)
        }
        .accessibilityLabel("\(profile?.displayName ?? "A member")'s Golden Hour capture")
        .accessibilityHint(isMine ? "" : "Touch and hold for report, hide, and block options")
    }

    @ViewBuilder
    private var media: some View {
        ZStack {
            GoldenTheme.inkRaised

            if post.mediaKind == .photo {
                if let path = post.mediaPath,
                   let cached = ProofMediaCache.cachedFileURL(forMediaPath: path, kind: .photo),
                   let image = UIImage(contentsOfFile: cached.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    CachedImage(url: signedURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView().tint(GoldenTheme.gold)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(GoldenTheme.gold)
                    if let duration = post.mediaDuration {
                        Text(String(format: "0:%02d", Int(duration.rounded())))
                            .font(.sans(12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(GoldenTheme.cream.opacity(0.8))
                    }
                }
            }
        }
        .blur(radius: isBlurred ? 22 : 0)
        .overlay {
            if isBlurred {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GoldenTheme.cream.opacity(0.85))
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 6) {
            if let profile {
                RemoteAvatarView(profile: profile, size: 20)
            }
            Text(isMine ? "You" : (profile?.displayName ?? "Member"))
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(GoldenTheme.cream)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(8)
    }

    @ViewBuilder
    private var spareBadge: some View {
        if let spare = post.secondsToSpare {
            Text(String(format: "%d:%02d to spare", spare / 60, spare % 60))
                .font(.sans(9, weight: .bold).monospacedDigit())
                .foregroundStyle(GoldenTheme.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(GoldenTheme.gold))
                .padding(8)
        }
    }
}

// MARK: - Empty slot

private struct GoldenEmptySlot: View {
    let profile: RemoteProfile
    let stillHasTime: Bool
    let captureClosesAt: Date
    let now: Date

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                GoldenTheme.gold.opacity(stillHasTime ? 0.4 : 0.14),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
            .frame(height: 200)
            .overlay {
                VStack(spacing: 8) {
                    RemoteAvatarView(profile: profile, size: 38)
                        .opacity(stillHasTime ? 1 : 0.45)
                        .grayscale(stillHasTime ? 0 : 1)
                    Text(profile.displayName)
                        .font(.sans(11, weight: .semibold))
                        .foregroundStyle(GoldenTheme.cream.opacity(stillHasTime ? 0.85 : 0.45))
                        .lineLimit(1)
                    if stillHasTime {
                        Text("still has \(GoldenHourSchedule.countdownString(until: captureClosesAt, from: now))")
                            .font(.sans(10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(GoldenTheme.gold)
                    } else {
                        Text("quiet today")
                            .font(.sans(10, weight: .semibold))
                            .foregroundStyle(GoldenTheme.cream.opacity(0.4))
                    }
                }
                .padding(.horizontal, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                stillHasTime
                    ? "\(profile.displayName) still has time to post"
                    : "\(profile.displayName) was quiet today"
            )
    }
}

// MARK: - Full-screen viewer

private struct GoldenHourMediaViewer: View {
    let post: GoldenHourPost

    @Environment(GoldenHourService.self) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var resolvedURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = resolvedURL {
                if post.mediaKind == .video {
                    GoldenLoopingPlayer(url: url)
                        .ignoresSafeArea()
                } else if let image = localImage(url) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    CachedImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(GoldenTheme.gold)
                    }
                    .ignoresSafeArea()
                }
            } else {
                ProgressView().tint(GoldenTheme.gold)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .task {
            guard let path = post.mediaPath else { return }
            if let cached = ProofMediaCache.cachedFileURL(forMediaPath: path, kind: post.mediaKind) {
                resolvedURL = cached
                return
            }
            guard let signed = await service.signedURL(forMediaPath: path) else { return }
            if post.mediaKind == .video {
                resolvedURL = await ProofMediaCache.download(from: signed, forMediaPath: path, kind: .video) ?? signed
            } else {
                resolvedURL = signed
            }
        }
    }

    private func localImage(_ url: URL) -> UIImage? {
        guard url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
