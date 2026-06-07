//
//  CircleSettingsSheet.swift
//  FrisFocus
//
//  Settings for a circle: governance toggle (owner-only), member
//  roster with role controls, shared-task management (gated by role
//  and the governance toggle), and the pending review queue for
//  owner/admin.
//
//  Default friend circles never see the governance UI light up —
//  the toggle is off, the request queue is empty, and the task
//  rows just apply edits directly for whoever has permission.
//

import SwiftUI
import UIKit

struct CircleSettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let circleId: UUID

    @State private var showAddTaskForm: Bool = false
    @State private var editingTaskId: UUID?
    @State private var draftTitle: String = ""
    @State private var transientBanner: String?
    @State private var bannerTask: Task<Void, Never>?

    private var circle: FFCircle? {
        store.circles.first { $0.id == circleId }
    }

    var body: some View {
        NavigationStack {
            if let circle {
                content(for: circle)
                    .navigationTitle("Circle settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .font(.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            } else {
                Text("Circle unavailable.")
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Body

    @ViewBuilder
    private func content(for circle: FFCircle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let banner = transientBanner {
                    bannerView(text: banner)
                }

                if store.isOwner(of: circle) {
                    governanceSection(for: circle)
                }

                if store.canManageTasks(in: circle) {
                    pendingRequestsSection(for: circle)
                }

                sharedTasksSection(for: circle)

                membersSection(for: circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 48)
        }
        .background(Theme.warmWheat)
    }

    // MARK: - Governance

    private func governanceSection(for circle: FFCircle) -> some View {
        sectionContainer(title: "Governance", eyebrow: "OWNER ONLY") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: governanceBinding(for: circle)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Members can propose tasks")
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(circle.membersCanProposeTasks
                            ? "Member changes queue for your review"
                            : "Only owner & admins can change tasks")
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                }
                .tint(Theme.alertGreen)
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func governanceBinding(for circle: FFCircle) -> Binding<Bool> {
        Binding(
            get: { circle.membersCanProposeTasks },
            set: { newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.setMembersCanProposeTasks(newValue, in: circle.id)
            }
        )
    }

    // MARK: - Pending requests

    @ViewBuilder
    private func pendingRequestsSection(for circle: FFCircle) -> some View {
        let pending = store.pendingRequests(forCircleId: circle.id)
        if !pending.isEmpty {
            sectionContainer(
                title: "Pending requests",
                eyebrow: "\(pending.count) AWAITING REVIEW"
            ) {
                VStack(spacing: 10) {
                    ForEach(pending) { request in
                        pendingRequestRow(request, in: circle)
                    }
                }
            }
        }
    }

    private func pendingRequestRow(_ request: CircleTaskRequest, in circle: FFCircle) -> some View {
        let requesterName: String = {
            if request.requesterId == store.currentUserId { return "You" }
            return store.friend(by: request.requesterId)?.displayName ?? "A member"
        }()

        let actionLabel: String = {
            switch request.type {
            case .add: return "wants to add"
            case .edit: return "wants to edit"
            case .delete: return "wants to remove"
            }
        }()

        let targetTitle: String = {
            if request.type == .edit,
               let id = request.existingTaskId,
               let existing = circle.tasks.first(where: { $0.id == id }) {
                return "\u{201C}\(existing.title)\u{201D} \u{2192} \u{201C}\(request.taskData.title)\u{201D}"
            }
            return "\u{201C}\(request.taskData.title)\u{201D}"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(requesterName) \(actionLabel)")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Text(targetTitle)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.rejectRequest(request.id)
                } label: {
                    Text("Reject")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.approveRequest(request.id)
                } label: {
                    Text("Approve")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.alertGreen)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Shared tasks

    @ViewBuilder
    private func sharedTasksSection(for circle: FFCircle) -> some View {
        let role = store.myRole(in: circle)
        let canAdd = store.canManageTasks(in: circle) || circle.membersCanProposeTasks

        sectionContainer(
            title: "Shared tasks",
            eyebrow: role == .owner ? "OWNER" : (role == .admin ? "ADMIN" : "MEMBER")
        ) {
            VStack(spacing: 10) {
                if circle.tasks.isEmpty && !showAddTaskForm {
                    Text("No shared tasks yet.")
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }

                ForEach(circle.tasks) { task in
                    sharedTaskRow(task, in: circle)
                }

                if showAddTaskForm {
                    addOrEditForm(for: circle)
                } else if canAdd {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editingTaskId = nil
                        draftTitle = ""
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAddTaskForm = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.sans(15, weight: .semibold))
                            Text(circle.requiresRequest(forUserId: store.currentUserId)
                                ? "Propose a task"
                                : "Add a task")
                                .font(.sans(14, weight: .medium))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18),
                                              style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sharedTaskRow(_ task: CircleTask, in circle: FFCircle) -> some View {
        let mayEdit = store.canManageTasks(in: circle) || circle.membersCanProposeTasks
        let needsRequest = circle.requiresRequest(forUserId: store.currentUserId)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(task.title)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if mayEdit {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editingTaskId = task.id
                    draftTitle = task.title
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAddTaskForm = true
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let applied = store.deleteOrProposeCircleTask(
                        circleId: circle.id,
                        existingTaskId: task.id
                    )
                    showBanner(applied
                        ? "Task removed."
                        : "Removal queued for review.")
                } label: {
                    Image(systemName: "trash")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(needsRequest
                            ? Theme.textPrimary.opacity(0.45)
                            : Theme.alertRed.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private func addOrEditForm(for circle: FFCircle) -> some View {
        let isEditing = editingTaskId != nil
        let needsRequest = circle.requiresRequest(forUserId: store.currentUserId)
        let saveLabel: String = {
            if needsRequest {
                return isEditing ? "Propose edit" : "Propose add"
            }
            return isEditing ? "Save" : "Add"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            TextField("Task name", text: $draftTitle)
                .font(.sans(15, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                )

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    closeForm()
                } label: {
                    Text("Cancel")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    submitForm(in: circle)
                } label: {
                    Text(saveLabel)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Theme.textPrimary.opacity(0.3)
                                    : Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func submitForm(in circle: FFCircle) {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let applied: Bool
        if let id = editingTaskId,
           let existing = circle.tasks.first(where: { $0.id == id }) {
            var draft = CircleTaskDraft(from: existing)
            draft.title = trimmed
            applied = store.editOrProposeCircleTask(
                circleId: circle.id,
                existingTaskId: id,
                draft: draft
            )
            showBanner(applied ? "Task updated." : "Edit queued for review.")
        } else {
            let draft = CircleTaskDraft(title: trimmed)
            applied = store.addOrProposeCircleTask(circleId: circle.id, draft: draft)
            showBanner(applied ? "Task added." : "Task queued for review.")
        }
        closeForm()
    }

    private func closeForm() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showAddTaskForm = false
        }
        editingTaskId = nil
        draftTitle = ""
    }

    // MARK: - Members

    private func membersSection(for circle: FFCircle) -> some View {
        sectionContainer(
            title: "Members",
            eyebrow: "\(circle.memberIds.count) MEMBER\(circle.memberIds.count == 1 ? "" : "S")"
        ) {
            VStack(spacing: 10) {
                ForEach(circle.memberIds, id: \.self) { memberId in
                    memberRow(memberId: memberId, in: circle)
                }
            }
        }
    }

    private func memberRow(memberId: UUID, in circle: FFCircle) -> some View {
        let role = circle.role(forUserId: memberId)
        let isMe = memberId == store.currentUserId
        let displayName: String = {
            if isMe { return "You" }
            return store.friend(by: memberId)?.displayName ?? "Member"
        }()
        let initials: String = {
            if isMe { return "J" }
            return store.friend(by: memberId)?.initials ?? "?"
        }()
        let accent: Color = {
            if isMe { return Theme.textPrimary }
            if let f = store.friend(by: memberId) {
                return Color(hex: f.accentColorHex)
            }
            return Theme.textTertiary
        }()

        let viewerIsOwner = store.isOwner(of: circle)
        let viewerCanManage = store.canManageTasks(in: circle)

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent)
                Text(initials)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                roleChip(role)
            }

            Spacer(minLength: 8)

            if !isMe {
                Menu {
                    if viewerIsOwner {
                        switch role {
                        case .owner:
                            EmptyView()
                        case .admin:
                            Button("Demote to member") {
                                store.demoteFromAdmin(userId: memberId, in: circle.id)
                            }
                        case .member:
                            Button("Promote to admin") {
                                store.promoteToAdmin(userId: memberId, in: circle.id)
                            }
                        }
                        if role != .owner {
                            Button("Transfer ownership", role: .destructive) {
                                store.transferOwnership(to: memberId, in: circle.id)
                            }
                        }
                    }
                    if viewerCanManage, role != .owner {
                        // Admins can only remove plain members, not other admins.
                        let canRemove = viewerIsOwner || role == .member
                        if canRemove {
                            Button("Remove from circle", role: .destructive) {
                                store.removeMember(userId: memberId, from: circle.id)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .opacity(viewerIsOwner || (viewerCanManage && role == .member) ? 1 : 0.3)
                .disabled(!(viewerIsOwner || (viewerCanManage && role == .member)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private func roleChip(_ role: CircleRole) -> some View {
        let label: String = {
            switch role {
            case .owner: return "OWNER"
            case .admin: return "ADMIN"
            case .member: return "MEMBER"
            }
        }()
        let color: Color = {
            switch role {
            case .owner: return Theme.sunWarm
            case .admin: return Theme.alertGreen
            case .member: return Theme.textPrimary.opacity(0.5)
            }
        }()
        return Text(label)
            .font(.sans(9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }

    // MARK: - Chrome

    @ViewBuilder
    private func sectionContainer<C: View>(
        title: String,
        eyebrow: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(eyebrow)
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            content()
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func bannerView(text: String) -> some View {
        Text(text)
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.92))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func showBanner(_ text: String) {
        bannerTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            transientBanner = text
        }
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2.0))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transientBanner = nil
                }
            }
        }
    }
}

#Preview {
    let store = Store()
    return Group {
        if let parallel = store.circles.first(where: { $0.type == .parallel }) {
            CircleSettingsSheet(circleId: parallel.id)
        }
    }
    .environment(store)
}
