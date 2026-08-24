//
//  FirstRunIntroView.swift
//  FrisFocus
//
//  The one continuous onboarding flow, in master order:
//
//    Welcome → Manifesto (4 cards) → Account (sign-in → claim name) →
//    THE FORK → [quick path | deep path] → People card → Invites → Home.
//
//  The fork doubles as the authenticated-no-season landing forever
//  (ContentView re-presents this cover at `.fork` whenever a signed-in
//  person has no season). Kill-safe: every phase persists a marker and
//  a relaunch resumes at the last completed phase — the quick path's
//  board draft and the deep path's conversation each restore their own
//  inner state on top.
//
//  No OS permission dialogs live anywhere in this flow. Notifications
//  are offered later, on the first deliverable social event, behind a
//  soft prime card on the home.
//

import SwiftUI
import AuthenticationServices

// MARK: - Kill-safe outer phase marker

/// Remembers WHICH room of the onboarding flow the person was in, so a
/// force-quit resumes there. The quick path's board and the deep path's
/// conversation persist their own inner state separately.
enum OnboardingProgress {
    enum Marker: String {
        case welcome, manifesto, account, claimName, fork, quickPath, deepPath
    }

    private static let key = "onboarding.phase.v1"

    static func save(_ marker: Marker) {
        UserDefaults.standard.set(marker.rawValue, forKey: key)
    }

    static func restore() -> Marker? {
        UserDefaults.standard.string(forKey: key).flatMap(Marker.init(rawValue:))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Flow

struct FirstRunIntroView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(SeasonSyncService.self) private var seasonSync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .welcome
    @State private var showSignIn: Bool = false
    /// True while a fresh sign-in resolves (profile + cloud season check).
    @State private var resolving: Bool = false
    @State private var didResolveEntry: Bool = false

    private enum Phase {
        case welcome, manifesto, account, claimName, fork, quickPath, deepPath, peopleCard, invites
    }

    var body: some View {
        @Bindable var auth = auth
        return ZStack {
            switch phase {
            case .welcome:
                ZStack {
                    DawnBackdrop(progress: 0).ignoresSafeArea()
                    WelcomePanel(
                        onStart: { advance(to: .manifesto) },
                        onDemo: {
                            OnboardingProgress.clear()
                            store.startDemo()
                        },
                        onSignIn: { showSignIn = true }
                    )
                }
                .transition(stageTransition)

            case .manifesto:
                ManifestoView(
                    onContinue: { advance(to: .account) },
                    onSkip: { advance(to: .account) }
                )
                .transition(.opacity)

            case .account:
                ZStack {
                    TwoSunsBackdrop(progress: 0.15, warmth: 0).ignoresSafeArea()
                    AccountSignInStep(resolving: resolving)
                }
                .transition(stageTransition)

            case .claimName:
                ZStack {
                    TwoSunsBackdrop(progress: 0.45, warmth: 1).ignoresSafeArea()
                    ClaimNameStep(onContinue: { advance(to: .fork) })
                }
                .transition(stageTransition)

            case .fork:
                ZStack {
                    DawnBackdrop(progress: 0.3).ignoresSafeArea()
                    ForkView(
                        onQuick: { advance(to: .quickPath) },
                        onDeep: { advance(to: .deepPath) }
                    )
                }
                .transition(stageTransition)

            case .quickPath:
                ColdStartFlowView(
                    onComplete: { result in
                        // Freeze the complete season on the device now
                        // (raises the persisted seam), then walk the
                        // people-card + invite beats.
                        store.commitColdStart(result)
                        advance(to: .peopleCard)
                    },
                    onBack: { advance(to: .fork) }
                )
                .transition(.opacity)

            case .deepPath:
                SeasonSetupFlowView(
                    startInResume: SeasonSetupResumeStore.hasSaved,
                    coldStartContext: nil,
                    onFinished: {
                        store.finalizeConversationColdStart()
                        advance(to: .peopleCard)
                    },
                    onExit: { advance(to: .fork) }
                )
                .transition(.opacity)

            case .peopleCard:
                ZStack {
                    TwoSunsBackdrop(progress: 0.7, warmth: 0).ignoresSafeArea()
                    PeopleCardStep(
                        onContinue: {
                            store.setSeamPhase("invites")
                            advance(to: .invites)
                        },
                        onSkip: { finish() }
                    )
                }
                .transition(stageTransition)

            case .invites:
                ZStack {
                    TwoSunsBackdrop(progress: 1, warmth: 1).ignoresSafeArea()
                    BringPeopleStep(onFinish: { finish() })
                }
                .transition(stageTransition)
            }

            // A quiet resolve state after any sign-in outside the account
            // step (welcome link, entry restore) — never a dead screen.
            if resolving && phase != .account {
                ResolvingAccountOverlay()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
                .environment(auth)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: auth.user?.id) { _, newId in
            guard newId != nil else { return }
            showSignIn = false
            if phase == .welcome || phase == .account {
                handleSignInSuccess()
            }
        }
        .alert("Sign in failed", isPresented: $auth.showError) {
            Button("OK") {}
        } message: {
            Text(auth.errorMessage)
        }
        .onAppear { resolveEntry() }
    }

    // MARK: Entry (cold launch / re-present)

    /// Decide where this cover opens: resumed seam beats, the fork
    /// landing for an authenticated-no-season state, a mid-onboarding
    /// relaunch, or the very top of the flow.
    private func resolveEntry() {
        guard !didResolveEntry else { return }
        didResolveEntry = true

        // Post-commit beats survive force-quits.
        if store.accountSeamActive {
            phase = store.persistedSeamPhase == "invites" ? .invites : .peopleCard
            return
        }

        // Authenticated-no-season landing (ContentView only raises the
        // cover in `.clean` when signed in with no season): the fork.
        if store.appMode == .clean {
            phase = .fork
            return
        }

        // Mid-onboarding relaunch with a live session.
        if auth.user != nil {
            switch OnboardingProgress.restore() {
            case .quickPath:
                phase = .quickPath   // the board draft restores itself
            case .deepPath:
                phase = .deepPath    // the conversation restores itself
            default:
                // Re-resolve honestly: existing season → home; a handle
                // but no season → fork; no handle yet → claim name.
                handleSignInSuccess()
            }
            return
        }

        // Signed out: resume at the last completed pre-account beat.
        switch OnboardingProgress.restore() {
        case .manifesto:
            phase = .manifesto
        case .account, .claimName, .fork, .quickPath, .deepPath:
            phase = .account
        default:
            phase = .welcome
        }
    }

    // MARK: Sign-in resolution

    /// After any successful sign-in: load the profile, give the cloud
    /// season a moment to restore, then route — existing season skips
    /// everything; a claimed handle lands at the fork; otherwise claim.
    private func handleSignInSuccess() {
        guard !resolving else { return }
        resolving = true
        Task {
            if let myId = auth.user?.id {
                await profileStore.load(myUserId: myId)
            }
            await waitForSeasonRestore()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                resolving = false
            }
            let hasSeason = !store.currentSeason.name.isEmpty
            let hasHandle = (profileStore.myProfile?.username?.isEmpty == false)
            if hasSeason {
                // Existing cloud season → straight to the live home.
                OnboardingProgress.clear()
                store.restoreFromSignIn()
            } else if hasHandle {
                advance(to: .fork)
            } else {
                advance(to: .claimName)
            }
        }
    }

    /// Wait (bounded) for the account's cloud restore to have had its
    /// say, so "no season" is a fact and not a race.
    private func waitForSeasonRestore() async {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if !store.currentSeason.name.isEmpty { return }
            if seasonSync.hasAttemptedRestore && !seasonSync.isRestoring { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: Advancing

    private func advance(to next: Phase) {
        if let marker = marker(for: next) {
            OnboardingProgress.save(marker)
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            phase = next
        }
    }

    private func marker(for phase: Phase) -> OnboardingProgress.Marker? {
        switch phase {
        case .welcome: return .welcome
        case .manifesto: return .manifesto
        case .account: return .account
        case .claimName: return .claimName
        case .fork: return .fork
        case .quickPath: return .quickPath
        case .deepPath: return .deepPath
        case .peopleCard, .invites: return nil   // carried by the seam key
        }
    }

    /// The flow is complete — drop the cover onto the live home.
    private func finish() {
        store.finishOnboardingSeam()
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99))
    }
}

// MARK: - Welcome panel

private struct WelcomePanel: View {
    let onStart: () -> Void
    let onDemo: () -> Void
    let onSignIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 112, height: 112)
                Image(systemName: "sun.and.horizon.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Theme.sunCore, Theme.sunWarm)
                    .symbolRenderingMode(.palette)
            }
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .padding(.bottom, 30)

            VStack(spacing: 16) {
                EyebrowText(text: "WELCOME TO FRISFOCUS", opacity: 0.8, color: Theme.textCream)

                Text("Your day,\nlit by what you do.")
                    .font(.serif(34, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("An honest record of your life — the sun rises as your day fills. Set up takes about a minute.")
                    .font(.serifItalic(16.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onStart()
                } label: {
                    HStack(spacing: 10) {
                        Text("Get started")
                            .font(.sans(17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.textCream)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDemo()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .medium))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Explore a demo first")
                                .font(.sans(15.5, weight: .semibold))
                            Text("A sample life you can leave anytime")
                                .font(.sans(12, weight: .regular))
                                .opacity(0.72)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.textCream)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.textCream.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSignIn()
                } label: {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundStyle(Theme.textCream.opacity(0.7))
                        Text("Sign in")
                            .foregroundStyle(Theme.textCream)
                            .fontWeight(.semibold)
                    }
                    .font(.sans(13.5, weight: .regular))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82)) {
                shown = true
            }
        }
    }
}

// MARK: - Resolving overlay

/// Shown while a fresh sign-in is being resolved outside the account
/// step — a calm beat, never a dead screen.
private struct ResolvingAccountOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Theme.textPrimary)
                Text("One moment — checking your account…")
                    .font(.sans(13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.paperCream)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
    }
}

// MARK: - Sign-in sheet

/// A compact sign-in surface for returning users, mirroring the
/// Apple / Google buttons used in the account hub. On success the flow
/// resolves: an existing cloud season lands straight on the restored
/// home; no season lands at the fork.
private struct SignInSheet: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                EyebrowText(text: "WELCOME BACK", opacity: 0.5)

                Text("Sign in to restore\nyour seasons")
                    .font(.serif(25, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your season, journal, circles, and friends sync back to this device.")
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    Task { await auth.signIn(provider: "apple") }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(auth.isSigningIn)

                googleButton
            }
            .padding(.top, 28)
            .overlay(alignment: .top) {
                if auth.isSigningIn {
                    ProgressView()
                        .tint(Theme.textPrimary)
                        .padding(.top, -26)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.warmWheat)
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signIn(provider: "google") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                Text("Continue with Google")
                    .font(.sans(17, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.textPrimary.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn)
    }
}

#Preview {
    FirstRunIntroView()
        .environment(AuthManager())
        .environment(Store())
}
