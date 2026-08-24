//
//  AccountSeamView.swift
//  FrisFocus
//
//  The account beats of the onboarding flow, in master order: sign-in
//  comes right after the manifesto and BEFORE any season exists. This
//  file holds the shared two-suns dawn backdrop and the one-tap
//  Apple / Google sign-in step; the flow itself lives in
//  FirstRunIntroView, which sequences:
//
//    manifesto → AccountSignInStep → ClaimNameStep → the fork →
//    [quick or deep path] → PeopleCardStep → BringPeopleStep → home.
//
//  No OS permission dialogs anywhere in this flow — notifications are
//  offered later, on the first deliverable social event, behind a soft
//  prime card on the home.
//

import SwiftUI
import AuthenticationServices

// MARK: - Two-suns backdrop

/// A dawn sky with two suns rising side by side over a shared horizon.
/// `warmth` crossfades from pre-dawn violet to the app's warm cream;
/// `progress` (0…1) lifts and brightens both suns across the seam.
struct TwoSunsBackdrop: View {
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
                    .frame(width: min(380, width), height: min(380, width))
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

// MARK: - Account sign-in step

/// One-tap Apple / Google sign-in over the dark pre-dawn sky, shown
/// BEFORE any season exists. Required — there's no skip here. Frames
/// the why through the social value and the privacy promise in one
/// breath. Terms / Privacy open in-app.
struct AccountSignInStep: View {
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
                EyebrowText(text: "MAKE IT YOURS", opacity: 0.8, color: Theme.textCream)

                Text("One account,\nevery season kept.")
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
            Text("Your seasons live on your account — ")
                .foregroundStyle(Theme.textCream.opacity(0.85))
            + Text("this phone today, any phone tomorrow.")
                .foregroundStyle(Theme.textCream)
                .fontWeight(.semibold)

            Text("Nothing you build here is public, ")
                .foregroundStyle(Theme.textCream.opacity(0.85))
            + Text("and nothing is shared until you choose.")
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
