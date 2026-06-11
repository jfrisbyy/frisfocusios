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

struct EditProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var originalUsername: String = ""

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

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
                photoPicker
                nameField
                usernameField
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

    // MARK: - Photo

    private var photoPicker: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
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

            Text("Tap to change your photo")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
            if let myId { await profileStore.load(myUserId: myId) }
            let profile = profileStore.myProfile
            name = profile?.name ?? auth.user?.name ?? ""
            username = profile?.username ?? ""
            originalUsername = username
            usernameStatus = username.isEmpty ? .idle : .unchanged
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            pickedImage = image
        }
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

        let ok = await profileStore.save(
            name: name,
            username: username.isEmpty ? nil : username,
            email: auth.user?.email,
            avatarUrl: avatarUrl,
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
