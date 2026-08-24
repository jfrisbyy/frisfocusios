//
//  ContactsMatchService.swift
//  FrisFocus
//
//  Find friends from the address book. Contacts are read locally, their
//  emails and hashed phone numbers are matched against accounts in one
//  round-trip (`match_contact_keys`), and nothing about the address book
//  is ever stored server-side — the function only returns profile ids
//  for keys we supplied.
//

import Foundation
import Contacts
import CryptoKit
import Supabase

/// One address-book person we could invite: a display name plus the raw
/// emails/phones needed to compose the invite text.
nonisolated struct ContactCandidate: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let emails: [String]
    let phones: [String]

    var primaryPhone: String? { phones.first }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// Wire params for the matching RPC.
private nonisolated struct MatchContactKeysParams: Encodable, Sendable {
    let pEmails: [String]
    let pPhoneHashes: [String]

    enum CodingKeys: String, CodingKey {
        case pEmails = "p_emails"
        case pPhoneHashes = "p_phone_hashes"
    }
}

/// One match row: which profile matched, and by which supplied key.
private nonisolated struct MatchedKeyRow: Decodable, Sendable {
    let profileId: String
    let matchedEmail: String?
    let matchedPhoneHash: String?

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case matchedEmail = "matched_email"
        case matchedPhoneHash = "matched_phone_hash"
    }
}

@Observable
@MainActor
final class ContactsMatchService {
    var authorization: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    var isWorking = false
    var hasLoaded = false
    /// People from the address book who already have an account.
    var matched: [RemoteProfile] = []
    /// Everyone else worth inviting (has a phone number to text).
    var inviteCandidates: [ContactCandidate] = []
    var errorMessage: String?

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .limited
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Ask for access if we haven't yet, then run the match.
    func connectAndMatch(myUserId: String) async {
        if authorization == .notDetermined {
            let store = CNContactStore()
            _ = try? await store.requestAccess(for: .contacts)
            authorization = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard isAuthorized else { return }
        await match(myUserId: myUserId)
    }

    /// Read the address book and match it against accounts.
    func match(myUserId: String) async {
        guard isAuthorized, !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            hasLoaded = true
        }

        let contacts = await Task.detached(priority: .userInitiated) {
            Self.fetchContacts()
        }.value

        guard !contacts.isEmpty else {
            matched = []
            inviteCandidates = []
            return
        }

        // Build the key → contact maps (capped, deduped).
        var emailToContact: [String: String] = [:]
        var hashToContact: [String: String] = [:]
        for contact in contacts {
            for email in contact.emails {
                let key = email.lowercased()
                if emailToContact[key] == nil { emailToContact[key] = contact.id }
            }
            for phone in contact.phones {
                guard let normalized = Self.normalizePhone(phone) else { continue }
                let hash = Self.phoneHash(normalized)
                if hashToContact[hash] == nil { hashToContact[hash] = contact.id }
            }
        }

        do {
            var matchedIds = Set<String>()
            var matchedContactIds = Set<String>()

            // Chunk the keys so giant address books stay well under any
            // payload limits.
            let emailChunks = Array(emailToContact.keys).chunked(into: 400)
            let hashChunks = Array(hashToContact.keys).chunked(into: 400)
            let rounds = max(emailChunks.count, hashChunks.count)
            for index in 0..<rounds {
                let params = MatchContactKeysParams(
                    pEmails: index < emailChunks.count ? emailChunks[index] : [],
                    pPhoneHashes: index < hashChunks.count ? hashChunks[index] : []
                )
                let rows: [MatchedKeyRow] = try await supabase
                    .rpc("match_contact_keys", params: params)
                    .execute()
                    .value
                for row in rows {
                    guard row.profileId != myUserId else {
                        // My own card in my contacts — not an invite target.
                        if let email = row.matchedEmail, let cid = emailToContact[email] { matchedContactIds.insert(cid) }
                        if let hash = row.matchedPhoneHash, let cid = hashToContact[hash] { matchedContactIds.insert(cid) }
                        continue
                    }
                    matchedIds.insert(row.profileId)
                    if let email = row.matchedEmail, let cid = emailToContact[email] { matchedContactIds.insert(cid) }
                    if let hash = row.matchedPhoneHash, let cid = hashToContact[hash] { matchedContactIds.insert(cid) }
                }
            }

            // Resolve the matched accounts into renderable profiles.
            if matchedIds.isEmpty {
                matched = []
            } else {
                let profiles: [RemoteProfile] = try await supabase
                    .from("profiles")
                    .select("id, name, username, avatar_url, header_url, area_key, area_name")
                    .in("id", values: Array(matchedIds))
                    .execute()
                    .value
                matched = profiles.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            }

            // Everyone unmatched with a textable number becomes an invite.
            inviteCandidates = contacts.filter {
                !matchedContactIds.contains($0.id) && !$0.phones.isEmpty
            }
        } catch {
            print("[ContactsMatch] match failed: \(error)")
            errorMessage = "Couldn't check your contacts. Please try again."
        }
    }

    // MARK: - Address book

    /// Read name + emails + phones for every contact. Runs off the main
    /// actor — CNContactStore enumeration is blocking.
    nonisolated private static func fetchContacts() -> [ContactCandidate] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        var result: [ContactCandidate] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let fullName = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let name = fullName.isEmpty ? contact.organizationName : fullName
                let emails = contact.emailAddresses.map { ($0.value as String).lowercased() }
                let phones = contact.phoneNumbers.map { $0.value.stringValue }
                guard !name.isEmpty, !(emails.isEmpty && phones.isEmpty) else { return }
                result.append(ContactCandidate(id: contact.identifier, name: name, emails: emails, phones: phones))
            }
        } catch {
            print("[ContactsMatch] enumerate failed: \(error)")
        }
        return result
    }

    // MARK: - Phone normalization

    /// Reduce a phone string to a comparable form: digits only, last 10
    /// kept (drops country codes / formatting), so the same number typed
    /// differently on two phones still matches.
    nonisolated static func normalizePhone(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(10))
    }

    /// SHA-256 hex of a normalized number — the only phone-derived value
    /// that ever leaves the device for matching.
    nonisolated static func phoneHash(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Chunking helper

private extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
