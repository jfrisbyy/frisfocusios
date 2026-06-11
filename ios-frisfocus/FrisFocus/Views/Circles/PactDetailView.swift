//
//  PactDetailView.swift
//  FrisFocus
//
//  Detail page for one pact. Leads with the two people, symmetric —
//  you and partner avatars face-to-face on the hero, the line "no
//  winner — you both finish, or you push each other to it" stated
//  plainly, and equal-weight progress cards side by side. Status
//  copy is always cooperative. Cheer routes to the C7 composer
//  addressed to the partner.
//

import SwiftUI
import UIKit

struct PactDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let pact: Pact

    @State private var showCheerComposer: Bool = false
    @State private var showSettings: Bool = false
    @State private var showLeaveConfirm: Bool = false
    /// You or your partner, whichever's profile is open.
    @State private var profileTarget: ProfileTarget?

    /// The live pact from the store so completion toggles re-render the
    /// progress cards without a manual reload.
    private var livePact: Pact { store.pact(by: pact.id) ?? pact }
    private var partner: Friend? { store.partnerFriend(forPact: livePact) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 20) {
                        antiCompetitionLine

                        if livePact.status == .active {
                            twoProgressCards
                            statusLine
                            todaySection
                            actions
                        } else if livePact.status == .pending {
                            pendingBlock
                        } else if livePact.status == .completed {
                            completedBlock
                        } else {
                            declinedBlock
                        }
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 24)

                    Color.clear.frame(height: 140)
                }
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)

            SundialNavView(
                active: .subPage,
                onCaptureTap: {},
                onHomeTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                },
                onCirclesTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .edgeSwipeBack()
        .profileDestination($profileTarget, store: store)
        .sheet(isPresented: $showCheerComposer) {
            if let partner {
                CheerComposerView(friend: partner)
                    .environment(store)
            }
        }
        .confirmationDialog(
            "Pact settings",
            isPresented: $showSettings,
            titleVisibility: .visible
        ) {
            Button("End the pact now") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.endPact(livePact.id)
            }
            Button("Leave the pact", role: .destructive) {
                showLeaveConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Leave this pact?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.leavePact(livePact.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Walking away clears the pact for both of you. No record kept.")
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let partnerColor = partner.map { Color(hex: $0.accentColorHex) } ?? Color(hex: 0x6B4D70)

        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    partnerColor.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            topBar
                .padding(.top, 56)
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow)
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textCream.opacity(0.78))
                Text(livePact.title)
                    .font(.serif(28, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(2)

                pairLine
                    .padding(.top, 4)
            }
            .padding(.leading, Theme.pageHorizontalPadding)
            .padding(.trailing, Theme.pageHorizontalPadding)
            .padding(.bottom, 18)
        }
        .frame(height: 230)
        .clipped()
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.sans(15, weight: .medium))
                    Text("Pacts")
                        .font(.sans(14, weight: .regular))
                }
                .foregroundStyle(Theme.textCream)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Pacts")
            Spacer()
        }
    }

    private var eyebrow: String {
        let partnerName = partner?.displayName ?? "friend"
        switch livePact.status {
        case .pending:
            return livePact.proposerId == store.currentUserId
                ? "PENDING · \(partnerName.uppercased()) HASN’T ACCEPTED YET"
                : "INVITE FROM \(partnerName.uppercased())"
        case .active:
            let days = store.pactDaysLeft(pact: livePact)
            let suffix = days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT"
            return "A PACT WITH \(partnerName.uppercased()) · \(suffix)"
        case .completed:
            return "THE WINDOW CLOSED"
        case .declined:
            return "DECLINED"
        }
    }

    /// "you ↔ partner" — symmetric, with a connecting line. Visual
    /// cue that this is together, not versus.
    private var pairLine: some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                profileTarget = .me
            } label: {
                youDisc
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your profile")

            Text("you")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textCream.opacity(0.85))
            Rectangle()
                .fill(Theme.textCream.opacity(0.35))
                .frame(height: 1)
            if let partner {
                Text(partner.displayName.lowercased())
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    profileTarget = .friend(partner)
                } label: {
                    partnerDisc(partner)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(partner.displayName)'s profile")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var youDisc: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text("J")
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 28, height: 28)
        .overlay(
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Theme.sunWarm, Theme.sunOuter],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.6
            )
        )
    }

    private func partnerDisc(_ friend: Friend) -> some View {
        ZStack {
            Circle().fill(Color(hex: friend.accentColorHex))
            Text(friend.initials)
                .font(.sans(11, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.6), lineWidth: 1))
    }

    // MARK: - Anti-competition line

    private var antiCompetitionLine: some View {
        Text("no winner — you both finish, or you push each other to")
            .font(.serifItalic(14, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: - Progress

    private var twoProgressCards: some View {
        let window = max(livePact.durationDays, 1)
        let youKept = store.pactDaysKept(pact: livePact, userId: store.currentUserId)
        let partnerKept = partner.map { store.pactDaysKept(pact: livePact, userId: $0.id) } ?? 0

        return HStack(spacing: 12) {
            progressCard(
                title: "You",
                kept: youKept,
                window: window,
                tint: Theme.sunOuter
            )
            progressCard(
                title: partner?.displayName ?? "Partner",
                kept: partnerKept,
                window: window,
                tint: partner.map { Color(hex: $0.accentColorHex) } ?? Theme.alertGreen
            )
        }
    }

    private func progressCard(title: String, kept: Int, window: Int, tint: Color) -> some View {
        let fraction = min(1.0, max(0.0, Double(kept) / Double(window)))
        return VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            Text("\(kept)")
                .font(.serif(36, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text("of \(window) days")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// Cooperative status copy. Never "you're losing"; always frames
    /// the remaining work as something the pair does together.
    private var statusLine: some View {
        Text(statusCopy)
            .font(.sans(13, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.8))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.paperCream)
            )
    }

    private var statusCopy: String {
        let partnerName = partner?.displayName ?? "your partner"
        let daysLeft = store.pactDaysLeft(pact: livePact)
        let target = livePact.durationDays
        let youKept = store.pactDaysKept(pact: livePact, userId: store.currentUserId)
        let partnerKept = partner.map { store.pactDaysKept(pact: livePact, userId: $0.id) } ?? 0
        let youDone = youKept >= target
        let partnerDone = partnerKept >= target

        if youDone && partnerDone {
            return "You both kept the pact. Together."
        }
        if youDone {
            return "You’ve kept it — cheer \(partnerName) to the finish."
        }
        if partnerDone {
            return "\(partnerName) kept the pact — you’ve got \(daysLeft == 1 ? "1 day" : "\(daysLeft) days") left."
        }
        if daysLeft == 0 {
            return "The window’s closing. Whatever lands today, lands together."
        }
        if daysLeft == 1 {
            return "You’re both still in it. 1 more day each to keep the pact."
        }
        return "You’re both on track. \(daysLeft) more days each to keep the pact."
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 8) {
                ForEach(livePact.tasks) { task in
                    TodayTaskRow(pact: livePact, task: task)
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            cheerButton
            settingsButton
        }
    }

    private var cheerButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCheerComposer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.sans(12, weight: .semibold))
                Text("Cheer \(partner?.displayName ?? "partner")")
                    .font(.sans(14, weight: .semibold))
            }
            .foregroundStyle(Theme.sunShadow)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.sunOuter.opacity(0.45), lineWidth: 0.8)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(partner == nil)
        .accessibilityLabel("Cheer \(partner?.displayName ?? "partner")")
    }

    private var settingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        } label: {
            Text("Pact settings")
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.textPrimary.opacity(0.06))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pact settings")
    }

    // MARK: - Other status blocks

    private var pendingBlock: some View {
        VStack(spacing: 14) {
            Text(livePact.proposerId == store.currentUserId
                 ? "Waiting on \(partner?.displayName ?? "your partner")."
                 : "\(partner?.displayName ?? "Your partner") proposed this pact.")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("When both of you start, the window opens for \(livePact.durationDays) days.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)

            if livePact.proposerId != store.currentUserId {
                HStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.declinePact(livePact.id)
                    } label: {
                        Text("Decline")
                            .font(.sans(14, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Theme.textPrimary.opacity(0.06))
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        store.acceptPact(livePact.id)
                    } label: {
                        Text("Accept")
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Theme.textPrimary)
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.leavePact(livePact.id)
                    dismiss()
                } label: {
                    Text("Cancel pact")
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.textPrimary.opacity(0.06))
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var completedBlock: some View {
        let youKept = store.pactDaysKept(pact: livePact, userId: store.currentUserId)
        let partnerKept = partner.map { store.pactDaysKept(pact: livePact, userId: $0.id) } ?? 0
        let bothKept = youKept >= livePact.durationDays && partnerKept >= livePact.durationDays

        return VStack(spacing: 12) {
            Text(bothKept ? "You kept the pact together." : "The window’s closed.")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(bothKept
                 ? "Same window, same commitment. Both of you showed up."
                 : "You showed up \(youKept) day\(youKept == 1 ? "" : "s") · \(partner?.displayName ?? "Partner") \(partnerKept) day\(partnerKept == 1 ? "" : "s").")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.paperCream)
        )
    }

    private var declinedBlock: some View {
        Text("This pact was declined.")
            .font(.serifItalic(14, weight: .regular))
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
    }
}

// MARK: - Today task row

private struct TodayTaskRow: View {
    @Environment(Store.self) private var store
    let pact: Pact
    let task: PactTask

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.togglePactTaskCompletion(pactId: pact.id, task: task)
        } label: {
            HStack(spacing: 12) {
                checkbox
                Text(task.name)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let category = task.category {
                    Circle()
                        .fill(category.color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
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
        .accessibilityLabel(task.name)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }

    private var isDone: Bool {
        store.hasUserCompletedPactTaskToday(pactId: pact.id, taskId: task.id)
    }

    private var checkbox: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(0.35), lineWidth: 1.4)
                .frame(width: 22, height: 22)
            if isDone {
                Circle()
                    .fill(Theme.alertGreen)
                    .frame(width: 14, height: 14)
            }
        }
    }
}

#Preview {
    let store = Store()
    return NavigationStack {
        if let pact = store.myPacts.first {
            PactDetailView(pact: pact)
        }
    }
    .environment(store)
}
