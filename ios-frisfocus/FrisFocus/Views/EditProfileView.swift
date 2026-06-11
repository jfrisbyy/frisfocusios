//
//  EditProfileView.swift
//  FrisFocus
//
//  Where the user shapes how friends see them: a tappable photo, a
//  display name, and a one-of-a-kind @username checked live as they
//  type. Saving writes through `ProfileStore`, which propagates the new
//  identity everywhere (home avatar, friends, circles, proofs).
//

import SwiftUI
import PhotosUI
import UIKit
import CoreLocation

/// Identifiable wrapper so `fullScreenCover(item:)` can present the
/// header crop screen for a freshly picked image.
private struct HeaderCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Identifiable wrapper for the circular avatar crop screen.
private struct AvatarCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct EditProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var originalUsername: String = ""

    @State private var phone: String = ""
    @State private var originalPhone: String = ""

    @State private var nearYouOn: Bool = false
    @State private var nearYouBusy: Bool = false
    @State private var nearYouHint: String?
    @State private var location = LocationService()

    @State private var photoItem: PhotosPickerItem?
    @State private var avatarCropTarget: AvatarCropTarget?
    @State private var pickedImage: UIImage?

    @State private var headerPhotoItem: PhotosPickerItem?
    @State private var headerCropTarget: HeaderCropTarget?
    @State private var croppedHeader: UIImage?
    @State private var headerRemoved: Bool = false

    @State private var usernameStatus: UsernameStatus = .idle
    @State private var checkTask: Task<Void, Never>?
    @State private var isUploading: Bool = false
    @State private var didLoad: Bool = false

    private enum UsernameStatus {
        case idle, unchanged, checking, available, taken, invalid
    }

    private var myId: String? { auth.user?.id }

    private var currentPhotoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var currentHeaderURL: URL? { profileStore.myProfile?.headerURL }

    /// Whether the preview is currently showing a custom header —
    /// either freshly cropped or already saved (and not just removed).
    private var hasCustomHeader: Bool {
        croppedHeader != nil || (!headerRemoved && currentHeaderURL != nil)
    }

    /// The user's own signature color — the default band friends see
    /// when no header photo is set.
    private var myAccent: Color {
        if let myId { return Color(hex: RemoteIDMapper.accentHex(forRemoteId: myId)) }
        return Theme.textPrimary
    }

    private var initials: String {
        let fromName = name.split(separator: " ").prefix(2).compactMap { $0.first }
        if !fromName.isEmpty { return String(fromName).uppercased() }
        return profileStore.myProfile?.initials ?? auth.user?.initials ?? "?"
    }

    private var canSave: Bool {
        guard !profileStore.isSaving, !isUploading else { return false }
        switch usernameStatus {
        case .checking, .invalid, .taken: return false
        case .idle, .unchanged, .available: return true
        }
    }

    var body: some View {
        @Bindable var profileStore = profileStore

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                headerSection
                nameField
                usernameField
                phoneField
                nearYouSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .background(Theme.warmWheat.ignoresSafeArea())
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if profileStore.isSaving || isUploading {
                    ProgressView().tint(Theme.textPrimary)
                } else {
                    Button("Save") { Task { await save() } }
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.textPrimary : Theme.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task { loadInitialValues() }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedImage(newItem) }
        }
        .onChange(of: headerPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedHeader(newItem) }
        }
        .fullScreenCover(item: $headerCropTarget) { target in
            ProfileHeaderCropView(image: target.image) { baked in
                croppedHeader = baked
                headerRemoved = false
            }
        }
        .fullScreenCover(item: $avatarCropTarget) { target in
            AvatarCropView(image: target.image) { baked in
                pickedImage = baked
            }
        }
        .onChange(of: username) { _, newValue in
            let sanitized = ProfileStore.sanitizeUsername(newValue)
            if sanitized != newValue {
                username = sanitized
                return
            }
            scheduleUsernameCheck()
        }
        .alert("Something went wrong", isPresented: $profileStore.showError) {
            Button("OK") { }
        } message: {
            Text(profileStore.errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Header + photo

    /// The classic profile layout: a live banner preview (the exact
    /// shape friends see) with the avatar overlapping its bottom edge.
    private var headerSection: some View {
        VStack(spacing: 0) {
            headerBanner

            photoPicker
                .offset(y: -46)
                .padding(.bottom, -46)

            Text("Tap to change your photo")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 10)

            if hasCustomHeader {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) {
                        croppedHeader = nil
                        headerRemoved = true
                    }
                } label: {
                    Text("Remove header photo")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Banner preview at the profile hero's true aspect ratio. The
    /// signature color sits underneath, so the photo never flashes
    /// empty while loading — same as the real profile band.
    private var headerBanner: some View {
        ZStack(alignment: .bottomTrailing) {
            myAccent
                .aspectRatio(ProfileHeaderCropView.aspect, contentMode: .fit)
                .overlay {
                    headerImage
                        .allowsHitTesting(false)
                }
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.22), .clear, Color.black.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
                .clipShape(.rect(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
                )

            PhotosPicker(selection: $headerPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: "photo.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.warmWheat, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Change header background")
        }
    }

    @ViewBuilder
    private var headerImage: some View {
        if let croppedHeader {
            Image(uiImage: croppedHeader)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if !headerRemoved, let url = currentHeaderURL {
            CachedImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                myAccent
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                avatar
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
                    .padding(4)
                    .background(Circle().fill(Theme.warmWheat))
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

                ZStack {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.warmWheat, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let pickedImage {
            Image(uiImage: pickedImage).resizable().scaledToFill()
        } else if let url = currentPhotoURL {
            CachedImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialsDisc
            }
        } else {
            initialsDisc
        }
    }

    private var initialsDisc: some View {
        ZStack {
            Theme.textPrimary
            Text(initials)
                .font(.serif(38, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    // MARK: - Name

    private var nameField: some View {
        fieldCard(label: "DISPLAY NAME") {
            TextField("Your name", text: $name)
                .font(.sans(16, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
    }

    // MARK: - Username

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldCard(label: "USERNAME") {
                HStack(spacing: 4) {
                    Text("@")
                        .font(.sans(16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("username", text: $username)
                        .font(.sans(16, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    usernameStatusIcon
                }
            }
            usernameHint
        }
    }

    @ViewBuilder
    private var usernameStatusIcon: some View {
        switch usernameStatus {
        case .checking:
            ProgressView().controlSize(.small).tint(Theme.textTertiary)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.alertRed)
        case .idle, .unchanged:
            EmptyView()
        }
    }

    @ViewBuilder
    private var usernameHint: some View {
        let (text, color): (String, Color) = {
            switch usernameStatus {
            case .available: return ("That handle is free.", Theme.alertGreen)
            case .taken: return ("That @username is already taken.", Theme.alertRed)
            case .invalid: return ("3–20 letters, numbers, or underscores.", Theme.alertRed)
            default: return ("Friends can find you by your @username.", Theme.textTertiary)
            }
        }()
        Text(text)
            .font(.sans(12, weight: .regular))
            .foregroundStyle(color)
            .padding(.leading, 4)
            .animation(.easeOut(duration: 0.2), value: usernameStatus)
    }

    // MARK: - Phone (matching only)

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldCard(label: "PHONE NUMBER") {
                TextField("Optional", text: $phone)
                    .font(.sans(16, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .keyboardType(.phonePad)
            }
            Text("Only used so friends with your number can find you from their contacts. Never shown to anyone.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Near you

    private var nearYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAR YOU")
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appear in Near you")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(nearYouStatusText)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if nearYouBusy {
                    ProgressView().tint(Theme.textTertiary)
                } else {
                    Toggle("", isOn: $nearYouOn)
                        .labelsHidden()
                        .tint(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textPrimary.opacity(0.1), lineWidth: 1)
            )

            Text(nearYouHint ?? "Shares only a coarse, city-level area on Discover — never your exact position.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(nearYouHint == nil ? Theme.textTertiary : Theme.alertRed)
                .padding(.leading, 4)
        }
        .onChange(of: nearYouOn) { oldValue, newValue in
            guard oldValue != newValue, !nearYouBusy else { return }
            handleNearYouToggle(newValue)
        }
    }

    private var nearYouStatusText: String {
        if let area = profileStore.myProfile?.areaName, profileStore.nearYouEnabled {
            return "Near \(area)"
        }
        return profileStore.nearYouEnabled ? "On" : "Off"
    }

    private func handleNearYouToggle(_ turnOn: Bool) {
        guard let myId else { return }
        nearYouHint = nil
        if !turnOn {
            Task { await profileStore.setNearYou(areaKey: nil, areaName: nil, myUserId: myId) }
            return
        }
        nearYouBusy = true
        location.requestPermissionIfNeeded()
        Task {
            var waited = 0
            while location.coordinate == nil && waited < 24 {
                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted { break }
                try? await Task.sleep(for: .milliseconds(250))
                waited += 1
            }
            if let coordinate = location.coordinate {
                let ok = await profileStore.enableNearYou(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    myUserId: myId
                )
                if !ok { nearYouOn = false }
            } else {
                nearYouOn = false
                nearYouHint = location.authorizationStatus == .denied || location.authorizationStatus == .restricted
                    ? "Location is off for FrisFocus. Allow it in Settings to use Near you."
                    : "Couldn't get your location just now. Try again in a moment."
            }
            nearYouBusy = false
        }
    }

    // MARK: - Shared field card

    private func fieldCard<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            content()
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Theme.paperCream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.textPrimary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func loadInitialValues() {
        guard !didLoad else { return }
        didLoad = true
        Task {
            if let myId {
                await profileStore.load(myUserId: myId)
                await profileStore.loadPhone(myUserId: myId)
            }
            let profile = profileStore.myProfile
            name = profile?.name ?? auth.user?.name ?? ""
            username = profile?.username ?? ""
            originalUsername = username
            usernameStatus = username.isEmpty ? .idle : .unchanged
            phone = profileStore.myPhone ?? ""
            originalPhone = phone
            nearYouOn = profileStore.nearYouEnabled
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            avatarCropTarget = AvatarCropTarget(image: image)
        }
        photoItem = nil
    }

    private func loadPickedHeader(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            headerCropTarget = HeaderCropTarget(image: image)
        }
        headerPhotoItem = nil
    }

    private func scheduleUsernameCheck() {
        checkTask?.cancel()
        let candidate = username
        if candidate.isEmpty { usernameStatus = .idle; return }
        if candidate == originalUsername { usernameStatus = .unchanged; return }
        guard ProfileStore.isValidUsername(candidate) else { usernameStatus = .invalid; return }
        usernameStatus = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            guard let myId else { return }
            let available = await profileStore.isUsernameAvailable(candidate, myUserId: myId)
            if Task.isCancelled || candidate != username { return }
            usernameStatus = available ? .available : .taken
        }
    }

    private func save() async {
        guard let myId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        var avatarUrl = profileStore.myProfile?.avatarUrl ?? auth.user?.picture
        if let pickedImage {
            isUploading = true
            let uploaded = await profileStore.uploadAvatar(pickedImage, myUserId: myId)
            isUploading = false
            guard let uploaded else { return }
            avatarUrl = uploaded
        }

        var headerEdit: ProfileHeaderEdit = .keep
        if let croppedHeader {
            isUploading = true
            let uploaded = await profileStore.uploadHeader(croppedHeader, myUserId: myId)
            isUploading = false
            guard let uploaded else { return }
            headerEdit = .set(uploaded)
        } else if headerRemoved, profileStore.myProfile?.headerUrl != nil {
            headerEdit = .remove
        }

        if phone.trimmingCharacters(in: .whitespaces) != originalPhone.trimmingCharacters(in: .whitespaces) {
            let phoneOk = await profileStore.savePhone(phone, myUserId: myId)
            guard phoneOk else { return }
        }

        let ok = await profileStore.save(
            name: name,
            username: username.isEmpty ? nil : username,
            email: auth.user?.email,
            avatarUrl: avatarUrl,
            header: headerEdit,
            myUserId: myId
        )
        if ok { dismiss() }
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environment(AuthManager())
            .environment(ProfileStore())
    }
}
