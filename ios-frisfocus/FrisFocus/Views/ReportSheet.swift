//
//  ReportSheet.swift
//  FrisFocus
//
//  A calm reporting flow reused anywhere a person or a piece of
//  content can be flagged. Pick a reason, optionally add a note, and
//  submit — the report is filed for review. Pass a `messageId` to
//  report a proof, a `storyPostId` / `storyCommentId` to report story
//  content, a `goldenHourPostId` to report a Golden Hour capture, a
//  `circleId` to report a circle itself, or just a `reportedUserId` to
//  report the person.
//
//  `.memberSafetyActions(report:member:)` at the bottom is the shared
//  presentation for surfaces that list people who may be strangers (a
//  circle's members, a public listing): one modifier brings the report
//  sheet and the report-or-block choice, so each list only has to say
//  who was picked.
//

import SwiftUI
import UIKit

/// A pending report target, wrapped so it can drive a `.sheet(item:)`
/// from any surface with a "..." menu.
struct ReportTarget: Identifiable {
    let id = UUID()
    let reportedUserId: String?
    let messageId: UUID?
    let subjectName: String
    var storyPostId: UUID? = nil
    var storyCommentId: UUID? = nil
    /// Optional content snapshot (e.g. the exact cheer text) carried
    /// into the report so review has the content in hand.
    var contextDetails: String? = nil
    /// The Golden Hour capture being reported. The capture deletes
    /// itself within the hour, so without this a report could not say
    /// which one it meant.
    var goldenHourPostId: UUID? = nil
    /// The circle being reported — its name, description, events, or
    /// shared tasks — rather than any one member.
    var circleId: UUID? = nil
}

struct ReportSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(\.dismiss) private var dismiss

    let reportedUserId: String?
    let messageId: UUID?
    let subjectName: String
    var storyPostId: UUID? = nil
    var storyCommentId: UUID? = nil
    /// Optional content snapshot appended to whatever the reporter
    /// writes — used by surfaces (like cheers) whose content has no
    /// dedicated column on the reports table.
    var contextDetails: String? = nil
    var goldenHourPostId: UUID? = nil
    var circleId: UUID? = nil

    @State private var reason: String?
    @State private var details: String = ""
    @State private var isSubmitting: Bool = false

    private let reasons = [
        "Spam",
        "Harassment or bullying",
        "Inappropriate or explicit content",
        "Impersonation",
        "Something else",
    ]

    private var subtitle: String {
        if circleId != nil { return "Report the circle \(subjectName)" }
        if goldenHourPostId != nil { return "Report this capture from \(subjectName)" }
        if storyCommentId != nil { return "Report this comment from \(subjectName)" }
        if storyPostId != nil { return "Report this story from \(subjectName)" }
        return messageId != nil ? "Report this proof from \(subjectName)" : "Report \(subjectName)"
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        reasonsSection
                        detailsSection
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                submitButton
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("REPORT")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text(subtitle)
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT'S WRONG?")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            ForEach(reasons, id: \.self) { option in
                reasonRow(option)
            }
        }
    }

    private func reasonRow(_ option: String) -> some View {
        let isSelected = reason == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reason = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.3))
                Text(option)
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.textPrimary.opacity(0.3) : Theme.textPrimary.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING TO ADD? (OPTIONAL)")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            TextField("A short note for whoever reviews this…", text: $details, axis: .vertical)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.paperCream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(Theme.textCream)
                } else {
                    Text("Submit report")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(reason == nil ? Theme.textPrimary.opacity(0.35) : Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(reason == nil || isSubmitting)
    }

    private func submit() async {
        guard let reason, let myId = auth.user?.id else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = [contextDetails, note.isEmpty ? nil : note]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        let ok = await moderation.report(
            reportedUserId: reportedUserId,
            messageId: messageId,
            storyPostId: storyPostId,
            storyCommentId: storyCommentId,
            goldenHourPostId: goldenHourPostId,
            circleId: circleId,
            reason: reason,
            details: merged,
            myUserId: myId
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

// MARK: - Report + block for people lists

extension View {
    /// The safety actions for a surface that lists people who may be
    /// strangers — a circle's members, a public listing.
    ///
    /// Set `member` to offer "Report" and "Block" for that person; set
    /// `report` to open the report sheet directly (for a circle, or any
    /// target that isn't a person). One modifier per surface, so a
    /// member list only has to say who was picked.
    func memberSafetyActions(
        report: Binding<ReportTarget?>,
        member: Binding<RemoteProfile?>
    ) -> some View {
        modifier(MemberSafetyActionsModifier(reportTarget: report, member: member))
    }
}

private struct MemberSafetyActionsModifier: ViewModifier {
    @Binding var reportTarget: ReportTarget?
    @Binding var member: RemoteProfile?
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation

    private var isChoosing: Binding<Bool> {
        Binding(
            get: { member != nil },
            set: { newValue in if !newValue { member = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $reportTarget) { target in
                ReportSheet(
                    reportedUserId: target.reportedUserId,
                    messageId: target.messageId,
                    subjectName: target.subjectName,
                    storyPostId: target.storyPostId,
                    storyCommentId: target.storyCommentId,
                    contextDetails: target.contextDetails,
                    goldenHourPostId: target.goldenHourPostId,
                    circleId: target.circleId
                )
            }
            .confirmationDialog(
                member?.displayName ?? "This member",
                isPresented: isChoosing,
                titleVisibility: .visible,
                presenting: member
            ) { picked in
                Button("Report \(picked.displayName)") {
                    reportTarget = ReportTarget(
                        reportedUserId: picked.id,
                        messageId: nil,
                        subjectName: picked.displayName
                    )
                }
                // The dialog is the confirmation: one deliberate,
                // clearly-labelled tap, with what it does spelled out
                // underneath.
                Button("Block \(picked.displayName)", role: .destructive) {
                    guard let myId = auth.user?.id else { return }
                    Task { await moderation.block(picked.id, myUserId: myId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Reports are reviewed by a person. Blocking stops messages and requests between you, and hides each other's shared moments.")
            }
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            ReportSheet(reportedUserId: "usr_x", messageId: nil, subjectName: "Alex")
                .environment(AuthManager())
                .environment(ModerationService())
        }
}
