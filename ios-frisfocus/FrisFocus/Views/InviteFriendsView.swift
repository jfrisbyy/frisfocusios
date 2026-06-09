//
//  InviteFriendsView.swift
//  FrisFocus
//
//  Your personal doorway for bringing friends in: a one-tap Share of
//  your invite link, a scannable code for adding someone in person, and
//  a copy-link fallback. Tapping the link (or scanning the code) opens
//  FrisFocus straight to your profile with an Add control.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct InviteFriendsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore

    @State private var qrImage: UIImage?
    @State private var didCopy: Bool = false

    private var myId: String? { auth.user?.id }
    private var inviteURL: URL? { myId.flatMap { InviteLink.url(forUserId: $0) } }

    private var displayName: String {
        profileStore.myProfile?.name ?? auth.user?.name ?? "You"
    }
    private var handle: String? { profileStore.myProfile?.handle }

    private var shareMessage: String {
        if let handle {
            return "I'm on FrisFocus as \(handle) — add me and let's keep each other going."
        }
        return "I'm on FrisFocus — add me and let's keep each other going."
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                intro
                qrCard
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .background(Theme.warmWheat.ignoresSafeArea())
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { renderQRIfNeeded() }
    }

    // MARK: - Pieces

    private var intro: some View {
        VStack(spacing: 8) {
            Text("BRING A FRIEND")
                .font(.sans(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text("Add me on FrisFocus")
                .font(.serif(25, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Share your link or let a friend scan your code. They'll open straight to your profile.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
    }

    private var qrCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 176, height: 176)
                } else {
                    ProgressView().tint(Theme.textTertiary)
                }
            }

            VStack(spacing: 3) {
                Text(displayName)
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let handle {
                    Text(handle)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if let inviteURL {
                ShareLink(
                    item: inviteURL,
                    subject: Text("Add me on FrisFocus"),
                    message: Text(shareMessage)
                ) {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Share invite link")
                            .font(.sans(16, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                })

                Button {
                    UIPasteboard.general.url = inviteURL
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: didCopy ? "checkmark" : "link")
                            .font(.system(size: 15, weight: .semibold))
                        Text(didCopy ? "Link copied" : "Copy link")
                            .font(.sans(16, weight: .medium))
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
            } else {
                Text("Sign in to get your invite link.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - QR

    private func renderQRIfNeeded() {
        guard qrImage == nil, let inviteURL else { return }
        qrImage = Self.makeQRCode(from: inviteURL.absoluteString)
    }

    /// Build a crisp QR image from a string using CoreImage.
    private static func makeQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    NavigationStack {
        InviteFriendsView()
            .environment(AuthManager())
            .environment(ProfileStore())
    }
}
