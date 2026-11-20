//
//  ProfileStore.swift
//  FrisFocus
//
//  The signed-in user's own editable profile, backed by the `profiles`
//  table. Auth (the Rork JWT) gives us a stable id, email, and the
//  provider's name/photo; this layer lets the user override their
//  display name, claim a unique @username, and upload a custom photo —
//  and surfaces that identity app-wide (the home avatar, the account
//  hub) so the user sees themselves the way friends do.
//
//  Injected once at the app root and loaded whenever the signed-in id
//  changes. Friend-facing surfaces (Friends, circles, proofs) already
//  read `profiles` via `RemoteProfile`, so an edit here propagates to
//  everyone automatically.
//

import Foundation
import Supabase
import UIKit
import CoreLocation

// MARK: - Wire payloads

/// Minimal row used for the username availability check.
private nonisolated struct ProfileIdRow: Decodable, Sendable {
    let id: String
}

/// How a save should treat the header background: leave it alone,
/// point it at a freshly uploaded image, or clear it back to the
/// default signature-color band (an explicit SQL NULL).
nonisolated enum ProfileHeaderEdit: Sendable {
    case keep
    case set(String)
    case remove
}

/// Partial upsert of the user's own profile. Optional fields use
/// `encodeIfPresent`, so a `nil` is omitted from the payload and
/// leaves that column untouched — never accidentally nulled. The
/// header is the exception: it encodes an explicit null on `.remove`
/// and is omitted entirely on `.keep`. `id` anchors the upsert to
/// the PK.
private nonisolated struct ProfileEditUpsert: Encodable, Sendable {
    let id: String
    let email: String?
    let name: String?
    let username: String?
    let avatarUrl: String?
    let header: ProfileHeaderEdit
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, name, username
        case avatarUrl = "avatar_url"
        case headerUrl = "header_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        switch header {
        case .keep: break
        case .set(let url): try c.encode(url, forKey: .headerUrl)
        case .remove: try c.encodeNil(forKey: .headerUrl)
        }
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Update payload for the Near-you columns. Encodes explicit nulls on
/// clear so turning Near you off actually removes the area.
private nonisolated struct NearYouUpdate: Encodable, Sendable {
    let areaKey: String?
    let areaName: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case areaKey = "area_key"
        case areaName = "area_name"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let areaKey { try c.encode(areaKey, forKey: .areaKey) } else { try c.encodeNil(forKey: .areaKey) }
        if let areaName { try c.encode(areaName, forKey: .areaName) } else { try c.encodeNil(forKey: .areaName) }
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// The user's own private contact-key row (phone for matching).
private nonisolated struct ContactKeyRow: Decodable, Sendable {
    let phone: String?
}

private nonisolated struct ContactKeyUpsert: Encodable, Sendable {
    let userId: String
    let phone: String?
    let phoneHash: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case phone
        case phoneHash = "phone_hash"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        if let phone { try c.encode(phone, forKey: .phone) } else { try c.encodeNil(forKey: .phone) }
        if let phoneHash { try c.encode(phoneHash, forKey: .phoneHash) } else { try c.encodeNil(forKey: .phoneHash) }
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// A handle the person chose while the server could not be reached.
/// Claim-name lets them carry on ("Continue for now") rather than
/// trapping them on a cover that cannot be dismissed; the claim waits
/// on this device and `ProfileStore.load` retries the save on the next
/// launch, or the next time the profile is read.
///
/// Only the account id, display name and handle are kept — no email —
/// and the claim is ignored for any other account that signs in here.
private nonisolated struct PendingProfileClaim: Codable, Sendable {
    let userId: String
    let name: String
    let username: String
}

// MARK: - Store

@Observable
@MainActor
final class ProfileStore {
    /// The signed-in user's own profile row, once loaded. The UI falls
    /// back to the auth-provided identity while this is nil.
    var myProfile: RemoteProfile?

    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var showError = false

    /// True when the most recent @username availability check could not
    /// reach the server — as opposed to finding the handle taken. Lets
    /// claim-name say "can't check" instead of a false "Taken".
    private(set) var lastUsernameCheckFailed = false
    /// True when the most recent `save` failed because the @username was
    /// already taken, rather than because the server was unreachable.
    private(set) var lastSaveHitDuplicate = false

    /// The user's own phone number (private, matching-only). Loaded
    /// from `contact_keys` on demand; nil when unset.
    var myPhone: String?

    @ObservationIgnored private var loadedForUserId: String?
    @ObservationIgnored private var phoneLoadedForUserId: String?
    @ObservationIgnored private var isRetryingClaim = false

    /// The columns the store reads/writes on `profiles`.
    private static let profileColumns = "id, name, username, avatar_url, header_url, area_key, area_name"

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Load

    /// Fetch the user's own profile row. Cheap to call repeatedly — it
    /// no-ops if already loaded for this id unless `force` is set.
    func load(myUserId: String, force: Bool = false) async {
        if !force, loadedForUserId == myUserId, myProfile != nil {
            await retryPendingClaimIfNeeded(myUserId: myUserId)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select(Self.profileColumns)
                .eq("id", value: myUserId)
                .limit(1)
                .execute()
                .value
            myProfile = rows.first
            loadedForUserId = myUserId
            await retryPendingClaimIfNeeded(myUserId: myUserId)
        } catch {
            fail("Couldn't load your profile.", error)
            // Still unreachable: keep showing the handle that is waiting
            // to be saved rather than forgetting the person chose one.
            if let claim = pendingClaim(for: myUserId) {
                showPendingClaimLocally(claim)
            }
        }
    }

    // MARK: Pending handle claim

    private static let pendingClaimKey = "profile.pendingClaim.v1"

    private func pendingClaim(for myUserId: String) -> PendingProfileClaim? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingClaimKey) else { return nil }
        guard let claim = try? JSONDecoder().decode(PendingProfileClaim.self, from: data) else { return nil }
        return claim.userId == myUserId ? claim : nil
    }

    private func clearPendingClaim() {
        UserDefaults.standard.removeObject(forKey: Self.pendingClaimKey)
    }

    /// Keep a handle the server could not be reached to save: remember it
    /// on this device, show it locally straight away, and let `load`
    /// retry the save later. Used by claim-name's "Continue for now".
    func stashPendingClaim(name: String, username: String, myUserId: String) {
        let claim = PendingProfileClaim(
            userId: myUserId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            username: Self.sanitizeUsername(username)
        )
        if let data = try? JSONEncoder().encode(claim) {
            UserDefaults.standard.set(data, forKey: Self.pendingClaimKey)
        }
        showPendingClaimLocally(claim)
    }

    /// Lay the waiting handle over whatever profile is in memory, so the
    /// person sees the name they chose while the save is still pending.
    private func showPendingClaimLocally(_ claim: PendingProfileClaim) {
        let current = myProfile
        let shownName: String? = claim.name.isEmpty ? current?.name : claim.name
        myProfile = RemoteProfile(
            id: claim.userId,
            email: current?.email,
            name: shownName,
            username: claim.username,
            avatarUrl: current?.avatarUrl,
            headerUrl: current?.headerUrl,
            areaKey: current?.areaKey,
            areaName: current?.areaName,
            seasonCard: current?.seasonCard
        )
    }

    /// Try again to save a handle claimed while offline. Quiet on
    /// purpose — it runs behind `load`, so a failure is logged and left
    /// for the next attempt instead of raising an alert about something
    /// the person did not just do.
    private func retryPendingClaimIfNeeded(myUserId: String) async {
        guard let claim = pendingClaim(for: myUserId) else { return }
        // The row already carries a handle that is not this claim (set
        // from another device, say): the server wins, nothing to retry.
        if let saved = myProfile?.username, !saved.isEmpty, saved != claim.username {
            clearPendingClaim()
            return
        }
        guard !isRetryingClaim else {
            // Another load is already retrying. Keep the chosen handle
            // in view meanwhile rather than the bare row just fetched.
            showPendingClaimLocally(claim)
            return
        }
        isRetryingClaim = true
        defer { isRetryingClaim = false }
        do {
            let updated: RemoteProfile = try await supabase
                .from("profiles")
                .upsert(ProfileEditUpsert(
                    id: myUserId,
                    email: nil,
                    name: claim.name.isEmpty ? nil : claim.name,
                    username: claim.username,
                    avatarUrl: nil,
                    header: .keep,
                    updatedAt: Self.iso.string(from: Date())
                ))
                .select(Self.profileColumns)
                .single()
                .execute()
                .value
            myProfile = updated
            loadedForUserId = myUserId
            clearPendingClaim()
        } catch {
            let text = "\(error)"
            if text.contains("23505") || text.lowercased().contains("duplicate") || text.contains("profiles_username") {
                // Someone else took the handle in the meantime. Retrying
                // can never succeed, so drop the claim; the next load
                // reads the real row and the person can choose again.
                Log.profileStore.error("pending handle claim lost to a duplicate: \(error)")
                clearPendingClaim()
                loadedForUserId = nil
            } else {
                Log.profileStore.error("pending handle claim retry failed: \(error)")
                showPendingClaimLocally(claim)
            }
        }
    }

    /// Drop cached state on sign-out so the next user starts clean.
    func clear() {
        // A pending handle claim is deliberately NOT cleared here: this
        // runs on every cold launch before the session restores, which
        // would throw the claim away before it could be retried. The
        // claim carries its account id and is ignored for anyone else.
        myProfile = nil
        loadedForUserId = nil
        myPhone = nil
        phoneLoadedForUserId = nil
    }

    // MARK: Username

    /// A tidy handle: lowercased, trimmed, 3–20 of [a–z 0–9 _].
    nonisolated static func sanitizeUsername(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = lowered.unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0)
        }
        return String(String.UnicodeScalarView(allowed.prefix(20)))
    }

    nonisolated static func isValidUsername(_ candidate: String) -> Bool {
        let c = candidate.count
        guard c >= 3, c <= 20 else { return false }
        return candidate.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    /// Case-insensitive availability. Free when no *other* profile holds
    /// the handle (the user's own current handle counts as available).
    func isUsernameAvailable(_ raw: String, myUserId: String) async -> Bool {
        let candidate = Self.sanitizeUsername(raw)
        guard Self.isValidUsername(candidate) else { return false }
        do {
            let rows: [ProfileIdRow] = try await supabase
                .from("profiles")
                .select("id")
                .ilike("username", pattern: candidate)
                .execute()
                .value
            lastUsernameCheckFailed = false
            return rows.allSatisfy { $0.id == myUserId }
        } catch {
            Log.profileStore.error("username check failed: \(error)")
            lastUsernameCheckFailed = true
            return false
        }
    }

    // MARK: Save

    /// Upsert the user's edited profile. Returns true on success. A
    /// duplicate @username surfaces a friendly, specific message.
    @discardableResult
    func save(
        name: String,
        username: String?,
        email: String?,
        avatarUrl: String?,
        header: ProfileHeaderEdit = .keep,
        myUserId: String
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        lastSaveHitDuplicate = false

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.map(Self.sanitizeUsername)

        do {
            let updated: RemoteProfile = try await supabase
                .from("profiles")
                .upsert(ProfileEditUpsert(
                    id: myUserId,
                    email: email,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    username: (cleanUsername?.isEmpty == false) ? cleanUsername : nil,
                    avatarUrl: avatarUrl,
                    header: header,
                    updatedAt: Self.iso.string(from: Date())
                ))
                .select(Self.profileColumns)
                .single()
                .execute()
                .value
            myProfile = updated
            loadedForUserId = myUserId
            return true
        } catch {
            let text = "\(error)"
            if text.contains("23505") || text.lowercased().contains("duplicate") || text.contains("profiles_username") {
                lastSaveHitDuplicate = true
                fail("That @username is already taken. Try another.", error)
            } else {
                fail("Couldn't save your profile.", error)
            }
            return false
        }
    }

    // MARK: Phone (private matching key)

    /// Load the user's own phone from the private `contact_keys` row.
    /// Cheap to call repeatedly.
    func loadPhone(myUserId: String, force: Bool = false) async {
        if !force, phoneLoadedForUserId == myUserId { return }
        do {
            let rows: [ContactKeyRow] = try await supabase
                .from("contact_keys")
                .select("phone")
                .eq("user_id", value: myUserId)
                .limit(1)
                .execute()
                .value
            myPhone = rows.first?.phone
            phoneLoadedForUserId = myUserId
        } catch {
            Log.profileStore.error("phone load failed: \(error)")
        }
    }

    /// Save (or clear, when empty) the matching-only phone number. The
    /// raw number stays readable only by its owner; matching uses the
    /// hash.
    @discardableResult
    func savePhone(_ raw: String?, myUserId: String) async -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = trimmed.isEmpty ? nil : ContactsMatchService.normalizePhone(trimmed)
        if !trimmed.isEmpty && normalized == nil {
            fail("That phone number looks too short.", NSError(domain: "ProfileStore", code: -3))
            return false
        }
        do {
            try await supabase
                .from("contact_keys")
                .upsert(ContactKeyUpsert(
                    userId: myUserId,
                    phone: trimmed.isEmpty ? nil : trimmed,
                    phoneHash: normalized.map { ContactsMatchService.phoneHash($0) },
                    updatedAt: Self.iso.string(from: Date())
                ), onConflict: "user_id")
                .execute()
            myPhone = trimmed.isEmpty ? nil : trimmed
            phoneLoadedForUserId = myUserId
            return true
        } catch {
            fail("Couldn't save your phone number.", error)
            return false
        }
    }

    // MARK: Near you

    /// Whether the user currently shares a coarse area.
    var nearYouEnabled: Bool { myProfile?.areaKey != nil }

    /// Turn Near you on from a coordinate: derive the coarse grid cell
    /// and a friendly city-level name, then store both on the profile.
    @discardableResult
    func enableNearYou(latitude: Double, longitude: Double, myUserId: String) async -> Bool {
        let key = AreaGrid.key(latitude: latitude, longitude: longitude)
        var name: String?
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude)
            )
            let mark = placemarks.first
            name = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea
        } catch {
            // Geocoding is best-effort — the key alone still matches.
            Log.profileStore.error("reverse geocode failed: \(error)")
        }
        return await setNearYou(areaKey: key, areaName: name, myUserId: myUserId)
    }

    /// Write (or clear, with nils) the Near-you area columns.
    @discardableResult
    func setNearYou(areaKey: String?, areaName: String?, myUserId: String) async -> Bool {
        do {
            try await supabase
                .from("profiles")
                .update(NearYouUpdate(
                    areaKey: areaKey,
                    areaName: areaName,
                    updatedAt: Self.iso.string(from: Date())
                ))
                .eq("id", value: myUserId)
                .execute()
            myProfile?.areaKey = areaKey
            myProfile?.areaName = areaName
            return true
        } catch {
            fail("Couldn't update Near you.", error)
            return false
        }
    }

    // MARK: Avatar

    /// Upload a chosen image to the public avatars bucket under the
    /// user's own folder and return its public URL, or nil on failure.
    func uploadAvatar(_ image: UIImage, myUserId: String) async -> String? {
        guard let data = downscaledJPEG(image) else {
            fail("Couldn't process that photo.", NSError(domain: "ProfileStore", code: -1))
            return nil
        }
        let path = "\(myUserId)/avatar_\(UUID().uuidString).jpg"
        do {
            _ = try await supabase.storage
                .from("avatars")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
            let url = try supabase.storage.from("avatars").getPublicURL(path: path)
            await retireOldImage(at: myProfile?.avatarUrl, myUserId: myUserId)
            return url.absoluteString
        } catch {
            fail("Couldn't upload your photo.", error)
            return nil
        }
    }

    /// Upload a pre-cropped header background to the public avatars
    /// bucket under the user's own folder and return its public URL.
    /// The crop screen bakes the framing in, so this only downsizes.
    func uploadHeader(_ image: UIImage, myUserId: String) async -> String? {
        guard let data = downscaledJPEG(image, maxDimension: 1400) else {
            fail("Couldn't process that photo.", NSError(domain: "ProfileStore", code: -2))
            return nil
        }
        let path = "\(myUserId)/header_\(UUID().uuidString).jpg"
        do {
            _ = try await supabase.storage
                .from("avatars")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
            let url = try supabase.storage.from("avatars").getPublicURL(path: path)
            await retireOldImage(at: myProfile?.headerUrl, myUserId: myUserId)
            return url.absoluteString
        } catch {
            fail("Couldn't upload your header photo.", error)
            return nil
        }
    }

    /// Remove a previously uploaded avatar/header once its replacement is
    /// live.
    ///
    /// Each upload writes a new uniquely-named object, so without this
    /// every photo a person ever set stays in the bucket — and `avatars`
    /// is public, which means an old picture remains fetchable at its old
    /// URL forever. Replacing your photo should retire the old one.
    ///
    /// Deliberately best-effort and silent: the new photo is already
    /// live, so failing to tidy the old one must never surface as an
    /// error to someone who just changed their picture.
    ///
    /// Only ever deletes inside the caller's own `<userId>/` prefix, and
    /// only a name this app generates, so a malformed or foreign URL
    /// cannot be turned into a delete of something else.
    private func retireOldImage(at urlString: String?, myUserId: String) async {
        guard let urlString,
              let path = Self.avatarObjectPath(from: urlString, myUserId: myUserId)
        else { return }
        _ = try? await supabase.storage.from("avatars").remove(paths: [path])
    }

    /// The `<userId>/<file>` object path inside the avatars bucket that a
    /// stored public URL refers to — or nil if it is not one of ours.
    ///
    /// `nonisolated` because this class is `@MainActor` (unlike `Store`,
    /// which is not) and this is a pure function of its two arguments
    /// with nothing to isolate. Without it the tests, which are
    /// nonisolated, cannot call it at all.
    nonisolated static func avatarObjectPath(from urlString: String, myUserId: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        // .../object/public/avatars/<userId>/<file>
        guard let bucketIndex = parts.firstIndex(of: "avatars"),
              parts.count >= bucketIndex + 3 else { return nil }
        let owner = parts[bucketIndex + 1]
        let file = parts[bucketIndex + 2]
        guard owner == myUserId,
              file.hasPrefix("avatar_") || file.hasPrefix("header_"),
              !file.contains("..") else { return nil }
        return "\(owner)/\(file)"
    }

    /// Square-ish JPEG sized for an avatar — keeps uploads small.
    private func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    // MARK: Helpers

    private func fail(_ message: String, _ error: Error) {
        Log.profileStore.error("\(message) \(error)")
        errorMessage = message
        showError = true
    }
}
