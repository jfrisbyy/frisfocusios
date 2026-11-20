//
//  AppleSignInButton.swift
//  FrisFocus
//
//  The one "Continue with Apple" button, shared by every sign-in
//  surface. Sign in with Apple runs through the same web OAuth flow as
//  Google (`AuthManager.signIn(provider:)`), so this is a plain Button
//  drawn to Apple's Human Interface Guidelines — solid black or white,
//  the Apple logo, system type — rather than AuthenticationServices'
//  `SignInWithAppleButton`, which would fire a native Apple ID request
//  this app has no entitlement for and whose result was never used.
//
//  It takes the height and corner radius of the buttons it sits beside,
//  so it is always at least as prominent as the Google button under it.
//

import SwiftUI

struct AppleSignInButton: View {
    /// Apple's two solid styles. `.black` for light surfaces, `.white`
    /// for dark or coloured ones.
    enum Style {
        case black
        case white
    }

    var style: Style = .black
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 14
    let action: () -> Void

    private var fillColor: Color {
        style == .black ? Color.black : Color.white
    }

    private var contentColor: Color {
        style == .black ? Color.white : Color.black
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                Text("Continue with Apple")
                    .font(.system(size: 19, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(contentColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
