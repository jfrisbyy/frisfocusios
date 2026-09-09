//
//  ProfileQuickCard.swift
//  FrisFocus
//
//  The avatar quick-profile experience. Tapping the top-right avatar on
//  the home or social screen springs open a small floating card that
//  scales and fades out of the bubble's corner, over a dimmed + softly
//  blurred backdrop. The card carries the user's identity (a tap there
//  opens My profile — the page friends see, with edit shortcuts), a
//  slim two-tile row (My profile · Friends), and a route into the full
//  account screen where sign-out / delete / blocked live.
//
//  Wired once per host via `.profileQuickCard(isPresented:)`. When signed
//  out, the same tap opens the full sign-in sheet — the quick card is a
//  signed-in convenience, nothing more — so both entry points behave
//  identically on every screen.
//

import SwiftUI
import UIKit

// MARK: - Destinations

/// A surface the quick card can route to. `myProfile` opens the user's
/// own profile page full-screen; `account` opens the full hub; the rest
/// open their own focused screen.
enum ProfileQuickDestination: Int, Identifiable {
    case myProfile, editProfile, friends, account, proofLibrary, help
    var id: Int { rawValue }
}

// MARK: - Public entry point

extension View {
    /// Attach the avatar quick-profile experience to a screen. Flip
    /// `isPresented` true (from the avatar's tap action) to open it.
    ///
    /// Signed in → the floating quick card. Signed out → the full
    /// sign-in sheet, matching the app's prior behaviour.
    func profileQuickCard(isPresented: Binding<Bool>) -> some View {
        modifier(ProfileQuickCardModifier(isPresented: isPresented))
    }
}

private struct ProfileQuickCardModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AuthManager.self) private var auth

    @State private var destination: ProfileQuickDestination?

    /// Signed-out tap → full sign-in sheet. Derived from the shared
    /// trigger so the host only owns one piece of state.
    private var showSignIn: Binding<Bool> {
        Binding(
            get: { isPresented && auth.user == nil },
            set: { newValue in if !newValue { isPresented = false } }
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented, auth.user != nil {
                    ProfileQuickCardOverlay { dest in
                        // The overlay has already played its dismiss
                        // animation — it isn't a presentation, so the
                        // chosen destination can raise immediately
                        // without the transitions fighting.
                        isPresented = false
                        if let dest {
                            destination = dest
                        }
                    }
                    .onAppear { Log.app.debug("profile: quick card presented") }
                }
            }
            .sheet(isPresented: showSignIn) {
                ProfileSheetView()
            }
            .sheet(item: sheetDestination) { dest in
                ProfileQuickDestinationSheet(destination: dest)
            }
            .fullScreenCover(item: coverDestination) { _ in
                MyProfileView()
            }
    }

    /// Every destination except My profile presents as a sheet.
    private var sheetDestination: Binding<ProfileQuickDestination?> {
        Binding(
            get: { destination == .myProfile ? nil : destination },
            set: { newValue in
                if newValue == nil, destination != .myProfile { destination = nil }
            }
        )
    }

    /// My profile is a full page — it presents full-screen, exactly
    /// like a friend's profile does.
    private var coverDestination: Binding<ProfileQuickDestination?> {
        Binding(
            get: { destination == .myProfile ? .myProfile : nil },
            set: { newValue in
                if newValue == nil, destination == .myProfile { destination = nil }
            }
        )
    }
}

// MARK: - Overlay (backdrop + card)

private struct ProfileQuickCardOverlay: View {
    /// Called once the dismiss animation finishes. `nil` = plain close;
    /// a value = close then route there.
    let onDismiss: (ProfileQuickDestination?) -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FriendGraphService.self) private var friendGraph

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isClosing: Bool = false
    @State private var shown: Bool = false
    @State private var drag: CGSize = .zero
    @State private var topInset: CGFloat = 47

    private var displayName: String {
        profileStore.myProfile?.displayName ?? auth.user?.name ?? "You"
    }

    private var handleOrEmail: String? {
        if let handle = profileStore.myProfile?.handle { return handle }
        if let email = auth.user?.email, !email.isEmpty { return email }
        return nil
    }

    private var photoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var initials: String {
        let value = profileStore.myProfile?.initials ?? auth.user?.initials ?? ""
        return value.isEmpty ? "?" : value
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(300, geo.size.width - 28)

            ZStack(alignment: .topTrailing) {
                backdrop

                card
                    .frame(width: cardWidth)
                    .padding(.trailing, 12)
                    .padding(.top, topInset + 44)
                    .scaleEffect(shown ? 1 : 0.86, anchor: .topTrailing)
                    .opacity(shown ? 1 : 0)
                    .offset(x: drag.width, y: drag.height + (shown ? 0 : -10))
                    .gesture(dragGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .task {
            Log.app.debug("profile: quick card mounted")
            topInset = Self.keyWindowTopInset()
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) { shown = true }
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.12)
        }
        .opacity(shown ? 1 : 0)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { close(routingTo: nil) }
        .accessibilityLabel("Close profile")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            syncedNote
            divider
            shortcuts
            divider
            accountRow
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.paperCream.opacity(0.85)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Theme.textPrimary.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
    }

    private var header: some View {
        Button {
            close(routingTo: .myProfile)
        } label: {
            HStack(spacing: 13) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.serif(19, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(handleOrEmail ?? "Tap to set up your profile")
                        .font(.sans(13, weight: handleOrEmail == nil ? .regular : .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickRowButtonStyle())
        .accessibilityHint("Opens your profile")
    }

    private var avatar: some View {
        ZStack {
            if let photoURL {
                CachedImage(url: photoURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc
                }
            } else {
                initialsDisc
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
    }

    private var initialsDisc: some View {
        ZStack {
            Theme.textPrimary
            Text(initials)
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    private var syncedNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
            Text("Synced to your account")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// Three compact icon tiles — My profile, Friends, and the Proof
    /// library archive. Circles stay reachable from their own surfaces;
    /// the card stays a glance.
    private var shortcuts: some View {
        HStack(spacing: 6) {
            shortcutTile(.myProfile, icon: "person.crop.circle", title: "My profile")
            shortcutTile(.friends, icon: "person.2.fill", title: "Friends", showDot: friendGraph.hasUnseenRequests)
            shortcutTile(.proofLibrary, icon: "photo.stack", title: "Proofs")
            shortcutTile(.help, icon: "questionmark.circle", title: "Help")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private func shortcutTile(
        _ dest: ProfileQuickDestination,
        icon: String,
        title: String,
        showDot: Bool = false
    ) -> some View {
        Button {
            close(routingTo: dest)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(height: 20)
                    if showDot {
                        Circle()
                            .fill(Theme.alertRed)
                            .frame(width: 7, height: 7)
                            .offset(x: 7, y: -3)
                    }
                }
                Text(title)
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.055))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(QuickTileButtonStyle())
        .accessibilityLabel(showDot ? "\(title), new activity" : title)
    }

    private var accountRow: some View {
        Button {
            close(routingTo: .account)
        } label: {
            HStack(spacing: 13) {
                iconCircle("gearshape.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account & settings")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Sign out, delete account, blocked")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                chevron
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickRowButtonStyle())
    }

    // MARK: Small pieces

    private func iconCircle(_ systemName: String) -> some View {
        ZStack {
            Circle().fill(Theme.textPrimary.opacity(0.06))
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 34, height: 34)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: Gestures + dismissal

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only follow upward / rightward drags (toward the corner
                // the card grew from), damped so it feels light.
                let dx = max(0, value.translation.width) * 0.5
                let dy = min(0, value.translation.height) * 0.5
                drag = CGSize(width: dx, height: dy)
            }
            .onEnded { value in
                if value.translation.height < -44 || value.translation.width > 64 {
                    close(routingTo: nil)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                }
            }
    }

    private func close(routingTo dest: ProfileQuickDestination?) {
        guard !isClosing else { return }
        isClosing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.13), completionCriteria: .logicallyComplete) {
            shown = false
            drag = .zero
        } completion: {
            onDismiss(dest)
        }
    }

    /// The key window's top safe-area inset. Read imperatively because
    /// the hosting screens deliberately ignore the top safe area, which
    /// zeroes a GeometryReader-derived inset.
    private static func keyWindowTopInset() -> CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
        return inset > 0 ? inset : 47
    }
}

// MARK: - Row button style

/// A faint press wash + subtle scale so each row feels tactile inside the
/// otherwise static card.
private struct QuickRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.textPrimary.opacity(configuration.isPressed ? 0.06 : 0))
                    .padding(.horizontal, 6)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Press feedback for the compact shortcut tiles — a quick sink that
/// reads as a tap on a physical key.
private struct QuickTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Destination sheets

/// Routes a quick-card selection to its full surface. Each focused screen
/// is wrapped in its own `NavigationStack` with a close control; the
/// account hub brings its own. `myProfile` never lands here — it
/// presents full-screen from the modifier — but the case stays
/// exhaustive for safety.
private struct ProfileQuickDestinationSheet: View {
    let destination: ProfileQuickDestination

    var body: some View {
        switch destination {
        case .myProfile:
            MyProfileView()
        case .editProfile:
            QuickNavSheet(closePlacement: .topBarLeading, closeTitle: "Cancel") {
                EditProfileView()
            }
        case .friends:
            QuickNavSheet(closePlacement: .topBarTrailing, closeTitle: "Done") {
                FriendsView()
            }
        case .proofLibrary:
            QuickNavSheet(closePlacement: .topBarTrailing, closeTitle: "Done") {
                ProofLibraryView()
            }
        case .account:
            ProfileSheetView()
        case .help:
            // "How FrisFocus moves" — the home header's old "?" chip,
            // now living where every other me-shaped thing lives.
            HowItMovesSheet()
        }
    }
}

/// Wraps a pushable screen in a `NavigationStack` with a single close
/// button, so it presents cleanly as a sheet from the quick card.
private struct QuickNavSheet<Content: View>: View {
    let closePlacement: ToolbarItemPlacement
    let closeTitle: String
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: closePlacement) {
                        Button(closeTitle) { dismiss() }
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
        }
    }
}
