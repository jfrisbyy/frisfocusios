//
//  FindPeopleStep.swift
//  FrisFocus
//
//  Step 3 of the account seam: bring a few people in, strictly opt-in.
//  An honest pre-prompt explains why before the system contacts dialog;
//  after granting, contacts split into people already on FrisFocus (one
//  tap to send a friend request) and people to invite (opens Messages
//  pre-filled with the personal invite link). Nothing is ever auto-added.
//  A prominent "Maybe later" is always present; the primary button lands
//  the person on their live home with their board.
//

import SwiftUI
import UIKit

struct FindPeopleStep: View {
    /// Land on the live home with the saved board.
    let onFinish: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FriendGraphService.self) private var graph
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var service = ContactsMatchService()
    @State private var addedIds: Set<String> = []
    @State private var invitedIds: Set<String> = []
    @State private var shown: Bool = false

    private var myId: String? { auth.user?.id }

    private var inviteMessage: String {
        let handle = profileStore.myProfile?.handle
        let link = myId.flatMap { InviteLink.url(forUserId: $0)?.absoluteString } ?? ""
        if let handle {
            return "I'm on FrisFocus as \(handle) — add me and let's keep each other going. \(link)"
        }
        return "I'm on FrisFocus — add me and let's keep each other going. \(link)"
    }

    private var visibleMatches: [RemoteProfile] {
        guard let myId else { return [] }
        return service.matched.filter { profile in
            guard !moderation.isBlocked(profile.id) else { return false }
            return graph.relationship(to: profile.id, myUserId: myId) != .isMe
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)

            content
                .opacity(shown ? 1 : 0)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)) {
                shown = true
            }
        }
        .task {
            if service.isAuthorized, !service.hasLoaded, let myId {
                await service.match(myUserId: myId)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            EyebrowText(text: "FIND YOUR PEOPLE", opacity: 0.5)
            Text("Seasons are\nbetter witnessed.")
                .font(.serif(29, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bring a few people who'll keep up with you. You pick who — no one's added without you.")
                .font(.sans(13.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 6)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if service.isDenied {
            Spacer()
            deniedState.padding(.horizontal, 32)
            Spacer()
        } else if !service.isAuthorized {
            Spacer()
            askState.padding(.horizontal, 28)
            Spacer()
        } else if service.isWorking && !service.hasLoaded {
            Spacer()
            VStack(spacing: 10) {
                ProgressView().tint(Theme.textPrimary)
                Text("Checking your contacts…")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        } else {
            resultsList
        }
    }

    private var askState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.paperCream)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .frame(width: 84, height: 84)

            Text("FrisFocus checks your contacts in the moment to find people already here — your contacts are never stored on our servers.")
                .font(.sans(13.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let myId else { return }
                Task { await service.connectAndMatch(myUserId: myId) }
            } label: {
                Text("Connect contacts")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Contacts access is off")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("You can find friends anytime later from your profile. Everything else works without it.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if visibleMatches.isEmpty && service.inviteCandidates.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("No matches yet")
                    .font(.serif(18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("None of your contacts are here yet — you can invite them anytime.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)
            Spacer()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !visibleMatches.isEmpty {
                        sectionHeader("ALREADY ON FRISFOCUS", subtitle: "From your contacts — add to keep up.")
                        ForEach(visibleMatches) { profile in
                            matchRow(profile)
                        }
                    }
                    if !service.inviteCandidates.isEmpty {
                        sectionHeader("INVITE TO JOIN", subtitle: "Send them your link.")
                            .padding(.top, visibleMatches.isEmpty ? 0 : 14)
                        ForEach(service.inviteCandidates) { candidate in
                            inviteRow(candidate)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: Rows

    private func matchRow(_ profile: RemoteProfile) -> some View {
        let added = addedIds.contains(profile.id)
        return HStack(spacing: 12) {
            avatar(url: profile.photoURL, initials: profile.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let handle = profile.handle {
                    Text(handle)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard let myId, !added else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addedIds.insert(profile.id)
                Task {
                    await graph.sendRequest(to: profile, myUserId: myId)
                    socialSync.pokeEngine(trigger: "friend")
                }
            } label: {
                pill(title: added ? "Added" : "Add", filled: !added, icon: added ? "checkmark" : "plus")
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func inviteRow(_ candidate: ContactCandidate) -> some View {
        let invited = invitedIds.contains(candidate.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.08))
                Text(candidate.initials)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let phone = candidate.primaryPhone {
                    Text(phone)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                invitedIds.insert(candidate.id)
                sendInvite(to: candidate)
            } label: {
                pill(title: invited ? "Invited" : "Invite", filled: false, icon: invited ? "checkmark" : nil)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func avatar(url: URL?, initials: String) -> some View {
        ZStack {
            Circle().fill(Theme.textPrimary.opacity(0.08))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        Text(initials)
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
            }
        }
        .frame(width: 44, height: 44)
    }

    private func pill(title: String, filled: Bool, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(.sans(14, weight: .semibold))
        }
        .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(filled ? Theme.textPrimary : Color.clear)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Theme.textPrimary.opacity(filled ? 0 : 0.25), lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            if let subtitle {
                Text(subtitle)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onFinish()
            } label: {
                HStack(spacing: 10) {
                    Text("Start my season")
                        .font(.sans(17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.textPrimary)
                )
            }
            .buttonStyle(.plain)

            Button {
                onFinish()
            } label: {
                Text("Maybe later")
                    .font(.sans(14.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Invite via Messages

    private func sendInvite(to candidate: ContactCandidate) {
        guard let phone = candidate.primaryPhone else { return }
        let number = phone.filter { $0.isNumber || $0 == "+" }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let body = inviteMessage.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(number)&body=\(body)") else { return }
        UIApplication.shared.open(url)
    }
}
