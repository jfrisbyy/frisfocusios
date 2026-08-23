//
//  FirstRunIntroView.swift
//  FrisFocus
//
//  The first-launch welcome. A single warm panel that sets the tone
//  (the sun = your day), then drops straight into the 60-second cold
//  start: pick a direction → build a real board → land on home with the
//  sun low, ready for the first check.
//
//  A quiet "Already have an account? Sign in" link restores returning
//  users. Shown only while the Store sits in `.uninitialized` — the only
//  ways forward are building a season (then required sign-in) or signing
//  straight in.
//

import SwiftUI
import AuthenticationServices

struct FirstRunIntroView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .welcome
    @State private var showSignIn: Bool = false
    /// The directions-only envelope captured when the person forks into
    /// the conversation from the direction pick.
    @State private var forkContext: ColdStartContext?
    /// True while a fork is waiting on sign-in (the conversation needs an
    /// account); on success we drop straight into it.
    @State private var pendingFork: Bool = false

    private enum Phase { case welcome, manifesto, coldStart, forkSetup, account }

    var body: some View {
        @Bindable var auth = auth
        return ZStack {
            switch phase {
            case .welcome:
                ZStack {
                    DawnBackdrop(progress: 0).ignoresSafeArea()
                    WelcomePanel(
                        onStart: { advance(to: .manifesto) },
                        onSignIn: { showSignIn = true }
                    )
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))

            case .manifesto:
                ManifestoView(
                    onContinue: { advance(to: .coldStart) },
                    onSkip: { advance(to: .coldStart) }
                )
                .transition(.opacity)

            case .coldStart:
                ColdStartFlowView(
                    onComplete: { result in
                        // Freeze the complete season on the device now
                        // (flips appMode to .clean and raises
                        // `accountSeamActive`, which keeps this cover up),
                        // then walk the account seam.
                        store.commitColdStart(result)
                        advance(to: .account)
                    },
                    onBack: { advance(to: .welcome) },
                    onTalkItThrough: { context in
                        forkContext = context
                        // The conversation needs an account; if they're not
                        // signed in yet, gate on sign-in, then fork.
                        if auth.user?.id != nil {
                            advance(to: .forkSetup)
                        } else {
                            pendingFork = true
                            showSignIn = true
                        }
                    }
                )
                .transition(.opacity)

            case .forkSetup:
                // The season conversation, warm-started with their chosen
                // directions. On finish it has built their one real season
                // in place — hand off to the account seam like the board path.
                SeasonSetupFlowView(
                    coldStartContext: forkContext,
                    onFinished: {
                        store.finalizeConversationColdStart()
                        advance(to: .account)
                    }
                )
                .transition(.opacity)

            case .account:
                AccountSeamView(
                    onFinish: {
                        // Drop the cover → land on the live home with the
                        // saved board, ready for the first check.
                        store.accountSeamActive = false
                    }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
                .environment(auth)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: auth.user?.id) { _, newId in
            if newId != nil {
                showSignIn = false
                if pendingFork {
                    pendingFork = false
                    advance(to: .forkSetup)
                }
            }
        }
        .alert("Sign in failed", isPresented: $auth.showError) {
            Button("OK") {}
        } message: {
            Text(auth.errorMessage)
        }
    }

    private func advance(to next: Phase) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            phase = next
        }
    }
}

// MARK: - Welcome panel

private struct WelcomePanel: View {
    let onStart: () -> Void
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

                Text("Pick what you're focused on and start tracking real tasks in about a minute. The sun rises as your day fills.")
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

// MARK: - Sign-in sheet

/// A compact sign-in surface for returning users, mirroring the
/// Apple / Google buttons used in the account hub. On success the
/// Store's `restoreFromSignIn()` (wired in ContentView) moves the app
/// out of `.uninitialized` and the welcome cover dismisses straight
/// onto the restored home.
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
