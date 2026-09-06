//
//  DiscoverCirclesView.swift
//  FrisFocus
//
//  The public-circles directory. Lists circles whose owners flipped
//  them public, searchable by name/description. Each listing shows
//  only the circle's headline — name, shape, member count, window,
//  the owner's blurb — never anyone's tasks, scores, or identities.
//
//  Joining follows the owner's rule:
//   • open      — "Join" lands you in the circle instantly and pushes
//                 straight into its detail.
//   • approval  — "Ask to join" files a request; the button flips to
//                 "Requested" while the owner decides.
//

import SwiftUI
import UIKit

struct DiscoverCirclesView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var service = CircleGraphService()
    @State private var query: String = ""
    /// Pushed after a successful open join — straight into the room.
    @State private var joinedCircleId: UUID?
    /// The circle currently mid-join so its button can show a spinner.
    @State private var workingCircleId: UUID?

    private var myId: String? { auth.user?.id }

    var body: some View {
        @Bindable var service = service

        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    intro
                        .padding(.top, 14)

                    searchField
                        .padding(.top, 14)

                    content
                        .padding(.top, 18)
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.bottom, 44)
            }
        }
        .edgeSwipeBack()
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            guard let myId else { return }
            await service.loadDiscover(myUserId: myId)
        }
        // Joining an open circle subscribes this screen's own graph
        // service to realtime. Without this the channel outlived the
        // screen — one leaked subscription per visit, still delivering
        // after sign-out. The sibling screens that start realtime
        // (SharedCirclesListView, NotificationRouteHost) already do this;
        // this one was the odd one out.
        .onDisappear { service.stopRealtime() }
        .task(id: query) {
            // Debounced server-side search — waits for a typing pause.
            guard let myId else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await service.loadDiscover(search: query, myUserId: myId)
        }
        .refreshable {
            guard let myId else { return }
            await service.loadDiscover(search: query, myUserId: myId)
        }
        .navigationDestination(item: $joinedCircleId) { circleId in
            SharedCircleDetailView(
                service: service,
                circleId: circleId,
                myUserId: myId ?? ""
            )
        }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Header + search

    private var intro: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("OPEN TO ANYONE")
                .font(.sans(10.5, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("Circles people have opened up. Join one, or ask to.")
                .font(.sans(12.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            TextField("Search public circles", text: $query)
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if service.isDiscovering && service.discovered.isEmpty {
            ProgressView()
                .tint(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if service.discovered.isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(service.discovered) { circle in
                    listing(circle)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(query.isEmpty ? "Nothing public yet" : "No circles match")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(query.isEmpty
                 ? "When someone makes a circle public it shows up here. You can open one of yours from its settings."
                 : "Try a different name — or start the circle yourself and make it public.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 22)
        .background(Theme.paperCream.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Listing card

    private func listing(_ circle: DiscoverableCircle) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow(for: circle))
                        .font(.sans(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(circle.kind.tintDark.opacity(0.9))
                    Text(circle.name)
                        .font(.serif(18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                kindChip(circle.kind)
            }

            if let blurb = circle.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !blurb.isEmpty {
                Text(blurb)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text(memberCaption(circle))
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))

                Spacer(minLength: 8)

                joinControl(circle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(circle.kind.tint.opacity(0.2), lineWidth: 0.6)
        )
    }

    private func kindChip(_ kind: CircleKind) -> some View {
        Text(kind.shortLabel)
            .font(.sans(11, weight: .semibold))
            .foregroundStyle(kind.tintDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(kind.tint.opacity(0.16))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func joinControl(_ circle: DiscoverableCircle) -> some View {
        let isWorking = workingCircleId == circle.id
        let isRequested = service.myPendingRequestCircleIds.contains(circle.id)

        if isRequested {
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                    .font(.sans(11, weight: .semibold))
                Text("Requested")
                    .font(.sans(13, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule(style: .continuous).fill(Theme.textPrimary.opacity(0.07)))
            .accessibilityLabel("Request pending")
        } else {
            Button {
                handleJoin(circle)
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                            .tint(Theme.textCream)
                            .scaleEffect(0.8)
                    } else {
                        Text(circle.isOpenJoin ? "Join" : "Ask to join")
                            .font(.sans(13, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.textCream)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule(style: .continuous).fill(Theme.textPrimary))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel(circle.isOpenJoin ? "Join \(circle.name)" : "Ask to join \(circle.name)")
        }
    }

    // MARK: - Copy

    private func eyebrow(for circle: DiscoverableCircle) -> String {
        let type = circle.kind.eyebrow.replacingOccurrences(of: " CIRCLE", with: "")
        guard circle.timeframeKind == "time_boxed",
              let endDate = parseDate(circle.endDate) else {
            return "\(type) · ONGOING"
        }
        let days = max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: endDate)
        ).day ?? 0)
        return "\(type) · \(days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT")"
    }

    private func memberCaption(_ circle: DiscoverableCircle) -> String {
        let members = circle.memberCount == 1 ? "1 member" : "\(circle.memberCount) members"
        if circle.kind == .collective, let target = circle.collectiveTarget {
            let unit = circle.collectiveUnit ?? ""
            return "\(members) · \(circleNumber(target)) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        return members
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    // MARK: - Actions

    private func handleJoin(_ circle: DiscoverableCircle) {
        guard let myId else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        workingCircleId = circle.id
        Task {
            defer { workingCircleId = nil }
            if circle.isOpenJoin {
                let ok = await service.joinPublicCircle(circleId: circle.id, myUserId: myId)
                if ok {
                    service.startRealtime(myUserId: myId)
                    joinedCircleId = circle.id
                }
            } else {
                await service.requestToJoin(circleId: circle.id, myUserId: myId)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiscoverCirclesView()
            .environment(AuthManager())
    }
}
