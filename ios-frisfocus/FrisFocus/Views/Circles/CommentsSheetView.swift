//
//  CommentsSheetView.swift
//  FrisFocus
//
//  The full-thread sheet for a single story post. Reached from the
//  friend detail gesture bar's `Comment` button, and from any
//  "View all N comments" affordance once more surfaces are wired.
//  Lists every comment on the post and lets the current user append
//  a new one through `Store.addComment(postId:text:)`.
//
//  Intentionally minimal: no replies, no comment reactions, no
//  editing. C7a's contract is short messages within a private
//  context — this view enforces that by simply not surfacing any
//  other affordance. Every comment carries a quiet "…" menu: report
//  or block on someone else's, and removal wherever the person
//  looking is entitled to it — their own words anywhere, anyone's
//  words on a post of their own. Reporting and blocking never take
//  the text down, so without this an unwanted comment would sit on
//  your own story forever.
//

import SwiftUI
import UIKit

struct CommentsSheetView: View {
    @Environment(Store.self) private var store
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(ModerationService.self) private var moderation
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let postId: UUID
    let headline: String

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    /// The comment author whose profile is open, if any.
    @State private var profileTarget: ProfileTarget?
    /// The report flow for a specific comment, when open.
    @State private var reportTarget: ReportTarget?
    /// The comment whose author is pending a block confirmation.
    @State private var blockCandidate: Comment?
    /// The comment pending a delete confirmation — the user's own, or
    /// someone else's left on the user's own post.
    @State private var deleteCandidate: Comment?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Divider().opacity(0.4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let rows = store.comments(for: postId)
                        .filter { !isBlockedAuthor($0.fromFriendId) }
                    if rows.isEmpty {
                        Text("No comments yet — be the first.")
                            .font(.serifItalic(14, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(rows) { comment in
                            commentRow(comment)
                        }
                    }
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.vertical, 16)
            }

            Divider().opacity(0.4)

            composer
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.vertical, 12)
        }
        .background(Theme.warmWheat)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .profileDestination($profileTarget, store: store)
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName,
                storyPostId: target.storyPostId,
                storyCommentId: target.storyCommentId
            )
        }
        .confirmationDialog(
            "Block \(blockCandidate?.fromName ?? "this person")?",
            isPresented: Binding(
                get: { blockCandidate != nil },
                set: { if !$0 { blockCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                if let candidate = blockCandidate {
                    blockAuthor(of: candidate)
                }
                blockCandidate = nil
            }
            Button("Cancel", role: .cancel) { blockCandidate = nil }
        } message: {
            Text("They won't be able to message you or see your days, and you won't see theirs.")
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteCandidateIsMine ? "Delete" : "Remove", role: .destructive) {
                if let candidate = deleteCandidate {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    store.deleteComment(candidate.id)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text(deleteDialogMessage)
        }
    }

    /// The two delete cases share one dialog but not one voice: you
    /// delete your own words, you remove someone else's from your post.
    private var deleteCandidateIsMine: Bool {
        deleteCandidate?.fromFriendId == store.currentUserId
    }

    private var deleteDialogTitle: String {
        deleteCandidateIsMine ? "Delete your comment?" : "Remove this comment?"
    }

    private var deleteDialogMessage: String {
        if deleteCandidateIsMine {
            return "This will remove your comment from this post. Nobody will see it anymore."
        }
        let name = deleteCandidate?.fromName ?? "This person"
        return "This will remove \(name)'s comment from your post. Nobody will see it anymore."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMENTS")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Text(headline)
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentRow(_ comment: Comment) -> some View {
        let isMine = comment.fromFriendId == store.currentUserId
        let friend = store.friend(by: comment.fromFriendId)
        let colorHex = friend?.accentColorHex ?? "2C2C2A"
        let target: ProfileTarget? = isMine ? .me : friend.map { ProfileTarget.friend($0) }

        return HStack(alignment: .top, spacing: 6) {
            Button {
                guard let target else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                profileTarget = target
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    FriendAvatarView(
                        friend: isMine ? nil : friend,
                        size: 28,
                        fallbackInitials: comment.fromInitials,
                        fallbackColor: isMine ? Theme.textPrimary : Color(hex: colorHex)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        (
                            Text(comment.fromName)
                                .font(.sans(13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            + Text("  ")
                            + Text(comment.text)
                                .font(.sans(13, weight: .regular))
                                .foregroundColor(Theme.textPrimary.opacity(0.85))
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
            .accessibilityLabel(
                isMine
                    ? "Your comment: \(comment.text)"
                    : (target != nil ? "\(comment.fromName), tap to open profile. \(comment.text)" : "\(comment.fromName): \(comment.text)")
            )

            // One menu for every row now, rather than only on other
            // people's comments. A swipe would be the other obvious
            // home for "delete mine", but these rows live in a
            // LazyVStack, not a List, so `.swipeActions` isn't
            // available — and keeping every comment's affordance in the
            // same place means the gesture never has to be discovered
            // twice. The menu is never empty: it always carries either
            // Report or a removal the viewer is entitled to.
            Menu {
                if !isMine {
                    Button {
                        reportTarget = ReportTarget(
                            reportedUserId: socialSync.remoteId(forLocal: comment.fromFriendId),
                            messageId: nil,
                            subjectName: comment.fromName,
                            storyPostId: postId,
                            storyCommentId: comment.id
                        )
                    } label: {
                        Label("Report comment", systemImage: "flag")
                    }
                    if socialSync.remoteId(forLocal: comment.fromFriendId) != nil {
                        Button(role: .destructive) {
                            blockCandidate = comment
                        } label: {
                            Label("Block \(comment.fromName)", systemImage: "hand.raised")
                        }
                    }
                }
                if store.canDeleteComment(comment) {
                    Button(role: .destructive) {
                        deleteCandidate = comment
                    } label: {
                        Label(isMine ? "Delete comment" : "Remove comment", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(
                isMine ? "Options for your comment" : "Options for \(comment.fromName)'s comment"
            )
        }
    }

    /// Whether a comment author has been blocked — their comments
    /// vanish immediately, before any server refresh.
    private func isBlockedAuthor(_ localId: UUID) -> Bool {
        guard localId != store.currentUserId,
              let remote = socialSync.remoteId(forLocal: localId) else { return false }
        return moderation.isBlocked(remote)
    }

    /// Block a comment's author and refresh the mirrors so their
    /// presence fades from every surface.
    private func blockAuthor(of comment: Comment) {
        guard let remote = socialSync.remoteId(forLocal: comment.fromFriendId),
              let myId = auth.user?.id else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            await moderation.block(remote, myUserId: myId)
            await socialSync.refreshFriends()
            await socialSync.refreshStories()
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .focused($inputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                )

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(canSend ? Theme.textCream : Theme.textCream.opacity(0.55))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(canSend ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Post comment")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.addComment(postId: postId, text: draft)
        draft = ""
    }
}
