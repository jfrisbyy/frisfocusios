//
//  SocialSyncService+Stories.swift
//  FrisFocus
//
//  Stories, likes, comments, and seen-by — fully synced. Posts upload
//  their media to the private `stories` bucket (friends + circle
//  members read via RLS-checked signed URLs); friends' posts download
//  into the local media directory so every existing renderer (bubbles,
//  story player, circle clips) keeps working unchanged.
//

import Foundation
import Supabase

// MARK: - Wire rows

nonisolated struct StoryPostRow: Codable, Sendable {
    let id: UUID
    let authorId: String
    let caption: String?
    let mediaPath: String?
    let mediaUrl: String?
    let mediaKind: String?
    let mediaDuration: Double?
    let circleId: UUID?
    let attachedTaskId: UUID?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, caption
        case authorId = "author_id"
        case mediaPath = "media_path"
        case mediaUrl = "media_url"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
        case circleId = "circle_id"
        case attachedTaskId = "attached_task_id"
        case createdAt = "created_at"
    }

    var hasMedia: Bool { mediaPath != nil || mediaUrl != nil }
}

private nonisolated struct StoryLikeRow: Codable, Sendable {
    let id: UUID
    let postId: UUID
    let userId: String
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
    }
}

private nonisolated struct StoryCommentRow: Codable, Sendable {
    let id: UUID
    let postId: UUID
    let userId: String
    let body: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct StoryViewRow: Codable, Sendable {
    let postId: UUID
    let viewerId: String
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case viewerId = "viewer_id"
    }
}

private nonisolated struct StoryPostInsert: Encodable, Sendable {
    let id: String
    let authorId: String
    let caption: String?
    let mediaPath: String?
    let mediaKind: String?
    let mediaDuration: Double?
    let circleId: String?
    let attachedTaskId: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, caption
        case authorId = "author_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
        case circleId = "circle_id"
        case attachedTaskId = "attached_task_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct StoryLikeInsert: Encodable, Sendable {
    let id: String
    let postId: String
    let userId: String
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
    }
}

private nonisolated struct StoryCommentInsert: Encodable, Sendable {
    let id: String
    let postId: String
    let userId: String
    let body: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case userId = "user_id"
    }
}

private nonisolated struct StoryViewInsert: Encodable, Sendable {
    let postId: String
    let viewerId: String
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case viewerId = "viewer_id"
    }
}

// MARK: - Stories sync

extension SocialSyncService {
    /// Pull every story visible to me: friends' unexpired general posts
    /// plus all circle clips. Mirrors into `store.storyPosts` (+ likes,
    /// comments, seen-by) and kicks media downloads for anything new.
    func refreshStories() async {
        guard let store, myUserId != nil else { return }
        do {
            let cutoff = SyncDates.iso(Date().addingTimeInterval(-25 * 3600))
            let rows: [StoryPostRow] = try await supabase
                .from("story_posts")
                .select("id, author_id, caption, media_path, media_url, media_kind, media_duration, circle_id, attached_task_id, created_at")
                .or("circle_id.not.is.null,created_at.gte.\(cutoff)")
                .order("created_at", ascending: false)
                .limit(400)
                .execute()
                .value

            let postIds = rows.map { $0.id.uuidString }
            var likeRows: [StoryLikeRow] = []
            var commentRows: [StoryCommentRow] = []
            var viewRows: [StoryViewRow] = []
            if !postIds.isEmpty {
                async let l: [StoryLikeRow] = supabase
                    .from("story_likes")
                    .select("id, post_id, user_id")
                    .in("post_id", values: postIds)
                    .execute().value
                async let c: [StoryCommentRow] = supabase
                    .from("story_comments")
                    .select("id, post_id, user_id, body, created_at")
                    .in("post_id", values: postIds)
                    .execute().value
                async let v: [StoryViewRow] = supabase
                    .from("story_views")
                    .select("post_id, viewer_id")
                    .in("post_id", values: postIds)
                    .execute().value
                (likeRows, commentRows, viewRows) = try await (l, c, v)
            }

            var involved = Set(rows.map { $0.authorId })
            involved.formUnion(likeRows.map { $0.userId })
            involved.formUnion(commentRows.map { $0.userId })
            involved.formUnion(viewRows.map { $0.viewerId })
            await ensureProfiles(remoteIds: Array(involved))

            let existingById = Dictionary(store.storyPosts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let serverIds = Set(rows.map { $0.id })

            var mapped: [StoryPost] = rows.map { row in
                var post = StoryPost(
                    id: row.id,
                    authorId: localId(forRemote: row.authorId),
                    createdAt: SyncDates.parse(row.createdAt),
                    caption: row.caption,
                    mediaId: row.hasMedia ? row.id : nil,
                    circleId: row.circleId,
                    attachedCircleTaskId: row.attachedTaskId
                )
                // A post I authored locally keeps its original media asset.
                if let existing = existingById[row.id], existing.mediaId != nil {
                    post.mediaId = existing.mediaId
                }
                return post
            }

            // Keep local posts the server hasn't echoed yet. General
            // posts are kept only briefly (optimistic uploads still in
            // flight); circle clips never expire, so we preserve any
            // locally-authored clip the server hasn't returned regardless
            // of age — a failed/pending upload must not erase the story
            // (or its "new story" badge) on the next refresh.
            let optimisticWindow = Date().addingTimeInterval(-15 * 60)
            let optimistic = store.storyPosts.filter { post in
                post.authorId == store.currentUserId
                    && !serverIds.contains(post.id)
                    && (post.circleId != nil || post.createdAt > optimisticWindow)
            }
            mapped.append(contentsOf: optimistic)
            mapped.sort { $0.createdAt > $1.createdAt }
            store.storyPosts = mapped

            store.likes = likeRows.map { row in
                Like(
                    id: row.id,
                    postId: row.postId,
                    fromFriendId: localId(forRemote: row.userId),
                    fromName: displayName(forRemote: row.userId)
                )
            }
            store.comments = commentRows.map { row in
                Comment(
                    id: row.id,
                    postId: row.postId,
                    fromFriendId: localId(forRemote: row.userId),
                    fromName: displayName(forRemote: row.userId),
                    fromInitials: initials(forRemote: row.userId),
                    text: row.body,
                    createdAt: SyncDates.parse(row.createdAt)
                )
            }

            var viewers: [UUID: Set<UUID>] = [:]
            for row in viewRows {
                viewers[row.postId, default: []].insert(localId(forRemote: row.viewerId))
            }
            store.storyViewerIds = viewers

            ensureMediaAssets(for: rows)
            store.persistAll()
        } catch {
            print("[SocialSync] stories refresh failed: \(error)")
        }
    }

    /// Make sure a `MediaAsset` exists for every synced post with media
    /// and download any bytes we don't have locally yet.
    private func ensureMediaAssets(for rows: [StoryPostRow]) {
        guard let store else { return }
        for row in rows where row.hasMedia {
            // My own uploads already carry a local asset under the
            // post's original mediaId — skip those.
            if let post = store.storyPosts.first(where: { $0.id == row.id }),
               let mid = post.mediaId, mid != row.id,
               store.media(by: mid) != nil {
                continue
            }
            let type: MediaType = (row.mediaKind == "video") ? .video : .photo
            if store.media(by: row.id) == nil {
                store.mediaAssets.append(MediaAsset(
                    id: row.id,
                    type: type,
                    localURL: nil,
                    remoteURL: row.mediaUrl.flatMap(URL.init(string:)),
                    thumbnailURL: nil,
                    durationSeconds: row.mediaDuration,
                    createdAt: SyncDates.parse(row.createdAt)
                ))
            }
            let assetId = row.id
            if let asset = store.media(by: assetId),
               asset.resolvedLocalURL == nil,
               !activeMediaDownloads.contains(assetId) {
                activeMediaDownloads.insert(assetId)
                Task { [weak self] in
                    await self?.downloadStoryMedia(row: row, type: type)
                    self?.activeMediaDownloads.remove(assetId)
                }
            }
        }
    }

    private func downloadStoryMedia(row: StoryPostRow, type: MediaType) async {
        guard let store, let dir = MediaAsset.mediaDirectory else { return }
        do {
            let url: URL
            if let mediaUrl = row.mediaUrl, let direct = URL(string: mediaUrl) {
                url = direct
            } else if let path = row.mediaPath {
                url = try await supabase.storage.from("stories").createSignedURL(path: path, expiresIn: 3600)
            } else {
                return
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext: String
            if type == .photo {
                ext = "jpg"
            } else {
                ext = (row.mediaPath as NSString?)?.pathExtension.isEmpty == false
                    ? (row.mediaPath! as NSString).pathExtension
                    : "mov"
            }
            let fileURL = dir.appendingPathComponent("story-\(row.id.uuidString.lowercased()).\(ext)")
            try data.write(to: fileURL, options: .atomic)
            if let idx = store.mediaAssets.firstIndex(where: { $0.id == row.id }) {
                store.mediaAssets[idx].localURL = fileURL
                store.persistAll()
                if type == .video {
                    await store.ensureVideoPoster(mediaId: row.id)
                }
            }
        } catch {
            print("[SocialSync] media download failed for \(row.id): \(error)")
        }
    }

    // MARK: Up-sync hooks

    /// Called by `Store.postMedia` right after a local post is created.
    nonisolated func storyPosted(post: StoryPost, asset: MediaAsset?) {
        Task { @MainActor [weak self] in
            await self?.uploadStory(post: post, asset: asset)
        }
    }

    private func uploadStory(post: StoryPost, asset: MediaAsset?) async {
        guard let myUserId else { return }
        do {
            var mediaPath: String?
            var mediaKind: String?
            if let asset, let local = asset.resolvedLocalURL,
               let data = try? Data(contentsOf: local) {
                let ext = asset.type == .photo ? "jpg" : "mov"
                let contentType = asset.type == .photo ? "image/jpeg" : "video/quicktime"
                let path = "\(myUserId)/\(post.id.uuidString.lowercased()).\(ext)"
                try await StorageUploadClient.upload(
                    data: data,
                    bucket: "stories",
                    path: path,
                    contentType: contentType,
                    onProgress: { _ in }
                )
                mediaPath = path
                mediaKind = asset.type.rawValue
            }
            try await supabase.from("story_posts").insert(StoryPostInsert(
                id: post.id.uuidString,
                authorId: myUserId,
                caption: post.caption,
                mediaPath: mediaPath,
                mediaKind: mediaKind,
                mediaDuration: asset?.durationSeconds,
                circleId: post.circleId?.uuidString,
                attachedTaskId: post.attachedCircleTaskId?.uuidString,
                createdAt: SyncDates.iso(post.createdAt)
            )).execute()
        } catch {
            print("[SocialSync] story upload failed: \(error)")
        }
    }

    nonisolated func storyDeleted(postId: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("story_posts")
                    .delete()
                    .eq("id", value: postId.uuidString)
                    .execute()
                for ext in ["jpg", "mov", "mp4"] {
                    let path = "\(myUserId)/\(postId.uuidString.lowercased()).\(ext)"
                    _ = try? await supabase.storage.from("stories").remove(paths: [path])
                }
            } catch {
                print("[SocialSync] story delete failed: \(error)")
            }
        }
    }

    nonisolated func likeChanged(postId: UUID, liked: Bool, likeId: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                if liked {
                    try await supabase.from("story_likes").insert(StoryLikeInsert(
                        id: likeId.uuidString,
                        postId: postId.uuidString,
                        userId: myUserId
                    )).execute()
                    self.notifyAuthor(ofPost: postId, kind: .storyLike, preview: nil)
                } else {
                    try await supabase.from("story_likes")
                        .delete()
                        .eq("post_id", value: postId.uuidString)
                        .eq("user_id", value: myUserId)
                        .execute()
                }
            } catch {
                print("[SocialSync] like sync failed: \(error)")
            }
        }
    }

    nonisolated func commentAdded(_ comment: Comment) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("story_comments").insert(StoryCommentInsert(
                    id: comment.id.uuidString,
                    postId: comment.postId.uuidString,
                    userId: myUserId,
                    body: comment.text
                )).execute()
                self.notifyAuthor(ofPost: comment.postId, kind: .storyComment, preview: comment.text)
            } catch {
                print("[SocialSync] comment sync failed: \(error)")
            }
        }
    }

    nonisolated func storyViewed(postId: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("story_views")
                    .upsert(
                        StoryViewInsert(postId: postId.uuidString, viewerId: myUserId),
                        onConflict: "post_id,viewer_id"
                    )
                    .execute()
            } catch {
                print("[SocialSync] view sync failed: \(error)")
            }
        }
    }

    /// Push to a post's author when someone reacts (never to yourself).
    private func notifyAuthor(ofPost postId: UUID, kind: PushKind, preview: String?) {
        guard let store,
              let post = store.storyPosts.first(where: { $0.id == postId }),
              post.authorId != store.currentUserId,
              let remote = remoteId(forLocal: post.authorId) else { return }
        PushService.send(to: remote, kind: kind, preview: preview)
    }

    // MARK: One-time migration of pre-sync local posts

    /// Upload story posts that were created on this device before sync
    /// existed (queued by the Store's one-time social reset) so they
    /// survive under the real account and become visible to friends.
    func migratePendingLocalStories() async {
        guard let store else { return }
        let key = "pendingStoryUploads"
        guard let ids = UserDefaults.standard.stringArray(forKey: key), !ids.isEmpty else { return }
        var remaining = ids
        for idString in ids {
            guard let id = UUID(uuidString: idString),
                  let post = store.storyPosts.first(where: { $0.id == id }) else {
                remaining.removeAll { $0 == idString }
                continue
            }
            let asset = post.mediaId.flatMap { store.media(by: $0) }
            await uploadStory(post: post, asset: asset)
            remaining.removeAll { $0 == idString }
        }
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(remaining, forKey: key)
        }
    }
}
