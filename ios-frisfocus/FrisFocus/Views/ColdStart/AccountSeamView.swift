//
//  AccountSeamView.swift
//  FrisFocus
//
//  The get-started seam, shown after the cold-start season is saved and
//  before the person starts tracking. Four warm steps:
//
//    1. People card    — the invitation (choose your people, private by
//                        default, nothing public); leads the seam.
//    2. Save your start — one-tap Apple / Google sign-in that attaches the
//                        season they just built (required).
//    3. Claim your name — a friendly, can't-fail @handle (+ optional photo)
//    4. Bring your people — three optional invite routes (share link,
//                        username search, opt-in contacts).
//
//  The dawn sky carries through from the cold start: pre-dawn violet on
//  the people card + sign-in warming to bright cream on the name and
//  invite steps, with two suns rising together (friends' seasons side by
//  side) as a quiet progress cue. On finish the parent drops the
//  first-run cover and the person lands on their live home.
//
//  "Not now" on the people card sets `skippedPeople`, so the seam hops
//  straight from name-claim to home — invites stay reachable later from
//  the People page. Bail-safety is preserved throughout: the season is
//  already frozen locally before this seam appears.
//

import SwiftUI
import AuthenticationServices

struct AccountSeamView: View {
    /// Land on the live home with the saved board.
    let onFinish: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .peopleCard
    /// True while we resolve whether a freshly signed-in person is a
    /// returning user (skip straight home) or new (walk the seam).
    @State private var resolving: Bool = false
    /// Set when the person taps "Not now" on the people card — the seam
    /// then skips the invite step and lands on home after name-claim.
    @State private var skippedPeople: Bool = false

    enum Step: Int { case peopleCard, save, name, invite }

    var body: some View {
        ZStack {
            TwoSunsBackdrop(progress: sunProgress, warmth: warmth)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: warmth)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: sunProgress)

            switch step {
            case .peopleCard:
                PeopleCardStep(
                    onContinue: { advance(to: .save) },
                    onSkip: {
                        skippedPeople = true
                        advance(to: .save)
                    }
                )
                .transition(stageTransition)
            case .save:
                SaveYourStartStep(resolving: resolving)
                    .transition(stageTransition)
            case .name:
                ClaimNameStep(onContinue: {
                    // Honor an earlier "Not now" — skip invites entirely.
                    if skippedPeople { onFinish() } else { advance(to: .invite) }
                })
                    .transition(stageTransition)
            case .invite:
                BringPeopleStep(onFinish: onFinish)
                    .transition(stageTransition)
            }
        }
        // Sign-in success on the save step: decide where to go.
        .onChange(of: auth.user?.id) { _, newId in
            guard step == .save, let newId else { return }
            resolveAfterSignIn(userId: newId)
        }
    }

    // MARK: Routing

    /// A returning user (already has a claimed @handle) skips straight to
    /// their restored home; a new account walks the name + invite steps.
    private func resolveAfterSignIn(userId: String) {
        resolving = true
        Task {
            await profileStore.load(myUserId: userId)
            let hasHandle = (profileStore.myProfile?.username?.isEmpty == false)
            resolving = false
            if hasHandle {
                onFinish()
            } else {
                advance(to: .name)
            }
        }
    }

    private func advance(to next: Step) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            step = next
        }
    }

    private var sunProgress: Double {
        Double(step.rawValue) / 3.0
    }

    /// 0 = dark pre-dawn (people card / sign-in), 1 = bright cream
    /// (name / invite).
    private var warmth: Double {
        (step == .peopleCard || step == .save) ? 0 : 1
    }

    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99))
    }
}

// MARK: - Two-suns backdrop

/// A dawn sky with two suns rising side by side over a shared horizon.
/// `warmth` crossfades from pre-dawn violet to the app's warm cream;
/// `progress` (0…1) lifts and brightens both suns across the seam.
private struct TwoSunsBackdrop: View {
    var progress: Double
    var warmth: Double

    var body: some View {
        let p = max(0, min(1, progress))
        let w = max(0, min(1, warmth))

        ZStack {
            // Sky: violet pre-dawn → warm cream as the seam progresses.
            LinearGradient(
                colors: [
                    Color.lerpHSL(Color(hex: 0x241B3A), Theme.warmWheat, t: w),
                    Color.lerpHSL(Color(hex: 0x4A3357), Theme.warmWheat, t: w),
                    Color.lerpHSL(Color(hex: 0x8E5A4E), Theme.paperCream, t: w)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                // Two suns, slightly apart, both cresting the horizon and
                // rising with progress. They warm and brighten too.
                ForEach(0..<2, id: \.self) { i in
                    let dx: CGFloat = i == 0 ? -0.16 : 0.16
                    RadialGradient(
                        colors: [
                            Theme.sunCore.opacity(0.45 + 0.4 * p),
                            Theme.sunWarm.opacity(0.16 + 0.1 * w),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 200
                    )
                    .frame(width: 380, height: 380)
                    .position(
                        x: width * (0.5 + dx),
                        y: height * (0.9 - 0.12 * p)
                    )
                    .blur(radius: 6)
                }
            }
        }
    }
}

// MARK: - Step 1: Save your start

/// One-tap Apple / Google sign-in over the dark pre-dawn sky. Required —
/// there's no skip here. Frames the why through both the social value and
/// the privacy promise in one breath.
private struct SaveYourStartStep: View {
    /// True while we check whether the just-signed-in person is returning.
    let resolving: Bool

    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false
    @State private var legalDoc: LegalDocument?

    var body: some View {
        @Bindable var auth = auth
        return VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 104, height: 104)
                HStack(spacing: -10) {
                    sunGlyph(size: 40, opacity: 0.85)
                    sunGlyph(size: 52, opacity: 1)
                }
            }
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .padding(.bottom, 28)

            VStack(spacing: 16) {
                EyebrowText(text: "SAVE YOUR START", opacity: 0.8, color: Theme.textCream)

                Text("Keep what\nyou just built.")
                    .font(.serif(33, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                privacyCopy
                    .padding(.horizontal, 8)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    Task { await auth.signIn(provider: "apple") }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(auth.isSigningIn || resolving)

                googleButton

                Text(.init("By continuing you agree to our [Terms of Use](frisfocus://legal/terms) and [Privacy Policy](frisfocus://legal/privacy)."))
                    .font(.sans(11.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.6))
                    .tint(Theme.textCream.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.absoluteString.hasSuffix("terms") { legalDoc = .terms; return .handled }
                        if url.absoluteString.hasSuffix("privacy") { legalDoc = .privacy; return .handled }
                        return .systemAction
                    })
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .overlay(alignment: .top) {
                if auth.isSigningIn || resolving {
                    ProgressView()
                        .tint(Theme.textCream)
                        .padding(.top, -28)
                }
            }

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82)) {
                shown = true
            }
        }
        .alert("Sign in failed", isPresented: $auth.showError) {
            Button("OK") {}
        } message: {
            Text(auth.errorMessage)
        }
        .sheet(item: $legalDoc) { doc in
            NavigationStack {
                LegalView(document: doc)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { legalDoc = nil }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
    }

    private var privacyCopy: some View {
        VStack(spacing: 10) {
            Text("FrisFocus lets friends keep up with each other's seasons — ")
                .foregroundStyle(Theme.textCream.opacity(0.85))
            + Text("as much or as little as you choose to share.")
                .foregroundStyle(Theme.textCream)
                .fontWeight(.semibold)

            Text("Your day's shape is all anyone sees ")
                .foregroundStyle(Theme.textCream.opacity(0.85))
            + Text("unless you say otherwise.")
                .foregroundStyle(Theme.textCream)
                .fontWeight(.semibold)
        }
        .font(.serifItalic(15.5, weight: .regular))
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
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
            .frame(height: 54)
            .background(Theme.textCream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn || resolving)
    }

    private func sunGlyph(size: CGFloat, opacity: Double) -> some View {
        Image(systemName: "sun.and.horizon.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(Theme.sunCore, Theme.sunWarm)
            .symbolRenderingMode(.palette)
            .opacity(opacity)
    }
}
