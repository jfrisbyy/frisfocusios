//
//  MyProfileView.swift
//  FrisFocus
//
//  The user's own profile page — a faithful mirror of what friends see
//  when they visit: the custom header (or signature-color band), the
//  story-ringed avatar, name, handle, season line, and the day below,
//  built from the user's *real* tasks, routines, focus, and milestones
//  via `Store.myDay`.
//
//  A three-way Quiet / Open / Full switcher previews exactly what each
//  sharing tier reveals, crossfading the day section between levels.
//  The action pills (Proof, Message, Cheer) render where friends see
//  them but are clearly marked preview-only.
//
//  Edit affordances live right on the page: small camera discs on the
//  header and avatar, an "Edit profile" pill under the name (all
//  routing into the existing edit screen), and a gear up top for the
//  full Account & settings hub.
//

import SwiftUI
import UIKit

struct MyProfileView: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previewTier: VisibilityTier = .full
    @State private var showEditProfile: Bool = false
    @State private var showAccount: Bool = false
    @State private var showMyStories: Bool = false
    @State private var showCheers: Bool = false
    @State private var ringFill: Double = 0
    @State private var storyRingPulse: Bool = false

    /// Zoom-transition namespace — the story player grows out of the
    /// avatar and shrinks back into it on dismiss.
    @Namespace private var storyZoom

    // MARK: - Identity

    private var myId: String? { auth.user?.id }

    private var displayName: String {
        profileStore.myProfile?.displayName ?? auth.user?.name ?? "You"
    }

    private var handle: String? { profileStore.myProfile?.handle }

    private var photoURL: URL? {
        profileStore.myProfile?.photoURL ?? auth.user?.photoURL
    }

    private var headerPhotoURL: URL? { profileStore.myProfile?.headerURL }

    private var initials: String {
        let value = profileStore.myProfile?.initials ?? auth.user?.initials ?? ""
        return value.isEmpty ? "?" : value
    }

    /// My signature color — the band friends see when no header photo
    /// is set. Derived from the account id, same as everywhere else.
    private var accent: Color {
        if let myId { return Color(hex: RemoteIDMapper.accentHex(forRemoteId: myId)) }
        return Theme.textPrimary
    }

    // MARK: - Day

    private var day: FriendDay { store.myDay }

    private var hasStories: Bool { store.hasActiveMyStories }

    private var ringTarget: Double {
        switch previewTier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    hero

                    daySection
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 18)
                        .padding(.bottom, 18)

                    cheersRow
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.bottom, 24)

                    Color.clear.frame(height: 130)
                }
            }
            .background(Theme.warmWheat)
            .ignoresSafeArea(edges: .top)

            SundialNavView(
                active: .subPage,
                onCaptureTap: {},
                onHomeTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                },
                onCirclesTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .edgeSwipeBack()
        .sheet(isPresented: $showEditProfile) {
            NavigationStack {
                EditProfileView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showEditProfile = false }
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            }
        }
        .sheet(isPresented: $showAccount) {
            ProfileSheetView()
        }
        .sheet(isPresented: $showCheers) {
            CheerHistoryView()
                .environment(store)
        }
        .fullScreenCover(isPresented: $showMyStories) {
            StoryPlayerView(mode: .mine)
                .navigationTransition(.zoom(sourceID: "myprofile-story", in: storyZoom))
                .environment(store)
        }
        .onAppear {
            animateRing()
            if hasStories && !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    storyRingPulse = true
                }
            }
        }
        .onChange(of: previewTier) { _, _ in animateRing() }
    }

    private func animateRing() {
        if reduceMotion {
            ringFill = ringTarget
        } else {
            withAnimation(.easeOut(duration: 0.9)) { ringFill = ringTarget }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 54)
                .padding(.horizontal, Theme.pageHorizontalPadding)

            VStack(spacing: 6) {
                avatarBlock

                if hasStories {
                    Text("YOUR STORY · TAP TO VIEW")
                        .font(.sans(10, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                }

                Text(displayName)
                    .font(.serif(27, weight: .medium))
                    .foregroundStyle(Theme.textCream)

                Text(metaLine)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.82))

                editPill
                    .padding(.top, 8)
            }
            .padding(.top, 8)

            previewActionRow
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 16)

            Text("PREVIEW — ONLY FRIENDS SEE THESE BUTTONS")
                .font(.sans(9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.textCream.opacity(0.6))
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(heroBackground)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let handle { parts.append(handle) }
        let season = store.currentSeason.name.replacingOccurrences(of: " Season", with: "")
        if !season.isEmpty {
            parts.append("\(season) · day \(store.currentSeasonDay)")
        }
        return parts.isEmpty ? "This is you" : parts.joined(separator: " · ")
    }

    private var heroBackground: some View {
        let hasPhoto = headerPhotoURL != nil
        return ZStack {
            accent
            if let headerPhotoURL {
                Color.clear
                    .overlay {
                        CachedImage(url: headerPhotoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            accent
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)
            }
            LinearGradient(
                colors: hasPhoto
                    ? [Color.black.opacity(0.48), Color.black.opacity(0.22), Color.black.opacity(0.30)]
                    : [Color.black.opacity(0.34), Color.black.opacity(0.04), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.clear, .clear, Theme.warmWheat.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close your profile")

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showEditProfile = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change your header photo")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAccount = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account and settings")
        }
    }

    // MARK: Avatar

    /// Avatar with the story ring — lit gold (with a slow shimmer)
    /// when there's an active story; a quiet cream ring otherwise.
    /// Tapping plays the story; the small camera disc edits the photo.
    private var avatarBlock: some View {
        Button {
            guard hasStories else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showMyStories = true
        } label: {
            ZStack {
                avatarImage
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .padding(5)
                    .overlay { storyRingOverlay }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasStories)
        .matchedTransitionSource(id: "myprofile-story", in: storyZoom)
        .accessibilityLabel(hasStories ? "Your story — tap to view" : "Your profile photo")
        .overlay(alignment: .bottomTrailing) {
            avatarCameraDisc
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let photoURL {
            CachedImage(url: photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text(initials)
                .font(.serif(26, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var storyRingOverlay: some View {
        if hasStories {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter, Theme.sunCore, Theme.sunWarm],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .opacity(reduceMotion ? 1 : (storyRingPulse ? 1 : 0.6))
        } else {
            Circle().strokeBorder(Theme.textCream.opacity(0.55), lineWidth: 1)
        }
    }

    /// The small charcoal camera disc on the avatar's corner — the
    /// always-present edit affordance, quiet but discoverable.
    private var avatarCameraDisc: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showEditProfile = true
        } label: {
            ZStack {
                Circle().fill(Theme.textPrimary)
                Image(systemName: "camera.fill")
                    .font(.sans(10, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.8), lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 2, y: 2)
        .accessibilityLabel("Change your profile photo")
    }

    private var editPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showEditProfile = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.sans(12, weight: .semibold))
                Text("Edit profile")
                    .font(.sans(13, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.16)))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.textCream.opacity(0.35), lineWidth: 0.8)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit your profile")
    }

    // MARK: Preview action row

    /// The Proof / Message / Cheer pills exactly where friends see
    /// them — visually faithful, but inert: this is your own page.
    private var previewActionRow: some View {
        HStack(spacing: 8) {
            previewActionLabel(icon: "camera.fill", title: "Proof", filled: true)
            previewActionLabel(icon: "bubble.left.and.bubble.right.fill", title: "Message", filled: false)
            previewActionLabel(icon: "hands.clap.fill", title: "Cheer", filled: false)
        }
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Preview of the Proof, Message, and Cheer buttons friends see")
    }

    private func previewActionLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.sans(13, weight: .semibold))
            Text(title)
                .font(.sans(13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Theme.textPrimary : Theme.textCream)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(filled ? Theme.textCream : Color.white.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.textCream.opacity(filled ? 0 : 0.35), lineWidth: 0.8)
        )
    }

    // MARK: - Cheers row

    /// Doorway to the full cheer ledger — every word that ever found
    /// you (and the ones you sent), beyond the day they landed.
    private var cheersRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCheers = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.06))
                    Image(systemName: "hands.clap.fill")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cheers")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Every word that found you")
                        .font(.serifItalic(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View all cheers you’ve received and sent")
    }

    // MARK: - Day section

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR DAY · AS A \(previewTier.tag) FRIEND SEES IT")
                .font(.sans(10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            tierSwitcher

            Text(previewTier.detail)
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if previewTier == .quiet {
                    quietGlance
                } else {
                    dayGlanceCard
                }

                if previewTier == .open {
                    effortBreakdownCard
                }

                if previewTier == .full {
                    fullChecklistCard
                    if !day.routines.isEmpty {
                        routinesCard
                    }
                    focusMilestoneRow
                }

                if previewTier != .quiet {
                    pointsPrivacyRow
                    rhythmFooter
                }
            }
            .transition(.opacity)

            Text("You set a level per friend in Sharing & connection — this is just a preview.")
                .font(.serifItalic(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.25), value: previewTier)
    }

    // MARK: Tier switcher

    private var tierSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(VisibilityTier.allCases, id: \.self) { tier in
                tierPill(tier)
            }
        }
    }

    private func tierPill(_ tier: VisibilityTier) -> some View {
        let isSelected = previewTier == tier
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) { previewTier = tier }
        } label: {
            Text(tierName(tier))
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.textCream : Theme.textPrimary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textPrimary : Color.white.opacity(0.6))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(isSelected ? 0 : 0.12), lineWidth: 0.5)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview as a \(tierName(tier)) friend")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tierName(_ tier: VisibilityTier) -> String {
        switch tier {
        case .quiet: return "Quiet"
        case .open: return "Open"
        case .full: return "Full"
        }
    }

    // MARK: Quiet glance

    private var quietGlance: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.sans(16, weight: .regular))
                    .foregroundStyle(accent)
                    .padding(.top, 2)
                Text(day.moodLine)
                    .font(.serifItalic(17, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text("\(store.currentSeason.name.replacingOccurrences(of: " Season", with: "")) · day \(store.currentSeasonDay)")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glanceBackground)
    }

    // MARK: Day at a glance

    private var dayGlanceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            dayRing
            VStack(alignment: .leading, spacing: 6) {
                Text(day.moodLine)
                    .font(.serifItalic(18, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                if previewTier == .open {
                    Text("The shape of your day — no task names.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                } else if day.openCount > 0 {
                    Text("\(day.openCount) still open — the day’s not over.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glanceBackground)
    }

    private var dayRing: some View {
        DayProgressRing(fraction: ringFill, tint: accent, lineWidth: 9) {
            Group {
                if previewTier == .full {
                    VStack(spacing: 0) {
                        Text("\(day.doneCount)")
                            .font(.serif(28, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(day.totalCount)")
                            .font(.sans(10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    }
                } else {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement()
        .accessibilityLabel(previewTier == .full ? "\(day.doneCount) of \(day.totalCount) done today" : "Showing up")
    }

    // MARK: Full — checklist

    private var fullChecklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR LIST · \(day.doneCount) OF \(day.totalCount) DONE")
            if day.totalCount == 0 {
                Text("Nothing planned today yet — friends would see an open day.")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(card)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(day.categoryBreakdown.enumerated()), id: \.element.category) { idx, group in
                        if idx > 0 {
                            Rectangle().fill(Theme.textPrimary.opacity(0.06)).frame(height: 0.5)
                                .padding(.horizontal, 14)
                        }
                        categoryGroup(group.category, done: group.done, total: group.total)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card)
            }
        }
    }

    private func categoryGroup(_ category: Category, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(category.color).frame(width: 7, height: 7)
                Text(category.displayName.uppercased())
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(category.darkColor)
                Spacer()
                Text("\(done) of \(total)")
                    .font(.sans(11, weight: .medium))
                    .foregroundStyle(done == total ? Theme.alertGreen : Theme.textPrimary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 4)

            ForEach(tasksInCategory(category)) { task in
                checklistRow(task)
            }
        }
        .padding(.bottom, 9)
    }

    private func tasksInCategory(_ category: Category) -> [FriendDayTask] {
        day.tasks
            .filter { $0.category == category }
            .sorted { $0.isDone && !$1.isDone }
    }

    private func checklistRow(_ task: FriendDayTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.sans(15, weight: task.isDone ? .semibold : .regular))
                .foregroundStyle(task.isDone ? Theme.alertGreen : Theme.textPrimary.opacity(0.25))
            Text(task.title)
                .font(.sans(14, weight: task.isDone ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(task.isDone ? 0.9 : 0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .accessibilityLabel("\(task.title), \(task.isDone ? "done" : "still open")")
    }

    // MARK: Open — effort by category

    @ViewBuilder
    private var effortBreakdownCard: some View {
        let groups = day.categoryBreakdown.filter { $0.done > 0 }
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("WHERE YOUR EFFORT WENT")
            if groups.isEmpty {
                Text("Nothing logged yet — Open friends would see a quiet day so far.")
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(card)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    effortSegmentBar(groups)
                    FlowLayout(spacing: 12, lineSpacing: 8) {
                        ForEach(groups, id: \.category) { group in
                            HStack(spacing: 5) {
                                Circle().fill(group.category.color).frame(width: 7, height: 7)
                                Text("\(group.category.displayName) · \(group.done)")
                                    .font(.sans(12, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                            }
                        }
                    }
                    Text("Counts only — your task names stay private at this level.")
                        .font(.serifItalic(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card)
            }
        }
    }

    private func effortSegmentBar(_ groups: [(category: Category, done: Int, total: Int)]) -> some View {
        let totalDone = max(1, groups.reduce(0) { $0 + $1.done })
        return GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(groups, id: \.category) { group in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(group.category.color.opacity(0.85))
                        .frame(width: max(8, (proxy.size.width - CGFloat(groups.count - 1) * 3) * CGFloat(group.done) / CGFloat(totalDone)))
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Effort by category")
    }

    // MARK: Full — routines

    private var routinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ROUTINES TODAY")
            VStack(spacing: 0) {
                ForEach(Array(day.routines.enumerated()), id: \.element.id) { idx, routine in
                    if idx > 0 {
                        Rectangle().fill(Theme.textPrimary.opacity(0.07)).frame(height: 0.5)
                    }
                    routineRow(routine)
                }
            }
            .background(card)
        }
    }

    private func routineRow(_ routine: FriendRoutine) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(routine.isComplete ? Theme.alertGreen : Theme.sunWarm.opacity(0.28))
                    .frame(width: 26, height: 26)
                Image(systemName: routine.isComplete ? "checkmark" : "square.fill")
                    .font(.sans(routine.isComplete ? 12 : 9, weight: .bold))
                    .foregroundStyle(routine.isComplete ? Theme.textCream : Theme.sunShadow)
            }
            Text(routine.title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(routine.detail)
                .font(.sans(12, weight: routine.isComplete ? .medium : .regular))
                .foregroundStyle(routine.isComplete ? Theme.alertGreen : Theme.textPrimary.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Full — focus + milestone

    private var focusMilestoneRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FOCUS")
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text(day.focusText)
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(day.focusSessions) session\(day.focusSessions == 1 ? "" : "s")")
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Theme.textPrimary.opacity(0.08))
                .frame(width: 0.5)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(day.milestoneTitle.isEmpty ? "MILESTONE" : day.milestoneTitle.uppercased())
                    .font(.sans(9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
                Text(day.milestoneProgress)
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(day.milestoneAddedToday ? "+ today" : "no change")
                    .font(.sans(10, weight: .medium))
                    .foregroundStyle(day.milestoneAddedToday ? Theme.alertGreen : Theme.textPrimary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(card)
    }

    // MARK: Points privacy + rhythm

    /// Points are private calibration — friends must ask and you
    /// approve each one. Shown here so the preview reads honestly.
    private var pointsPrivacyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("Exact points stay private — friends ask, you approve each one.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(card)
    }

    private var rhythmFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Showing up \(day.rhythmDays) days · \(day.rhythmSummary)")
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                miniSparkline
                Text("LAST 10 DAYS")
                    .font(.sans(8, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card)
    }

    private var miniSparkline: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(day.rhythmBars.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(v < 0.18 ? Theme.textPrimary.opacity(0.14) : accent.opacity(0.5))
                    .frame(width: 5, height: max(5, 26 * v))
            }
        }
        .frame(height: 26)
    }

    // MARK: - Shared helpers

    private var card: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var glanceBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(accent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.20), lineWidth: 0.5)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sans(10, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
    }
}
