//
//  ClaimNameStep.swift
//  FrisFocus
//
//  Step 2 of the account seam: claim a friendly @handle over the warm
//  cream sky. The field arrives pre-filled with an open suggestion drawn
//  from the person's name, with a live availability check — so the
//  default is always one tap to accept and the step can never fail.
//  An optional photo can be added; otherwise the avatar falls back to
//  the provider photo or initials.
//

import SwiftUI
import PhotosUI

struct ClaimNameStep: View {
    /// Advance to the invite step.
    let onContinue: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var handle: String = ""
    @State private var availability: Availability = .idle
    @State private var didSeed: Bool = false

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    @State private var isSaving: Bool = false
    @State private var shown: Bool = false
    /// Set once a save has failed for a reason other than the handle
    /// being taken — the server could not be reached. Opens the quiet
    /// "Continue for now" way out of this non-dismissible step.
    @State private var saveFailedUnreachable: Bool = false

    private enum Availability: Equatable {
        /// `unverified`: the availability check itself could not reach
        /// the server, so the handle is neither confirmed nor taken.
        case idle, checking, available, taken, invalid, unverified
    }

    private var myId: String? { auth.user?.id }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            VStack(spacing: 10) {
                EyebrowText(text: "CLAIM YOUR NAME", opacity: 0.5)
                Text("What should\nfriends call you?")
                    .font(.serif(30, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is your handle. You can change it later.")
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)

            Spacer(minLength: 22)

            avatarPicker
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9)

            Spacer(minLength: 22)

            handleField
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)

            Spacer(minLength: 16)

            continueButton
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)

            if canContinueLocally {
                continueForNow
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)) {
                shown = true
            }
        }
        .task { await seedSuggestionIfNeeded() }
        // Live availability — debounced on each keystroke.
        .task(id: handle) { await checkAvailability() }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPicked(newItem) }
        }
        .alert("Couldn't save", isPresented: profileStoreErrorBinding) {
            Button("OK") {}
        } message: {
            Text(profileStore.errorMessage ?? "Please try again.")
        }
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                avatarCircle
                    .frame(width: 108, height: 108)

                ZStack {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: pickedImage == nil ? "plus" : "pencil")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.warmWheat, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pickedImage == nil ? "Add a photo" : "Change photo")
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let pickedImage {
            Image(uiImage: pickedImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let url = auth.user?.photoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialsCircle
                }
            }
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Theme.paperCream)
            Circle().strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 1)
            Text(auth.user?.initials ?? "?")
                .font(.serif(38, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
    }

    // MARK: Handle field

    private var handleField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("@")
                    .font(.sans(20, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("handle", text: $handle)
                    .font(.sans(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onChange(of: handle) { _, newValue in
                        let clean = ProfileStore.sanitizeUsername(newValue)
                        if clean != newValue { handle = clean }
                    }
                Spacer(minLength: 8)
                statusBadge
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Theme.warmWheat)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(fieldBorderColor, lineWidth: 1.5)
            )

            Text(statusMessage)
                .font(.sans(12.5, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .animation(.easeInOut(duration: 0.2), value: availability)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch availability {
        case .checking:
            ProgressView().tint(Theme.textTertiary)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
        case .taken, .invalid:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.alertAmber)
        case .idle, .unverified:
            EmptyView()
        }
    }

    private var statusMessage: String {
        switch availability {
        case .idle: return " "
        case .checking: return "Checking…"
        case .available: return "@\(handle) is available"
        case .taken: return "Taken — try the suggestion below"
        case .invalid: return "Use 3–20 letters, numbers, or _"
        case .unverified: return "Can't check this name right now"
        }
    }

    private var statusColor: Color {
        switch availability {
        case .available: return Theme.alertGreen
        case .taken, .invalid: return Theme.alertAmber
        default: return Theme.textTertiary
        }
    }

    private var fieldBorderColor: Color {
        switch availability {
        case .available: return Theme.alertGreen.opacity(0.6)
        case .taken, .invalid: return Theme.alertAmber.opacity(0.5)
        default: return Theme.textPrimary.opacity(0.12)
        }
    }

    // MARK: Continue

    private var continueButton: some View {
        Button {
            Task { await saveAndContinue() }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(Theme.textCream)
                } else {
                    Text("Continue")
                        .font(.sans(17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.textCream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(canContinue ? Theme.textPrimary : Theme.textPrimary.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue || isSaving)
    }

    private var canContinue: Bool { availability == .available }

    /// The way out when the server can't be reached: this step sits on a
    /// cover that cannot be dismissed, so a failed save must never leave
    /// retrying as the only move. Offered only after the server has
    /// actually failed us — never as a way round a handle that is taken.
    private var canContinueLocally: Bool {
        guard !isSaving, ProfileStore.isValidUsername(handle) else { return false }
        return saveFailedUnreachable || availability == .unverified
    }

    private var continueForNow: some View {
        VStack(spacing: 4) {
            Text("We can't reach FrisFocus right now.")
                .font(.sans(12.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                continueLocally()
            } label: {
                Text("Continue for now")
                    .underline()
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("We'll save @\(handle) for you once you're back online.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Logic

    /// Pre-fill the handle with an open suggestion drawn from the name.
    /// The local seed lands INSTANTLY (no empty field on a slow network);
    /// the availability-refined suggestion swaps in only if the user
    /// hasn't started typing.
    private func seedSuggestionIfNeeded() async {
        guard !didSeed, let myId else { return }
        didSeed = true
        let base = baseHandle(from: auth.user?.name ?? auth.user?.email)
        let root = base.isEmpty ? "friend" : base
        handle = root
        let suggestion = await firstAvailable(base: root, myUserId: myId)
        if handle == root, suggestion != root {
            handle = suggestion
        }
    }

    /// Walk base, base1, base2… until one is free (caps at a few tries).
    private func firstAvailable(base: String, myUserId: String) async -> String {
        let root = base.isEmpty ? "friend" : base
        if await profileStore.isUsernameAvailable(root, myUserId: myUserId) { return root }
        // Offline, every candidate "fails" — don't walk twenty of them
        // and land on a random suffix; keep the plain name.
        if profileStore.lastUsernameCheckFailed { return root }
        for n in 1...20 {
            let candidate = ProfileStore.sanitizeUsername("\(root)\(n)")
            if await profileStore.isUsernameAvailable(candidate, myUserId: myUserId) {
                return candidate
            }
        }
        return ProfileStore.sanitizeUsername("\(root)\(Int.random(in: 100...999))")
    }

    private func baseHandle(from raw: String?) -> String {
        guard let raw else { return "" }
        // Use the first name (or the email local part).
        let firstWord = raw.split(whereSeparator: { $0 == " " || $0 == "@" }).first.map(String.init) ?? raw
        return ProfileStore.sanitizeUsername(firstWord)
    }

    /// Debounced availability check for the current handle. A slow
    /// network never walls the step: after 2.5 s of "Checking…" the
    /// handle resolves optimistically so Continue enables — the save
    /// still enforces uniqueness server-side (and re-checks on a clash).
    private func checkAvailability() async {
        let candidate = handle
        guard let myId else { return }
        guard ProfileStore.isValidUsername(candidate) else {
            availability = candidate.isEmpty ? .idle : .invalid
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, handle == candidate, availability == .checking else { return }
            availability = .available
        }
        defer { watchdog.cancel() }
        let free = await profileStore.isUsernameAvailable(candidate, myUserId: myId)
        if Task.isCancelled || handle != candidate { return }
        if !free && profileStore.lastUsernameCheckFailed {
            // The check never reached the server. Saying "Taken" here
            // would be untrue, and would wall the step while offline.
            availability = .unverified
        } else {
            availability = free ? .available : .taken
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            pickedImage = image
        }
    }

    private func saveAndContinue() async {
        guard let myId, canContinue else { return }
        isSaving = true
        defer { isSaving = false }

        var avatarUrl: String?
        if let pickedImage {
            avatarUrl = await profileStore.uploadAvatar(pickedImage, myUserId: myId)
        }

        let name = auth.user?.name?.trimmingCharacters(in: .whitespaces)
        let ok = await profileStore.save(
            name: (name?.isEmpty == false) ? name! : handle,
            username: handle,
            email: auth.user?.email,
            avatarUrl: avatarUrl,
            myUserId: myId
        )
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onContinue()
        } else {
            // Anything but a taken handle means the server couldn't be
            // reached — open the "Continue for now" way out.
            if !profileStore.lastSaveHitDuplicate {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    saveFailedUnreachable = true
                }
            }
            // A rare race (handle taken just now) — re-check so the user
            // sees it and can accept a fresh suggestion.
            await checkAvailability()
        }
    }

    /// Carry on with the handle kept on this device. `ProfileStore`
    /// shows it locally and retries the save on the next launch (or the
    /// next time the profile is read); the photo, if one was picked, can
    /// be added again from the profile once online.
    private func continueLocally() {
        guard let myId, ProfileStore.isValidUsername(handle) else { return }
        let providerName = auth.user?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        profileStore.stashPendingClaim(
            name: providerName.isEmpty ? handle : providerName,
            username: handle,
            myUserId: myId
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onContinue()
    }

    private var profileStoreErrorBinding: Binding<Bool> {
        Binding(
            get: { profileStore.showError },
            set: { profileStore.showError = $0 }
        )
    }
}
