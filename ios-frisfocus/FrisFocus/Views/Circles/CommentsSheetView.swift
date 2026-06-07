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
//  edit/delete. C7a's contract is short messages within a private
//  context — this view enforces that by simply not surfacing any
//  other affordance.
//

import SwiftUI
import UIKit

struct CommentsSheetView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let postId: UUID
    let headline: String

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool
    /// The comment author whose profile is open, if any.
    @State private var profileTarget: ProfileTarget?

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

        return Button {
            guard let target else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            profileTarget = target
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(isMine ? Theme.textPrimary : Color(hex: colorHex))
                    Text(comment.fromInitials)
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 28, height: 28)

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
