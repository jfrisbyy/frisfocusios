//
//  ProofLibraryView.swift
//  FrisFocus
//
//  The permanent archive of EVERY proof the person made — posted story
//  cards stay here after the 24h story expires, circle clips are kept,
//  and so are proofs sent privately to one friend, which used to leave
//  no trace in the one place someone would go looking for them.
//  Proofs RECEIVED from friends are still never here: this is what you
//  made, not what you were sent.
//
//  A three-column grid of story-shaped thumbnails, newest first, with a
//  filter bar across the top: what it was tied to (a task, a to-do, a
//  milestone, a note) and where it went (kept only, or out to people).
//  A tap opens the full card. Videos loop in the viewer.
//

import AVFoundation
import SwiftUI
import UIKit

/// How the library grid is narrowed.
///
/// The whole reason the archive carries real task / to-do / milestone /
/// note ids rather than display names: "show me every proof for this
/// milestone" is a question the old name-matching library could not
/// answer, and renaming a task silently orphaned its proofs.
enum ProofLibraryFilter: Identifiable, Equatable {
    case all
    /// Never went anywhere — the clearest reading of "just for me".
    case keptOnly
    /// Went out to a story, a circle, or a person.
    case shared
    case task(id: UUID, title: String)
    case milestone(id: UUID, title: String)
    case anyTodo
    case anyNote

    var id: String {
        switch self {
        case .all: return "all"
        case .keptOnly: return "kept"
        case .shared: return "shared"
        case .task(let id, _): return "task-\(id.uuidString)"
        case .milestone(let id, _): return "milestone-\(id.uuidString)"
        case .anyTodo: return "todos"
        case .anyNote: return "notes"
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .keptOnly: return "Just for me"
        case .shared: return "Shared"
        case .task(_, let title): return title
        case .milestone(_, let title): return title
        case .anyTodo: return "To-dos"
        case .anyNote: return "Notes"
        }
    }

    func admits(_ item: ProofLibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .keptOnly: return item.isPrivateToMe
        case .shared: return !item.isPrivateToMe
        case .task(let id, _): return item.taskId == id
        case .milestone(let id, _): return item.milestoneId == id
        case .anyTodo: return item.todoId != nil
        case .anyNote: return item.noteId != nil
        }
    }
}

struct ProofLibraryView: View {
    @Environment(Store.self) private var store

    @State private var viewerItem: ProofLibraryItem?
    @State private var pendingDelete: ProofLibraryItem?
    @State private var filter: ProofLibraryFilter = .all

    /// The proofs the current filter admits, newest first.
    private var visibleItems: [ProofLibraryItem] {
        store.proofLibraryNewestFirst.filter { filter.admits($0) }
    }

    /// The filters worth offering: the fixed ones, plus one per thing
    /// that actually HAS proofs. A filter for a task with nothing
    /// attached is a dead end, so it isn't built.
    private var availableFilters: [ProofLibraryFilter] {
        var result: [ProofLibraryFilter] = [.all]
        let items = store.proofLibraryNewestFirst
        if items.contains(where: { $0.isPrivateToMe }) { result.append(.keptOnly) }
        if items.contains(where: { !$0.isPrivateToMe }) { result.append(.shared) }

        var seenTasks: [UUID] = []
        for item in items {
            if let id = item.taskId, !seenTasks.contains(id) { seenTasks.append(id) }
        }
        for id in seenTasks {
            guard let title = store.tasks.first(where: { $0.id == id })?.title else { continue }
            result.append(.task(id: id, title: title))
        }

        var seenMilestones: [UUID] = []
        for item in items {
            if let id = item.milestoneId, !seenMilestones.contains(id) { seenMilestones.append(id) }
        }
        for id in seenMilestones {
            guard let title = store.currentSeason.milestones.first(where: { $0.id == id })?.title else { continue }
            result.append(.milestone(id: id, title: title))
        }

        if items.contains(where: { $0.todoId != nil }) { result.append(.anyTodo) }
        if items.contains(where: { $0.noteId != nil }) { result.append(.anyNote) }
        return result
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(availableFilters) { option in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.18)) { filter = option }
                    } label: {
                        Text(option.label)
                            .font(.sans(12.5, weight: filter == option ? .semibold : .regular))
                            .foregroundStyle(filter == option ? Theme.paperCream : Theme.textPrimary.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(filter == option ? Theme.textPrimary : Theme.textPrimary.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(Theme.paperCream)
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nothing here yet")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("No proofs are tied to \(filter.label.lowercased()) — pin one from the capture screen and it'll show up here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            Theme.paperCream.ignoresSafeArea()

            if store.proofLibraryNewestFirst.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar
                    if visibleItems.isEmpty {
                        noMatchesState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(visibleItems) { item in
                                    tile(item)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
        .navigationTitle("Proof library")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerItem) { item in
            ProofLibraryViewerView(item: item)
                .environment(store)
        }
        .confirmationDialog(
            "Remove this proof from your library?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from library", role: .destructive) {
                if let item = pendingDelete {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    store.deleteProofLibraryItem(item.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Pins and posts made from it are not affected.")
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(_ item: ProofLibraryItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewerItem = item
        } label: {
            Color.black.opacity(0.15)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .overlay {
                    ProofLibraryThumb(item: item)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: item.isPrivateToMe ? "lock.fill" : "paperplane.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text(shortDate(item.createdAt))
                            .font(.sans(9, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(6)
                    .allowsHitTesting(false)
                }
                .overlay {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Remove from library", systemImage: "trash")
            }
        }
        .accessibilityLabel("Proof from \(shortDate(item.createdAt))")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            Text("No proofs archived yet")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Every proof you post or save lands here —\neven after it leaves your story.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Thumbnail

/// Lazily-loaded thumbnail for a library tile — a frame for videos,
/// the downscaled photo otherwise.
private struct ProofLibraryThumb: View {
    let item: ProofLibraryItem

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .video ? "video" : "photo")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .task(id: item.filename) {
            image = await load()
        }
    }

    private func load() async -> UIImage? {
        guard let url = item.url else { return nil }
        if item.kind == .video {
            return await VideoThumbnailService.thumbnail(for: url, maxDimension: 360)
        }
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}

// MARK: - Viewer

/// Full-screen viewer for one archived proof — the composed card on a
/// dark backdrop with its date, source, and everywhere it was pinned.
struct ProofLibraryViewerView: View {
    let item: ProofLibraryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            media
                .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fullDate)
                            .font(.sans(13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(sourceLine)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close proof")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                if !item.pinnedLabels.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(45))
                        Text("Pinned to \(item.pinnedLabels.joined(separator: " · "))")
                            .font(.sans(12, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 28)
                }
            }
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var media: some View {
        if item.kind == .video, let url = item.url {
            VideoLoopView(url: url, gravity: .resizeAspect)
                .id(url)
        } else if let url = item.url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                Text("Proof unavailable")
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private var fullDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: item.createdAt)
    }

    /// Where this proof went, rather than just how it was made. Now
    /// that a private send is archived too, "Saved on this device" was
    /// true and useless — it read identically for a proof nobody ever
    /// saw and one sent to a friend an hour ago.
    private var sourceLine: String {
        guard !item.sharedTo.isEmpty else { return "Just for you" }
        let places = item.sharedTo.map { destination -> String in
            switch destination {
            case .story: return "your story"
            case .circle: return "a circle"
            case .friend: return "a friend"
            }
        }
        switch places.count {
        case 1: return "Sent to \(places[0])"
        case 2: return "Sent to \(places[0]) and \(places[1])"
        default: return "Sent to \(places.dropLast().joined(separator: ", ")), and \(places[places.count - 1])"
        }
    }
}

#Preview {
    NavigationStack {
        ProofLibraryView()
            .environment(Store())
    }
}
