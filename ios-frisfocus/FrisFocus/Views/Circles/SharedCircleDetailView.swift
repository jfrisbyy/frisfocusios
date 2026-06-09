//
//  SharedCircleDetailView.swift
//  FrisFocus
//
//  The detail page for one real, Supabase-backed shared circle. Pushed
//  from `SharedCirclesListView`, it reads its circle live from the same
//  `CircleGraphService` instance — so a friend's check-off or
//  contribution (picked up by the list's poll) lands here without a
//  manual refresh.
//
//  Two bodies share one night-sky frame:
//   • parallel   — your own tappable checklist for today, plus a
//                  per-member progress board with a today / overall
//                  toggle.
//   • collective — an animated bar toward a shared number, an inline
//                  "log your progress" card, and each member's total.
//
//  Owner / admins can add tasks; the owner can delete the circle and any
//  member can leave. RLS enforces all of this server-side — the role
//  checks here only shape the UI.
//

import SwiftUI
import UIKit

struct SharedCircleDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let service: CircleGraphService
    let circleId: UUID
    let myUserId: String

    @State private var scope: CircleScope = .today
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var contributionText = ""
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showInvite = false
    @State private var showOurStory = false
    @State private var showNumberForm = false
    @State private var numberUnit = ""
    @State private var numberTarget = ""
    @State private var friendService = FriendGraphService()
    @FocusState private var contributionFocused: Bool

    private var circle: SharedCircle? { service.circles.first { $0.id == circleId } }
    private var isOwner: Bool { circle?.ownerId == myUserId }
    private var canManage: Bool { circle?.canManageTasks(myUserId) ?? false }

    var body: some View {
        @Bindable var service = service

        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            if let circle {
                detail(circle)
            } else {
                missing
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            service.startRealtime(myUserId: myUserId)
            await friendService.load(myUserId: myUserId)
        }
        .onChange(of: service.circles.map(\.id)) { _, ids in
            if !ids.contains(circleId) { dismiss() }
        }
        .alert("Add a task", isPresented: $showAddTask) {
            TextField("e.g. Run a mile", text: $newTaskTitle)
            Button("Add") { commitNewTask() }
            Button("Cancel", role: .cancel) { newTaskTitle = "" }
        } message: {
            Text("Everyone in the circle will see this task.")
        }
        .confirmationDialog("Delete this circle?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete circle", role: .destructive) {
                Task { await service.deleteCircle(circleId); dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the circle and everyone's progress. It can't be undone.")
        }
        .confirmationDialog("Leave this circle?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave circle", role: .destructive) {
                Task { await service.leaveCircle(circleId, myUserId: myUserId); dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stop seeing this circle. A member can add you back later.")
        }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
        .sheet(isPresented: $showOurStory) {
            if let circle {
                SharedCircleStoryView(circle: circle)
            }
        }
        .sheet(isPresented: $showInvite) {
            if let circle {
                InviteToCircleSheet(
                    circleName: circle.name,
                    friends: friendService.friends,
                    existingMemberIds: Set(circle.members.map(\.id)),
                    onInvite: { ids in
                        Task { await service.inviteMembers(circleId: circleId, inviteeIds: ids, myUserId: myUserId) }
                    }
                )
            }
        }
    }

    // MARK: - Scaffold

    private func detail(_ circle: SharedCircle) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero(circle)

                VStack(alignment: .leading, spacing: 26) {
                    switch circle.kind {
                    case .witness:
                        witnessBody(circle)
                    case .parallel:
                        parallelBody(circle)
                    case .collective:
                        collectiveBody(circle)
                    case .hybrid:
                        parallelBody(circle)
                        hybridDivider
                        collectiveBody(circle)
                    }
                    if canManage {
                        sharedGoalsSection(circle)
                    }
                    membershipFooter(circle)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 48)
            }
        }
        .background(Theme.warmWheat)
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await service.load(myUserId: myUserId) }
    }

    private var missing: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("This circle is no longer available")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Button {
                dismiss()
            } label: {
                Text("Back to circles")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Theme.textPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: - Hero

    private func hero(_ circle: SharedCircle) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: circle.kind.heroColors, startPoint: .top, endPoint: .bottom)

            starsLayer.allowsHitTesting(false)

            heroTopBar
                .padding(.top, 56)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow(circle))
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.72))

                Text(circle.name)
                    .font(.serif(25, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    RemoteCircleAvatarStack(
                        members: circle.members,
                        myUserId: myUserId,
                        maxVisible: 4,
                        diameter: 26,
                        onDark: true
                    )
                    Text(membershipCaption(circle))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.bottom, 18)
        }
        .frame(height: 220)
        .clipped()
    }

    private var heroTopBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.sans(15, weight: .medium))
                    Text("Circles")
                        .font(.sans(14, weight: .regular))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Circles")

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showOurStory = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed").font(.sans(10, weight: .semibold))
                    Text("Our story").font(.sans(12, weight: .medium))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(Theme.textCream.opacity(0.16)))
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.textCream.opacity(0.28), lineWidth: 0.5))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Our story")
        }
    }

    @ViewBuilder
    private var starsLayer: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                star(at: CGPoint(x: w * 0.08, y: h * 0.22), size: 1.4, opacity: 0.55)
                star(at: CGPoint(x: w * 0.22, y: h * 0.10), size: 1.0, opacity: 0.40)
                star(at: CGPoint(x: w * 0.32, y: h * 0.30), size: 1.8, opacity: 0.65)
                star(at: CGPoint(x: w * 0.48, y: h * 0.16), size: 1.2, opacity: 0.50)
                star(at: CGPoint(x: w * 0.60, y: h * 0.08), size: 1.0, opacity: 0.35)
                star(at: CGPoint(x: w * 0.72, y: h * 0.28), size: 1.6, opacity: 0.58)
                star(at: CGPoint(x: w * 0.86, y: h * 0.14), size: 1.0, opacity: 0.40)
                star(at: CGPoint(x: w * 0.94, y: h * 0.34), size: 1.4, opacity: 0.48)
            }
        }
    }

    private func star(at point: CGPoint, size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(Theme.textCream.opacity(opacity))
            .frame(width: size, height: size)
            .position(point)
    }

    // MARK: - Parallel body

    @ViewBuilder
    private func parallelBody(_ circle: SharedCircle) -> some View {
        yourListSection(circle)
        circleBoardSection(circle)
    }

    private func yourListSection(_ circle: SharedCircle) -> some View {
        let tasks = circle.sortedTasks
        let dayKey = CircleGraphService.dayKey()
        let done = circle.todayCount(userId: myUserId, on: dayKey)
        let total = tasks.count
        let allDone = total > 0 && done == total

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionEyebrow("TODAY")
                    Text("Your list")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if allDone {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("All done")
                            .font(.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(circle.kind.tintDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(circle.kind.tint.opacity(0.16))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                } else if total > 0 {
                    Text("\(done)/\(total)")
                        .font(.sans(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: allDone)

            if tasks.isEmpty {
                Text(canManage
                     ? "No tasks yet — add the first shared task below."
                     : "No tasks yet. The owner can add the shared list.")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        taskRow(circle, task, dayKey: dayKey)
                    }
                }
            }

            if canManage {
                addTaskButton
            }
        }
    }

    private func taskRow(_ circle: SharedCircle, _ task: CircleTaskRow, dayKey: String) -> some View {
        let mineDone = circle.didComplete(taskId: task.id, userId: myUserId, on: dayKey)
        let others = circle.completers(taskId: task.id, on: dayKey)
            .filter { $0 != myUserId }
            .compactMap { circle.profile($0) }

        return Button {
            UIImpactFeedbackGenerator(style: mineDone ? .light : .medium).impactOccurred()
            Task {
                await service.setCompletion(
                    circleId: circle.id,
                    taskId: task.id,
                    completed: !mineDone,
                    myUserId: myUserId
                )
            }
        } label: {
            HStack(spacing: 12) {
                checkbox(mineDone, tint: circle.kind.tint)

                Text(task.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(mineDone ? Theme.textPrimary.opacity(0.5) : Theme.textPrimary)
                    .strikethrough(mineDone, color: Theme.textPrimary.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if !others.isEmpty {
                    RemoteCircleAvatarStack(
                        members: others,
                        myUserId: myUserId,
                        maxVisible: 3,
                        diameter: 22,
                        onDark: false
                    )
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
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
        .accessibilityLabel("\(task.title), \(mineDone ? "done" : "not done")")
        .accessibilityAddTraits(mineDone ? [.isButton, .isSelected] : .isButton)
    }

    private func checkbox(_ done: Bool, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(done ? tint : Color.clear)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(done ? Color.clear : Theme.textPrimary.opacity(0.25), lineWidth: 1.6)
                )
            if done {
                Image(systemName: "checkmark")
                    .font(.sans(13, weight: .bold))
                    .foregroundStyle(Theme.textCream)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
    }

    private var addTaskButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            newTaskTitle = ""
            showAddTask = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.sans(12, weight: .semibold))
                Text("Add a shared task").font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a shared task")
    }

    // MARK: - Parallel: per-member board

    private func circleBoardSection(_ circle: SharedCircle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionEyebrow("THE CIRCLE")
                    Text(scope == .today ? "Today's progress" : "Across the run")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                scopeToggle
            }

            VStack(spacing: 10) {
                ForEach(orderedMembers(circle)) { member in
                    memberProgressRow(circle, member: member)
                }
            }
        }
    }

    private var scopeToggle: some View {
        HStack(spacing: 0) {
            scopeChip(.today, label: "Today")
            scopeChip(.overall, label: "Overall")
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Theme.textPrimary.opacity(0.06)))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Progress scope")
    }

    private func scopeChip(_ value: CircleScope, label: String) -> some View {
        let isSelected = scope == value
        return Button {
            guard scope != value else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) { scope = value }
        } label: {
            Text(label)
                .font(.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.6))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(isSelected ? Theme.textPrimary : Color.clear))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(label)
    }

    private func memberProgressRow(_ circle: SharedCircle, member: RemoteProfile) -> some View {
        let isMe = member.id == myUserId
        let taskIds = circle.sortedTasks.map(\.id)
        let completed = completedTaskIds(circle, userId: member.id, scope: scope)
        let done = completed.intersection(Set(taskIds)).count
        let total = taskIds.count
        let isQuiet = done == 0
        let complete = total > 0 && done == total

        return HStack(spacing: 12) {
            RemoteCircleAvatar(profile: member, size: 32, highlight: isMe)

            VStack(alignment: .leading, spacing: 7) {
                Text(isMe ? "You" : member.displayName)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                segmentedBar(taskIds: taskIds, completed: completed, tint: circle.kind.tint)
            }

            Spacer(minLength: 8)

            Text("\(done)/\(total)")
                .font(.sans(12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(complete ? Theme.alertGreen : Theme.textPrimary.opacity(isQuiet ? 0.4 : 0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .opacity(isQuiet ? 0.75 : 1)
    }

    private func segmentedBar(taskIds: [UUID], completed: Set<UUID>, tint: Color) -> some View {
        let count = max(taskIds.count, 1)
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { idx in
                let id = idx < taskIds.count ? taskIds[idx] : nil
                let filled = id.map { completed.contains($0) } ?? false
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(filled ? tint : Theme.textPrimary.opacity(0.1))
                    .frame(height: 6)
            }
        }
    }

    // MARK: - Collective body

    @ViewBuilder
    private func collectiveBody(_ circle: SharedCircle) -> some View {
        collectiveProgressCard(circle)
        logContributionSection(circle)
        contributorsSection(circle)
    }

    private func collectiveProgressCard(_ circle: SharedCircle) -> some View {
        let total = circle.contributionTotal
        let unit = circle.collectiveUnit ?? ""
        let pct = Int((circle.collectiveFraction * 100).rounded())

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(circleNumber(total))
                    .font(.serif(40, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.4), value: total)
                if let target = circle.collectiveTarget {
                    Text("/ \(circleNumber(target)) \(unit)")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                } else if !unit.isEmpty {
                    Text(unit)
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            if circle.collectiveTarget != nil {
                CircleProgressBar(fraction: circle.collectiveFraction, tint: circle.kind.tint, height: 12)

                HStack {
                    Text("\(pct)% there")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(circle.kind.tintDark)
                    Spacer()
                    Text("together so far")
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(circle.kind.tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(circle.kind.tint.opacity(0.22), lineWidth: 0.6)
        )
    }

    private func logContributionSection(_ circle: SharedCircle) -> some View {
        let unit = circle.collectiveUnit ?? ""
        let mine = circle.contributionTotal(userId: myUserId)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionEyebrow("LOG YOUR PROGRESS")
                Spacer()
                if mine > 0 {
                    Text("you: \(circleNumber(mine)) \(unit)")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .monospacedDigit()
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("0", text: $contributionText)
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused($contributionFocused)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                )

                Button {
                    if let amount = parsedContribution { logContribution(amount) }
                } label: {
                    Text("Add")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .frame(width: 72)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                .fill((parsedContribution ?? 0) > 0 ? circle.kind.tintDark : Theme.textPrimary.opacity(0.3))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled((parsedContribution ?? 0) <= 0)
                .accessibilityLabel("Add contribution")
            }

            HStack(spacing: 8) {
                ForEach([1.0, 5.0, 10.0], id: \.self) { amount in
                    quickAddChip(amount, tint: circle.kind)
                }
            }
        }
    }

    private func quickAddChip(_ amount: Double, tint: CircleKind) -> some View {
        Button {
            logContribution(amount)
        } label: {
            Text("+\(circleNumber(amount))")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(tint.tintDark)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(tint.tint.opacity(0.14)))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(circleNumber(amount))")
    }

    private func contributorsSection(_ circle: SharedCircle) -> some View {
        let unit = circle.collectiveUnit ?? ""
        let total = circle.contributionTotal
        let ranked = circle.members
            .map { ($0, circle.contributionTotal(userId: $0.id)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }

        return VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("WHO'S IN")
            VStack(spacing: 10) {
                ForEach(ranked, id: \.0.id) { member, amount in
                    let share = total > 0 ? amount / total : 0
                    HStack(spacing: 12) {
                        RemoteCircleAvatar(profile: member, size: 32, highlight: member.id == myUserId)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(member.id == myUserId ? "You" : member.displayName)
                                    .font(.sans(14, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(circleNumber(amount)) \(unit)")
                                    .font(.sans(12, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(amount > 0 ? Theme.textPrimary.opacity(0.7) : Theme.textPrimary.opacity(0.4))
                            }
                            CircleProgressBar(fraction: share, tint: circle.kind.tint, height: 6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
                    )
                    .opacity(amount > 0 ? 1 : 0.75)
                }
            }
        }
    }

    // MARK: - Witness body

    @ViewBuilder
    private func witnessBody(_ circle: SharedCircle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                sectionEyebrow("IN THE ROOM")
                Text("Just present")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("No shared goal — everyone keeps their own. A calm room you're in together.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            VStack(spacing: 10) {
                ForEach(orderedMembers(circle)) { member in
                    HStack(spacing: 12) {
                        RemoteCircleAvatar(profile: member, size: 34, highlight: member.id == myUserId)
                        Text(member.id == myUserId ? "You" : member.displayName)
                            .font(.sans(14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Circle().fill(CircleKind.witness.tint).frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    /// Labelled hairline separating the two goals in a hybrid.
    private var hybridDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.textPrimary.opacity(0.1)).frame(height: 0.5)
            Text("AND")
                .font(.sans(9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Rectangle().fill(Theme.textPrimary.opacity(0.1)).frame(height: 0.5)
        }
    }

    // MARK: - Shared goals (mode switching)

    private func sharedGoalsSection(_ circle: SharedCircle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("SHARED GOALS")

            goalCard(
                icon: "checklist",
                tint: CircleKind.parallel.tint,
                tintDark: CircleKind.parallel.tintDark,
                title: "Shared list",
                detail: circle.kind.hasSharedList
                    ? (circle.tasks.isEmpty ? "Everyone runs the same checklist" : "\(circle.tasks.count) shared task\(circle.tasks.count == 1 ? "" : "s")")
                    : "Everyone runs the same checklist each day",
                active: circle.kind.hasSharedList,
                actionLabel: circle.kind.hasSharedList ? "Set aside" : "Add",
                destructive: circle.kind.hasSharedList,
                action: {
                    let next = CircleKind.from(hasList: !circle.kind.hasSharedList, hasNumber: circle.kind.hasSharedNumber)
                    Task { await service.setCircleKind(circleId: circle.id, kind: next, myUserId: myUserId) }
                }
            )

            if circle.kind.hasSharedNumber {
                goalCard(
                    icon: "number",
                    tint: CircleKind.collective.tint,
                    tintDark: CircleKind.collective.tintDark,
                    title: "Shared number",
                    detail: numberDetail(circle),
                    active: true,
                    actionLabel: "Set aside",
                    destructive: true,
                    action: {
                        let next = CircleKind.from(hasList: circle.kind.hasSharedList, hasNumber: false)
                        Task { await service.setCircleKind(circleId: circle.id, kind: next, myUserId: myUserId) }
                    }
                )
            } else if showNumberForm {
                numberForm(circle)
            } else {
                goalCard(
                    icon: "number",
                    tint: CircleKind.collective.tint,
                    tintDark: CircleKind.collective.tintDark,
                    title: "Shared number",
                    detail: circle.collectiveTarget != nil ? "Resume \(numberDetail(circle)) — the total's still there" : "One number you build toward together",
                    active: false,
                    actionLabel: "Add",
                    destructive: false,
                    action: {
                        numberUnit = circle.collectiveUnit ?? ""
                        numberTarget = circle.collectiveTarget.map { circleNumber($0) } ?? ""
                        withAnimation(.easeInOut(duration: 0.18)) { showNumberForm = true }
                    }
                )
            }

            if circle.kind == .witness {
                Text("This is a Witness circle — pure presence. Add a goal anytime, or keep it a calm room.")
                    .font(.serifItalic(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            } else if circle.kind == .hybrid {
                Text("Running two goals at once. Set one aside anytime to keep things simple.")
                    .font(.serifItalic(12, weight: .regular))
                    .foregroundStyle(CircleKind.hybrid.tintDark.opacity(0.85))
            }
        }
    }

    private func numberDetail(_ circle: SharedCircle) -> String {
        let unit = circle.collectiveUnit ?? ""
        if let target = circle.collectiveTarget {
            return "\(circleNumber(target)) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        return unit.isEmpty ? "One number, together" : unit
    }

    private func goalCard(
        icon: String,
        tint: Color,
        tintDark: Color,
        title: String,
        detail: String,
        active: Bool,
        actionLabel: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(active ? 0.18 : 0.1)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(active ? tintDark : tint.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sans(15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: destructive ? .light : .medium).impactOccurred()
                action()
            } label: {
                Text(actionLabel)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.textPrimary.opacity(0.65) : Theme.textCream)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Group {
                            if destructive {
                                Capsule(style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.2), lineWidth: 0.6)
                            } else {
                                Capsule(style: .continuous).fill(tint)
                            }
                        }
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(service.isWorking)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func numberForm(_ circle: SharedCircle) -> some View {
        let target = Double(numberTarget.trimmingCharacters(in: .whitespaces))
        let unit = numberUnit.trimmingCharacters(in: .whitespaces)
        let valid = (target ?? 0) > 0 && !unit.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "number").font(.sans(14, weight: .semibold)).foregroundStyle(CircleKind.collective.tintDark)
                Text("Add a shared number").font(.sans(14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 10) {
                TextField("1000", text: $numberTarget)
                    .keyboardType(.numberPad)
                    .font(.sans(15, weight: .semibold))
                    .frame(width: 88)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(numberFieldBackground)
                TextField("miles, plunges, pages…", text: $numberUnit)
                    .font(.sans(15, weight: .regular))
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(numberFieldBackground)
            }
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cancelNumberForm()
                } label: {
                    Text("Cancel")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                Button {
                    guard let target, target > 0, !unit.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let next = CircleKind.from(hasList: circle.kind.hasSharedList, hasNumber: true)
                    let circleId = circle.id
                    Task { await service.setCircleKind(circleId: circleId, kind: next, unit: unit, target: target, myUserId: myUserId) }
                    cancelNumberForm()
                } label: {
                    Text("Add number")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(valid ? CircleKind.collective.tint : Theme.textPrimary.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!valid)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var numberFieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
            )
    }

    private func cancelNumberForm() {
        withAnimation(.easeInOut(duration: 0.18)) { showNumberForm = false }
        numberUnit = ""
        numberTarget = ""
    }

    // MARK: - Footer (leave / delete)

    private func inviteFriendsButton(_ circle: SharedCircle) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showInvite = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus").font(.sans(14, weight: .semibold))
                Text("Invite friends").font(.sans(15, weight: .medium))
            }
            .foregroundStyle(circle.kind.tintDark)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(circle.kind.tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite friends to this circle")
    }

    private func membershipFooter(_ circle: SharedCircle) -> some View {
        VStack(spacing: 12) {
            inviteFriendsButton(circle)

            Rectangle()
                .fill(Theme.textPrimary.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isOwner { showDeleteConfirm = true } else { showLeaveConfirm = true }
            } label: {
                Text(isOwner ? "Delete circle" : "Leave circle")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.alertRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.alertRed.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text(isOwner
                 ? "You own this circle. Deleting it removes it for everyone."
                 : "Leaving removes you from this circle. A member can add you back later.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    // MARK: - Shared chrome

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(2)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }

    // MARK: - Derived

    private var parsedContribution: Double? {
        Double(contributionText.trimmingCharacters(in: .whitespaces))
    }

    private func eyebrow(_ circle: SharedCircle) -> String {
        let base = circle.kind.eyebrow
        if circle.isOngoing { return "\(base) · ONGOING" }
        if let end = circle.endDate {
            let days = CircleDetailHelpers.daysLeft(until: end)
            return "\(base) · \(days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT")"
        }
        return base
    }

    private func membershipCaption(_ circle: SharedCircle) -> String {
        let count = circle.members.count
        let includesMe = circle.members.contains { $0.id == myUserId }
        let others = max(0, count - (includesMe ? 1 : 0))
        if includesMe {
            if others == 0 { return "just you" }
            return others == 1 ? "you + 1 other" : "you + \(others) others"
        }
        return count == 1 ? "1 person" : "\(count) people"
    }

    /// Self first, then everyone else alphabetically.
    private func orderedMembers(_ circle: SharedCircle) -> [RemoteProfile] {
        circle.members.sorted { a, b in
            if a.id == myUserId { return true }
            if b.id == myUserId { return false }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Task ids a member has completed in the current scope: today =
    /// same-day completions; overall = ever completed across the run
    /// (de-duplicated so repeats still read as one filled segment).
    private func completedTaskIds(_ circle: SharedCircle, userId: String, scope: CircleScope) -> Set<UUID> {
        let taskIds = Set(circle.tasks.map(\.id))
        let dayKey = CircleGraphService.dayKey()
        let matches = circle.completions.filter { c in
            guard c.userId == userId, taskIds.contains(c.taskId) else { return false }
            switch scope {
            case .today: return c.completedOn == dayKey
            case .overall: return true
            }
        }
        return Set(matches.map(\.taskId))
    }

    // MARK: - Actions

    private func commitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newTaskTitle = ""
        guard !title.isEmpty else { return }
        Task { await service.addTask(circleId: circleId, title: title, myUserId: myUserId) }
    }

    private func logContribution(_ amount: Double) {
        guard amount > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        contributionText = ""
        contributionFocused = false
        Task { await service.addContribution(circleId: circleId, amount: amount, myUserId: myUserId) }
    }
}

#Preview {
    NavigationStack {
        SharedCircleDetailView(
            service: CircleGraphService(),
            circleId: UUID(),
            myUserId: "preview-user"
        )
    }
}
