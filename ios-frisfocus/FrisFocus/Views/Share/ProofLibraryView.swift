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
    case todo(id: UUID, title: String)
    case note(id: UUID, title: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .keptOnly: return "kept"
        case .shared: return "shared"
        case .task(let id, _): return "task-\(id.uuidString)"
        case .milestone(let id, _): return "milestone-\(id.uuidString)"
        case .todo(let id, _): return "todo-\(id.uuidString)"
        case .note(let id, _): return "note-\(id.uuidString)"
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .keptOnly: return "Just for me"
        case .shared: return "Shared"
        case .task(_, let title): return title
        case .milestone(_, let title): return title
        case .todo(_, let title): return title
        case .note(_, let title): return title
        }
    }

    func admits(_ item: ProofLibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .keptOnly: return item.isPrivateToMe
        case .shared: return !item.isPrivateToMe
        case .task(let id, _): return item.taskId == id
        case .milestone(let id, _): return item.milestoneId == id
        case .todo(let id, _): return item.todoId == id
        case .note(let id, _): return item.noteId == id
        }
    }
}

struct ProofLibraryView: View {
    @Environment(Store.self) private var store
    /// Optional for local-only previews; production inherits the root service.
    @Environment(ProofLibrarySyncService.self) private var proofSync: ProofLibrarySyncService?

    @State private var viewerItem: ProofLibraryItem?
    @State private var pendingDelete: ProofLibraryItem?
    @State private var filter: ProofLibraryFilter = .all
    /// Which family of filters is unfolded beneath the top row — Tasks,
    /// Milestones, To-dos, or Notes. One at a time; nil = all folded.
    @State private var openGroup: ProofFilterGroup?

    /// The proofs the current filter admits, newest first.
    private var visibleItems: [ProofLibraryItem] {
        store.proofLibraryNewestFirst.filter { filter.admits($0) }
    }

    /// The visible proofs grouped into month shelves, newest month
    /// first — the way a camera roll remembers. Items inside a month
    /// keep their newest-first order.
    private var monthSections: [(id: String, title: String, items: [ProofLibraryItem])] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [ProofLibraryItem]] = [:]
        for item in visibleItems {
            let comps = calendar.dateComponents([.year, .month], from: item.createdAt)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        let now = Date()
        return order.map { key in
            let items = buckets[key] ?? []
            let date = items.first?.createdAt ?? now
            let title: String
            if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                title = "This month"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                title = date.formatted(.dateTime.month(.wide))
            } else {
                title = date.formatted(.dateTime.month(.wide).year())
            }
            return (id: key, title: title, items: items)
        }
    }

    /// A family of narrow filters — every task that has proofs, every
    /// milestone that has proofs — folded under one pill that carries the
    /// family's total. Twenty task names in a row was a wall; four
    /// families is a menu.
    enum ProofFilterGroup: String, Identifiable, CaseIterable {
        case tasks, milestones, todos, notes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tasks: return "Tasks"
            case .milestones: return "Milestones"
            case .todos: return "To-dos"
            case .notes: return "Notes"
            }
        }
    }

    /// One member of a family: the filter it applies and how many proofs
    /// it would show.
    struct ProofFilterEntry: Identifiable {
        let filter: ProofLibraryFilter
        let count: Int
        var id: String { filter.id }
    }

    /// The members of each family, counted, only for things that
    /// actually HAVE proofs — a filter for a task with nothing attached
    /// is a dead end, so it isn't built.
    private var groupEntries: [ProofFilterGroup: [ProofFilterEntry]] {
        let items = store.proofLibraryNewestFirst
        var result: [ProofFilterGroup: [ProofFilterEntry]] = [:]

        var taskCounts: [UUID: Int] = [:]
        var milestoneCounts: [UUID: Int] = [:]
        var todoCounts: [UUID: Int] = [:]
        var noteCounts: [UUID: Int] = [:]
        for item in items {
            if let id = item.taskId { taskCounts[id, default: 0] += 1 }
            if let id = item.milestoneId { milestoneCounts[id, default: 0] += 1 }
            if let id = item.todoId { todoCounts[id, default: 0] += 1 }
            if let id = item.noteId { noteCounts[id, default: 0] += 1 }
        }

        result[.tasks] = store.tasks.compactMap { task in
            guard let count = taskCounts[task.id] else { return nil }
            return ProofFilterEntry(filter: .task(id: task.id, title: task.title), count: count)
        }
        result[.milestones] = store.currentSeason.milestones.compactMap { milestone in
            guard let count = milestoneCounts[milestone.id] else { return nil }
            return ProofFilterEntry(filter: .milestone(id: milestone.id, title: milestone.title), count: count)
        }
        result[.todos] = store.todos.compactMap { todo in
            guard let count = todoCounts[todo.id] else { return nil }
            return ProofFilterEntry(filter: .todo(id: todo.id, title: todo.title), count: count)
        }
        result[.notes] = store.notes.compactMap { note in
            guard let count = noteCounts[note.id] else { return nil }
            return ProofFilterEntry(filter: .note(id: note.id, title: Self.noteTitle(note)), count: count)
        }
        return result
    }

    /// A note has no title field; its first line stands in.
    private static func noteTitle(_ note: Note) -> String {
        let firstLine = (note.body ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty {
            return note.createdAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return firstLine.count > 28 ? String(firstLine.prefix(28)) + "…" : firstLine
    }

    /// Total proofs across a family, for its pill.
    private func groupTotal(_ group: ProofFilterGroup, entries: [ProofFilterGroup: [ProofFilterEntry]]) -> Int {
        (entries[group] ?? []).reduce(0) { $0 + $1.count }
    }

    /// The family a narrow filter belongs to, so its pill reads selected
    /// while one of its members is active.
    private func group(of filter: ProofLibraryFilter) -> ProofFilterGroup? {
        switch filter {
        case .task: return .tasks
        case .milestone: return .milestones
        case .todo: return .todos
        case .note: return .notes
        case .all, .keptOnly, .shared: return nil
        }
    }

    private var filterBar: some View {
        let entries = groupEntries
        let items = store.proofLibraryNewestFirst
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterPill(label: "All", count: nil, selected: filter == .all) {
                        select(.all)
                    }
                    if items.contains(where: { $0.isPrivateToMe }) {
                        filterPill(label: "Just for me", count: nil, selected: filter == .keptOnly) {
                            select(.keptOnly)
                        }
                    }
                    if items.contains(where: { !$0.isPrivateToMe }) {
                        filterPill(label: "Shared", count: nil, selected: filter == .shared) {
                            select(.shared)
                        }
                    }
                    ForEach(ProofFilterGroup.allCases) { group in
                        let total = groupTotal(group, entries: entries)
                        if total > 0 {
                            let active = openGroup == group || self.group(of: filter) == group
                            filterPill(
                                label: group.label,
                                count: total,
                                selected: active,
                                chevron: openGroup == group ? "chevron.up" : "chevron.down"
                            ) {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    openGroup = openGroup == group ? nil : group
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }

            if let openGroup, let members = entries[openGroup], !members.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(members) { entry in
                            filterPill(
                                label: entry.filter.label,
                                count: entry.count,
                                selected: filter == entry.filter,
                                subtle: true
                            ) {
                                select(entry.filter)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.paperCream)
    }

    private func select(_ option: ProofLibraryFilter) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.18)) {
            filter = option
            // Picking a fixed filter folds whatever family was open —
            // it no longer describes what is on screen.
            if group(of: option) == nil { openGroup = nil }
        }
    }

    /// One pill. `count` rides as a quiet number after the label; the
    /// family pills carry a chevron for their fold state; members of an
    /// open family draw lighter so the two rows read as parent + child.
    private func filterPill(
        label: String,
        count: Int?,
        selected: Bool,
        chevron: String? = nil,
        subtle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.sans(12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.sans(11, weight: .medium))
                        .opacity(selected ? 0.75 : 0.5)
                }
                if let chevron {
                    Image(systemName: chevron)
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Theme.paperCream : Theme.textPrimary.opacity(subtle ? 0.65 : 0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    selected
                        ? Theme.textPrimary
                        : Theme.textPrimary.opacity(subtle ? 0.05 : 0.07)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    /// One month shelf's pinned label — quiet, but stays put while its
    /// grid scrolls under it, so "where am I in time" is always answered.
    private func monthHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("\(count)")
                .font(.sans(11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.paperCream.opacity(0.96))
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
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(monthSections, id: \.id) { section in
                                    Section {
                                        LazyVGrid(columns: columns, spacing: 6) {
                                            ForEach(section.items) { item in
                                                tile(item)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 18)
                                    } header: {
                                        monthHeader(section.title, count: section.items.count)
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 40)
                        }
                        .refreshable { await proofSync?.refresh(forceMedia: true) }
                    }
                }
            }
        }
        .navigationTitle("Proof library")
        .navigationBarTitleDisplayMode(.inline)
        // Opening the archive is an explicit request for the bytes. The
        // background sweep is Wi-Fi-only by design, which used to mean a
        // restored library rendered as a grid of empty tiles on cellular
        // — patient behaviour that read as a broken screen.
        .task(id: proofSync?.myUserId) {
            Log.proofLibrary.debug("archive: opened, sync attached=\(proofSync?.myUserId != nil)")
            await proofSync?.refresh(forceMedia: true)
        }
        .safeAreaInset(edge: .bottom) { restoringPill }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await proofSync?.refresh(forceMedia: true) }
                }
                .disabled(proofSync?.isRestoring == true || proofSync?.isFetchingMedia == true)
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            // A pager over what the grid is currently showing, opened on
            // the tapped proof: swiping left and right walks the shelf
            // without coming back out to the grid each time.
            ProofLibraryPagerView(items: visibleItems, initial: item)
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
                    ProofLibraryThumb(item: item, mediaRevision: proofSync?.downloadRevisions[item.id] ?? 0, isDownloading: proofSync?.activeDownloads.contains(item.filename) == true)
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

    /// Quiet marker while archive media this device doesn't have yet is
    /// coming down from the account.
    @ViewBuilder
    private var restoringPill: some View {
        if let proofSync, let message = proofSync.restoreError ?? (proofSync.failedDownloads.isEmpty ? nil : "Some proofs couldn't download. Please try again.") {
            VStack(spacing: 8) {
                Text(message).font(.sans(12, weight: .medium))
                Button("Try again") { Task { await proofSync.refresh(forceMedia: true) } }
                    .frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
            .padding(12)
            .background(Theme.paperCream)
        } else if let proofSync, proofSync.isRestoring || proofSync.isFetchingMedia {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.textPrimary)
                Text(proofSync.isRestoring ? "Refreshing your archive…" : "Bringing proofs back from your account…")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.sunWarm.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            .padding(.bottom, 18)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
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
    /// The sync service's byte-arrival counter. Part of the load id, so a
    /// tile that rendered before its media existed reloads the instant
    /// the file lands rather than holding a placeholder until relaunch.
    let mediaRevision: Int
    let isDownloading: Bool

    @State private var image: UIImage?
    @State private var didAttempt: Bool = false

    /// The bytes are on the server but not on this device — worth a
    /// spinner, not a broken-file glyph.
    private var isPending: Bool {
        guard image == nil, didAttempt, isDownloading else { return false }
        guard let url = item.url else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isPending {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.7))
            } else {
                Image(systemName: item.kind == .video ? "video" : "photo")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .task(id: "\(item.filename)#\(mediaRevision)") {
            let loaded = await load()
            guard !Task.isCancelled else { return }
            didAttempt = true
            if loaded != nil || image == nil { image = loaded }
        }
    }

    private func load() async -> UIImage? {
        guard let url = item.url,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if item.kind == .video {
            return await VideoThumbnailService.thumbnail(for: url, maxDimension: 360)
        }
        return await LocalThumbnailLoader.load(url: url, maxDimension: 360)
    }
}

// MARK: - Pager

/// Horizontal pages of viewers over a list of proofs. Each page is the
/// full single-proof viewer, so close, date, and pins travel with it.
struct ProofLibraryPagerView: View {
    let items: [ProofLibraryItem]
    let initial: ProofLibraryItem

    @State private var selection: UUID

    init(items: [ProofLibraryItem], initial: ProofLibraryItem) {
        self.items = items.isEmpty ? [initial] : items
        self.initial = initial
        _selection = State(initialValue: initial.id)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(items) { item in
                ProofLibraryViewerView(item: item, position: position(of: item))
                    .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
    }

    /// "3 of 12" for the header, so a swipe has somewhere to be going.
    private func position(of item: ProofLibraryItem) -> String? {
        guard items.count > 1, let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "\(index + 1) of \(items.count)"
    }
}

// MARK: - Viewer

/// Full-screen viewer for one archived proof — the composed card on a
/// dark backdrop with its date, source, and everywhere it was pinned.
struct ProofLibraryViewerView: View {
    let item: ProofLibraryItem
    /// Where this proof sits in the pager ("3 of 12"), nil when alone.
    var position: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(ProofLibrarySyncService.self) private var proofSync: ProofLibrarySyncService?

    @State private var image: UIImage?
    @State private var didAttempt: Bool = false

    /// On the server, not yet on this device.
    private var isPending: Bool {
        guard proofSync?.activeDownloads.contains(item.filename) == true || proofSync?.isRestoring == true,
              let url = item.url else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

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
                        Text(position.map { "\(sourceLine) · \($0)" } ?? sourceLine)
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
        // Pull the bytes on demand rather than declaring the proof gone.
        // "Proof unavailable" over a file that was simply waiting for
        // Wi-Fi is the cruellest possible sentence to show someone about
        // their own archive.
        .task(id: item.id) { await proofSync?.refresh(forceMedia: true) }
        .task(id: "\(item.filename)#\(proofSync?.downloadRevisions[item.id] ?? 0)") {
            let loaded = await loadImage()
            guard !Task.isCancelled else { return }
            image = loaded
            didAttempt = true
        }
    }

    @ViewBuilder
    private var media: some View {
        if item.kind == .video, let url = item.url,
           FileManager.default.fileExists(atPath: url.path) {
            VideoLoopView(url: url, gravity: .resizeAspect)
                .id(url)
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if isPending || !didAttempt {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.white.opacity(0.8))
                Text("Bringing this proof back from your account…")
                    .font(.sans(13, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 40)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                Text("This proof isn't available on this device yet.")
                    .font(.sans(13, weight: .medium))
                Text("Try refreshing. If its media was never backed up, open FrisFocus on the device where you made it and connect to Wi-Fi.")
                    .font(.sans(12, weight: .regular))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Try again") {
                    Task { await proofSync?.refresh(forceMedia: true) }
                }
                .frame(minHeight: 44)
            }
            .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private func loadImage() async -> UIImage? {
        guard item.kind != .video,
              let url = item.url,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
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
