//
//  SharedCirclesListView.swift
//  FrisFocus
//
//  The real shared-circles hub, reached from the account screen right
//  beside Friends. Lists every circle the signed-in user belongs to,
//  backed by `CircleGraphService` (Supabase) — so it syncs across every
//  device and updates live while the screen is open.
//
//  Design mirrors `FriendsView`: warm-wheat page, paper-cream cards. The
//  page owns both the circle graph and a friend graph (the friend list
//  feeds the create picker, and lets the empty state nudge the user to
//  add a friend first when they have none).
//

import SwiftUI
import UIKit

struct SharedCirclesListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var service = CircleGraphService()
    @State private var friendService = FriendGraphService()
    @State private var showCreate = false

    private var myId: String? { auth.user?.id }

    var body: some View {
        @Bindable var service = service

        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Circles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await liveRefresh() }
        .refreshable { await reloadOnce() }
        .fullScreenCover(isPresented: $showCreate) {
            CreateSharedCircleView(
                service: service,
                friends: friendService.friends,
                myUserId: myId ?? ""
            )
        }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if auth.user == nil {
            signedOut
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    startButton

                    if service.isLoading && service.circles.isEmpty {
                        ProgressView()
                            .tint(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if service.circles.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.circles) { circle in
                            NavigationLink {
                                SharedCircleDetailView(
                                    service: service,
                                    circleId: circle.id,
                                    myUserId: myId ?? ""
                                )
                            } label: {
                                CircleCard(circle: circle, myUserId: myId ?? "")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
        }
    }

    // MARK: - Header

    private var intro: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SHARED GOALS")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text("Circles you run together with real friends.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var startButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCreate = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Start a circle")
                    .font(.sans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / signed-out states

    private var emptyState: some View {
        let hasFriends = !friendService.friends.isEmpty
        return VStack(spacing: 10) {
            Image(systemName: hasFriends ? "circle.hexagongrid" : "person.2")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(hasFriends ? "No circles yet" : "Add a friend first")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(hasFriends
                 ? "Start a circle to chase a goal together — a shared daily list or one number you build toward."
                 : "Circles run with the friends you add by email. Add someone, then start your first circle together.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background(Theme.paperCream.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.top, 6)
    }

    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Sign in to share circles")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(40)
    }

    // MARK: - Live refresh

    /// Initial load, then a gentle poll so a friend's check-off or
    /// contribution shows up without a manual refresh. SwiftUI cancels
    /// this `.task` when the screen leaves, ending the loop. The detail
    /// screen reads from this same `service`, so polling here keeps the
    /// pushed detail live too.
    private func liveRefresh() async {
        guard let myId else { return }
        await service.load(myUserId: myId)
        await friendService.load(myUserId: myId)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
            if Task.isCancelled { break }
            await service.load(myUserId: myId)
        }
    }

    private func reloadOnce() async {
        guard let myId else { return }
        await service.load(myUserId: myId)
        await friendService.load(myUserId: myId)
    }
}

// MARK: - Circle card

private struct CircleCard: View {
    let circle: SharedCircle
    let myUserId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(circle.name)
                    .font(.serif(18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                kindChip
            }

            HStack(spacing: 10) {
                RemoteCircleAvatarStack(
                    members: circle.members,
                    myUserId: myUserId,
                    maxVisible: 4,
                    diameter: 26,
                    onDark: false
                )
                Text(membershipCaption)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }

            progressRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var kindChip: some View {
        Text(circle.kind.shortLabel)
            .font(.sans(11, weight: .semibold))
            .foregroundStyle(circle.kind.tintDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(circle.kind.tint.opacity(0.16))
            .clipShape(Capsule())
    }

    private var membershipCaption: String {
        let count = circle.members.count
        return count == 1 ? "just you" : "\(count) people"
    }

    @ViewBuilder
    private var progressRow: some View {
        switch circle.kind {
        case .parallel:
            let dayKey = CircleGraphService.dayKey()
            let done = circle.todayCount(userId: myUserId, on: dayKey)
            let total = circle.tasks.count
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(circle.kind.tintDark)
                Text(total == 0 ? "No tasks yet" : "You \(done)/\(total) today")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .monospacedDigit()
                Spacer()
            }
        case .collective:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(circleNumber(circle.contributionTotal))")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    if let target = circle.collectiveTarget {
                        Text("/ \(circleNumber(target)) \(circle.collectiveUnit ?? "")")
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    } else if let unit = circle.collectiveUnit {
                        Text(unit)
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                if circle.collectiveTarget != nil {
                    CircleProgressBar(fraction: circle.collectiveFraction, tint: circle.kind.tint, height: 8)
                }
            }
        }
    }
}
