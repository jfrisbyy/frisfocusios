//
//  HeaderStudioView.swift
//  FrisFocus
//
//  The full-screen header studio — not a settings form. The user
//  swipes through header options (their own photo first, then the
//  crafted sky palettes) rendered exactly as friends will see them:
//  season title carved in, identity card floating below, living
//  light. A strong-day / quiet-day toggle previews both moods of the
//  header before one clear save.
//

import SwiftUI
import PhotosUI
import UIKit

/// Identifiable wrapper so `fullScreenCover(item:)` can present the
/// header framing screen for a freshly picked image.
private struct StudioCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct HeaderStudioView: View {
    @Environment(Store.self) private var store
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// Lets a host (Edit profile) mirror the saved cover into its own
    /// local state so a later save there doesn't revert the choice.
    var onSaved: ((String?) -> Void)? = nil

    /// Tab selection — "photo" or a `SeasonCoverKind` raw value.
    @State private var selection: String = "photo"
    @State private var strongPreview: Bool = true
    @State private var photoItem: PhotosPickerItem?
    @State private var cropTarget: StudioCropTarget?
    @State private var croppedHeader: UIImage?
    @State private var isSaving: Bool = false
    @State private var didLoad: Bool = false

    private var myId: String? { auth.user?.id }

    private var accent: Color {
        if let chosen = store.currentSeason.accentHex { return Color(hex: chosen) }
        if let myId { return Color(hex: RemoteIDMapper.accentHex(forRemoteId: myId)) }
        return Theme.textPrimary
    }

    private var previewStrength: Double { strongPreview ? 0.92 : 0.08 }

    private var displayName: String {
        profileStore.myProfile?.displayName ?? auth.user?.name ?? "You"
    }

    private var photoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var currentHeaderURL: URL? { profileStore.myProfile?.headerURL }

    private var hasPhoto: Bool { croppedHeader != nil || currentHeaderURL != nil }

    private var selectionTitle: String {
        if selection == "photo" {
            return hasPhoto ? "Your photo" : "Your color"
        }
        return SeasonCoverKind(rawValue: selection)?.displayName ?? ""
    }

    var body: some View {
        ZStack {
            Color(hex: 0x16140F).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                TabView(selection: $selection) {
                    previewPage(coverId: nil)
                        .tag("photo")
                    ForEach(SeasonCoverKind.allCases) { kind in
                        previewPage(coverId: kind.rawValue)
                            .tag(kind.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: selection)

                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selection = store.currentSeason.coverId ?? "photo"
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedPhoto(newItem) }
        }
        .fullScreenCover(item: $cropTarget) { target in
            ProfileHeaderCropView(image: target.image) { baked in
                croppedHeader = baked
                selection = "photo"
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Your header")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            // Mirror the cancel width so the title stays centered.
            Text("Cancel")
                .font(.sans(15, weight: .regular))
                .hidden()
        }
    }

    // MARK: - Preview page

    /// One swipeable option, rendered as the real profile hero: the
    /// header base with its living light, the season carved in, and
    /// the identity card floating over the seam.
    private func previewPage(coverId: String?) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        previewBackground(coverId: coverId)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("CURRENTLY IN")
                                .font(.sans(10, weight: .semibold))
                                .tracking(2.2)
                                .foregroundStyle(Theme.textCream.opacity(0.75))
                            Text(store.currentSeason.name.replacingOccurrences(of: " Season", with: ""))
                                .font(.serif(30, weight: .medium))
                                .foregroundStyle(Theme.textCream)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                            Text(store.seasonDayTextCaps)
                                .font(.sans(10, weight: .semibold))
                                .tracking(2)
                                .foregroundStyle(Theme.textCream.opacity(0.85))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 56)
                    }
                    .frame(height: 320)
                    .clipped()

                    Theme.warmWheat
                        .frame(height: 110)
                }

                miniIdentityCard
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 18)

            // Photo option affordances under the preview.
            if coverId == nil {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 7) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.sans(13, weight: .semibold))
                        Text(hasPhoto ? "Replace & reframe photo" : "Choose a photo")
                            .font(.sans(14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule(style: .continuous).fill(.white.opacity(0.14)))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            } else {
                Color.clear.frame(height: 14 + 40)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func previewBackground(coverId: String?) -> some View {
        ZStack {
            if coverId == nil, let croppedHeader {
                accent
                Color.clear
                    .overlay {
                        Image(uiImage: croppedHeader)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                // Same living-light treatment the real hero applies.
                if previewStrength > 0.55 {
                    RadialGradient(
                        colors: [Color(hex: 0xFFD27A).opacity(0.30), .clear],
                        center: .init(x: 0.7, y: 0.25),
                        startRadius: 0,
                        endRadius: 320
                    )
                    .blendMode(.screen)
                } else {
                    Color.black.opacity(0.12)
                }
            } else {
                ProfilePosterBackground(
                    coverId: coverId,
                    headerURL: coverId == nil ? currentHeaderURL : nil,
                    accent: accent,
                    strength: previewStrength
                )
            }

            // Readability scrims, matching the real hero.
            LinearGradient(
                colors: [Color.black.opacity(0.40), Color.black.opacity(0.12), Color.black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.5), value: strongPreview)
    }

    /// The floating identity card, scaled down — real name and avatar
    /// so the preview is judged against the true page.
    private var miniIdentityCard: some View {
        HStack(spacing: 12) {
            ZStack {
                if let photoURL {
                    CachedImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        miniInitials
                    }
                } else {
                    miniInitials
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(store.lifetimeDaysShownUp) days shown up")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0xFFFBF1))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
        .allowsHitTesting(false)
    }

    private var miniInitials: some View {
        ZStack {
            Circle().fill(accent)
            Text(String(displayName.prefix(1)).uppercased())
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            Text(selectionTitle.uppercased())
                .font(.sans(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.65))
                .animation(nil, value: selection)

            pageDots

            moodToggle

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Text("Use this header")
                            .font(.sans(16, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            dot(isOn: selection == "photo")
            ForEach(SeasonCoverKind.allCases) { kind in
                dot(isOn: selection == kind.rawValue)
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(isOn: Bool) -> some View {
        Circle()
            .fill(.white.opacity(isOn ? 0.95 : 0.3))
            .frame(width: isOn ? 7 : 5.5, height: isOn ? 7 : 5.5)
            .animation(.easeOut(duration: 0.2), value: isOn)
    }

    /// Strong-day / quiet-day preview switch — both moods of the
    /// header before saving.
    private var moodToggle: some View {
        HStack(spacing: 6) {
            moodSegment("Strong day", icon: "sun.max.fill", isOn: strongPreview) {
                strongPreview = true
            }
            moodSegment("Quiet day", icon: "moon.fill", isOn: !strongPreview) {
                strongPreview = false
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.10)))
    }

    private func moodSegment(_ title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.4)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.sans(11, weight: .semibold))
                Text(title)
                    .font(.sans(13, weight: .semibold))
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? .white : .clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview on a \(title.lowercased())")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Actions

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            cropTarget = StudioCropTarget(image: image)
        }
        photoItem = nil
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let chosenCover: String? = selection == "photo" ? nil : selection

        // A freshly framed photo uploads first so the header URL is
        // live before friends re-read the profile.
        if let croppedHeader, let myId {
            guard let url = await profileStore.uploadHeader(croppedHeader, myUserId: myId) else { return }
            let ok = await profileStore.save(
                name: profileStore.myProfile?.name ?? auth.user?.name ?? "",
                username: profileStore.myProfile?.username,
                email: auth.user?.email,
                avatarUrl: profileStore.myProfile?.avatarUrl ?? auth.user?.picture,
                header: .set(url),
                myUserId: myId
            )
            guard ok else { return }
        }

        store.setSeasonCover(coverId: chosenCover)
        onSaved?(chosenCover)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
