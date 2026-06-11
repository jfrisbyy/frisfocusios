//
//  CircleSettingsSheet.swift
//  FrisFocus
//
//  Settings for a circle: governance toggle (owner-only), member
//  roster with role controls, shared-task management (gated by role
//  and the governance toggle), and the pending review queue for
//  owner/admin.
//
//  Default friend circles never see the governance UI light up —
//  the toggle is off, the request queue is empty, and the task
//  rows just apply edits directly for whoever has permission.
//

import SwiftUI
import PhotosUI
import UIKit

/// Identifiable wrapper so `fullScreenCover(item:)` can present the
/// header crop screen for a freshly picked circle banner.
private struct CircleHeaderCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CircleSettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(GoldenHourService.self) private var goldenHour
    @Environment(\.dismiss) private var dismiss

    let circleId: UUID

    /// Header photo flow.
    @State private var headerPhotoItem: PhotosPickerItem?
    @State private var headerCropTarget: CircleHeaderCropTarget?
    @State private var isUploadingHeader: Bool = false

    /// The member whose profile is open, if any.
    @State private var profileTarget: ProfileTarget?

    @State private var showGoldenSettings: Bool = false
    @State private var showGoldenHour: Bool = false
    @State private var showAddTaskForm: Bool = false
    @State private var editingTaskId: UUID?
    @State private var draftTitle: String = ""
    @State private var transientBanner: String?
    @State private var bannerTask: Task<Void, Never>?

    // Shared-goals (mode switching) state.
    @State private var showNumberForm: Bool = false
    @State private var numberUnit: String = ""
    @State private var numberTarget: String = ""
    @State private var showOurStory: Bool = false

    private var circle: FFCircle? {
        store.circles.first { $0.id == circleId }
    }

    var body: some View {
        NavigationStack {
            if let circle {
                content(for: circle)
                    .navigationTitle("Circle settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .font(.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
            } else {
                Text("Circle unavailable.")
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .profileDestination($profileTarget, store: store)
        .onChange(of: headerPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedHeader(newItem) }
        }
        .fullScreenCover(item: $headerCropTarget) { target in
            ProfileHeaderCropView(image: target.image) { baked in
                uploadHeader(baked)
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func content(for circle: FFCircle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let banner = transientBanner {
                    bannerView(text: banner)
                }

                headerPhotoSection(for: circle)

                ourStoryRow(for: circle)

                goldenHourRow(for: circle)

                if store.canManageTasks(in: circle) {
                    sharedGoalsSection(for: circle)
                }

                if store.isOwner(of: circle) {
                    governanceSection(for: circle)
                }

                if store.canManageTasks(in: circle) {
                    pendingRequestsSection(for: circle)
                }

                if circle.hasSharedList {
                    sharedTasksSection(for: circle)
                }

                membersSection(for: circle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 48)
        }
        .background(Theme.warmWheat)
        .sheet(isPresented: $showOurStory) {
            CircleStoryView(circleId: circleId)
                .environment(store)
        }
        .sheet(isPresented: $showGoldenSettings) {
            GoldenHourSettingsSheet(
                circleId: circleId,
                circleName: circle.name,
                myUserId: auth.user?.id ?? "",
                canManage: store.canManageTasks(in: circle)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showGoldenHour) {
            GoldenHourHostView(circleId: circleId)
        }
    }

    // MARK: - Header photo

    /// The circle's shared banner. Everyone sees the picture; owners
    /// and admins get the add / change / remove controls. Without a
    /// photo (and without edit rights) the section stays invisible.
    @ViewBuilder
    private func headerPhotoSection(for circle: FFCircle) -> some View {
        let canEdit = store.canManageTasks(in: circle)
        if circle.headerURL != nil || isUploadingHeader || canEdit {
            VStack(alignment: .leading, spacing: 10) {
                if circle.headerURL != nil || isUploadingHeader {
                    headerBanner(for: circle, canEdit: canEdit)
                } else if canEdit {
                    addHeaderButton
                }
            }
        }
    }

    private func headerBanner(for circle: FFCircle, canEdit: Bool) -> some View {
        Theme.textPrimary.opacity(0.08)
            .frame(height: 140)
            .overlay {
                if let url = circle.headerURL {
                    CachedImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Theme.textPrimary.opacity(0.08)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if isUploadingHeader {
                    ZStack {
                        Color.black.opacity(0.25)
                        ProgressView().tint(.white)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if canEdit {
                    HStack(spacing: 8) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.setCircleHeader(nil, in: circleId)
                            showBanner("Header photo removed.")
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove header photo")

                        PhotosPicker(selection: $headerPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change header photo")
                    }
                    .padding(10)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Circle header photo")
    }

    private var addHeaderButton: some View {
        PhotosPicker(selection: $headerPhotoItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.sans(15, weight: .semibold))
                Text("Add a header photo")
                    .font(.sans(14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.75))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.18),
                                  style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a header photo for this circle")
    }

    private func loadPickedHeader(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            headerCropTarget = CircleHeaderCropTarget(image: image)
        }
        headerPhotoItem = nil
    }

    private func uploadHeader(_ image: UIImage) {
        guard let myId = auth.user?.id else { return }
        isUploadingHeader = true
        Task {
            let uploaded = await profileStore.uploadHeader(image, myUserId: myId)
            isUploadingHeader = false
            if let uploaded {
                store.setCircleHeader(uploaded, in: circleId)
                showBanner("Header photo updated.")
            }
        }
    }

    // MARK: - Golden Hour

    /// True when this circle lives on the server — the Golden Hour
    /// service knows its settings row. Sample circles never do, so they
    /// get the explainer instead of a silently failing setup sheet.
    private var isGoldenBacked: Bool {
        goldenHour.settingsByCircle[circleId] != nil
    }

    /// The gold Golden Hour row — the same card that lives on the shared
    /// circle page. Opens the golden surface while a moment is live or
    /// viewing; otherwise the settings sheet. Sample circles get a quiet
    /// explainer pointing at shared circles.
    @ViewBuilder
    private func goldenHourRow(for circle: FFCircle) -> some View {
        if isGoldenBacked {
            let now = Date()
            let settings = goldenHour.settingsByCircle[circleId]
            let moment = goldenHour.currentMoment(for: circleId, now: now)
            let phase = moment?.phase(at: now)
            let isActive = phase == .live || phase == .viewing
            let myUserId = auth.user?.id ?? ""
            let streak = goldenHour.streak(circleId: circleId, userId: myUserId, now: now)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isActive {
                    showGoldenHour = true
                } else {
                    showGoldenSettings = true
                }
            } label: {
                HStack(spacing: 12) {
                    goldenIcon

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Golden Hour")
                                .font(.sans(15, weight: .semibold))
                                .foregroundStyle(GoldenTheme.cream)
                            if phase == .live {
                                Text("LIVE")
                                    .font(.sans(9, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(GoldenTheme.ink)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(GoldenTheme.gold))
                            }
                        }
                        Text(goldenStatusLine(settings: settings, phase: phase, canManage: store.canManageTasks(in: circle)))
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(GoldenTheme.cream.opacity(0.62))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if streak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(streak)")
                                .font(.sans(12, weight: .bold))
                        }
                        .foregroundStyle(GoldenTheme.gold)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GoldenTheme.gold.opacity(0.7))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(GoldenTheme.ink)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(GoldenTheme.gold.opacity(isActive ? 0.6 : 0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "Golden Hour is live. Open it." : "Golden Hour settings")
        } else {
            HStack(spacing: 12) {
                goldenIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text("Golden Hour")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(GoldenTheme.cream)
                    Text("The daily synchronized moment runs in shared circles — start one with friends to set it up.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(GoldenTheme.cream.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(GoldenTheme.ink)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(GoldenTheme.gold.opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var goldenIcon: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(GoldenTheme.ink)
            .frame(width: 38, height: 38)
            .background(Circle().fill(GoldenTheme.goldGradient))
    }

    private func goldenStatusLine(settings: GoldenHourSettings?, phase: GoldenHourPhase?, canManage: Bool) -> String {
        guard let settings, settings.enabled else {
            return canManage ? "Off — set up the daily moment" : "Off for this circle"
        }
        switch phase {
        case .live: return "Capture window is open right now"
        case .viewing: return "The wall is open — it disappears soon"
        case .over: return "Done for today · \(settings.mode.title)"
        default: return "On · \(settings.mode.title)"
        }
    }

    // MARK: - Our story entry

    private func ourStoryRow(for circle: FFCircle) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showOurStory = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.06)).frame(width: 38, height: 38)
                    Image(systemName: "book.closed")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Our story")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(storySubtitle(for: circle))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(14)
            .background(cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Our story")
    }

    private func storySubtitle(for circle: FFCircle) -> String {
        let n = circle.chapters.count
        if n <= 1 { return "A lookback on your time together" }
        return "\(n) chapters of your time together"
    }

    // MARK: - Shared goals (mode switching)

    private func sharedGoalsSection(for circle: FFCircle) -> some View {
        sectionContainer(title: "Shared goals", eyebrow: circle.type.shortEyebrow) {
            VStack(spacing: 10) {
                sharedListGoalCard(for: circle)
                sharedNumberGoal(for: circle)
                goalsFootnote(for: circle)
            }
        }
    }

    @ViewBuilder
    private func sharedListGoalCard(for circle: FFCircle) -> some View {
        if circle.hasSharedList {
            goalCard(
                icon: "checklist",
                tint: CircleType.parallel.tint,
                tintDark: CircleType.parallel.tintDark,
                title: "Shared list",
                detail: circle.tasks.isEmpty ? "Everyone runs the same checklist" : "\(circle.tasks.count) shared task\(circle.tasks.count == 1 ? "" : "s")",
                active: true,
                actionLabel: "Set aside",
                destructive: true,
                action: {
                    _ = store.removeCircleLayer(.sharedList, from: circle.id)
                    showBanner("List set aside — your tasks are kept.")
                }
            )
        } else {
            goalCard(
                icon: "checklist",
                tint: CircleType.parallel.tint,
                tintDark: CircleType.parallel.tintDark,
                title: "Shared list",
                detail: circle.tasks.isEmpty ? "Everyone runs the same checklist each day" : "Resume your \(circle.tasks.count) tasks — they're still here",
                active: false,
                actionLabel: "Add",
                destructive: false,
                action: {
                    _ = store.addCircleLayer(.sharedList, to: circle.id)
                    showBanner("Shared list added.")
                }
            )
        }
    }

    @ViewBuilder
    private func sharedNumberGoal(for circle: FFCircle) -> some View {
        if circle.hasSharedNumber {
            goalCard(
                icon: "number",
                tint: CircleType.collective.tint,
                tintDark: CircleType.collective.tintDark,
                title: "Shared number",
                detail: numberDetail(for: circle),
                active: true,
                actionLabel: "Set aside",
                destructive: true,
                action: {
                    _ = store.removeCircleLayer(.sharedNumber, from: circle.id)
                    showBanner("Number set aside — the running total is kept.")
                }
            )
        } else if showNumberForm {
            numberForm(for: circle)
        } else {
            goalCard(
                icon: "number",
                tint: CircleType.collective.tint,
                tintDark: CircleType.collective.tintDark,
                title: "Shared number",
                detail: circle.collectiveTarget != nil ? "Resume \(numberDetail(for: circle)) — the total's still there" : "One number you build toward together",
                active: false,
                actionLabel: "Add",
                destructive: false,
                action: {
                    numberUnit = circle.collectiveUnit ?? ""
                    numberTarget = circle.collectiveTarget.map { circleNumber($0) } ?? ""
                    withAnimation(.easeInOut(duration: 0.18)) { showNumberForm = true }
                }
            )
        }
    }

    @ViewBuilder
    private func goalsFootnote(for circle: FFCircle) -> some View {
        if circle.objectives.isEmpty {
            Text("This is a Witness circle — pure presence. Add a goal anytime, or keep it a calm room.")
                .font(.serifItalic(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } else if circle.objectives.count == 2 {
            Text("Running two goals at once. Set one aside anytime to keep things simple.")
                .font(.serifItalic(12, weight: .regular))
                .foregroundStyle(CircleType.hybrid.tintDark.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private func numberDetail(for circle: FFCircle) -> String {
        let unit = circle.collectiveUnit ?? ""
        if let target = circle.collectiveTarget {
            return "\(circleNumber(target)) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        return unit.isEmpty ? "One number, together" : unit
    }

    private func goalCard(
        icon: String,
        tint: Color,
        tintDark: Color,
        title: String,
        detail: String,
        active: Bool,
        actionLabel: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(active ? 0.18 : 0.1)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(active ? tintDark : tint.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if active {
                        Text("ON")
                            .font(.sans(8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(tintDark)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(tint.opacity(0.18)))
                    }
                }
                Text(detail)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: destructive ? .light : .medium).impactOccurred()
                action()
            } label: {
                Text(actionLabel)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.textPrimary.opacity(0.65) : Theme.textCream)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(goalActionBackground(destructive: destructive, tint: tint))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private func goalActionBackground(destructive: Bool, tint: Color) -> some View {
        if destructive {
            Capsule(style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.2), lineWidth: 0.6)
        } else {
            Capsule(style: .continuous).fill(tint)
        }
    }

    private func numberForm(for circle: FFCircle) -> some View {
        let target = Double(numberTarget.trimmingCharacters(in: .whitespaces))
        let unit = numberUnit.trimmingCharacters(in: .whitespaces)
        let valid = (target ?? 0) > 0 && !unit.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(CircleType.collective.tintDark)
                Text("Add a shared number")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 10) {
                TextField("1000", text: $numberTarget)
                    .keyboardType(.numberPad)
                    .font(.sans(15, weight: .semibold))
                    .frame(width: 88)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(numberFieldBackground)
                TextField("miles, plunges, pages…", text: $numberUnit)
                    .font(.sans(15, weight: .regular))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(numberFieldBackground)
            }
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cancelNumberForm()
                } label: {
                    Text("Cancel")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                Button {
                    commitNumber(for: circle, target: target, unit: unit)
                } label: {
                    Text("Add number")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(valid ? CircleType.collective.tint : Theme.textPrimary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!valid)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var numberFieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
            )
    }

    private func commitNumber(for circle: FFCircle, target: Double?, unit: String) {
        guard let target, target > 0, !unit.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        _ = store.addCircleLayer(.sharedNumber, to: circle.id, unit: unit, target: target)
        showBanner("Shared number added.")
        cancelNumberForm()
    }

    private func cancelNumberForm() {
        withAnimation(.easeInOut(duration: 0.18)) { showNumberForm = false }
        numberUnit = ""
        numberTarget = ""
    }

    // MARK: - Governance

    private func governanceSection(for circle: FFCircle) -> some View {
        sectionContainer(title: "Governance", eyebrow: "OWNER ONLY") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: governanceBinding(for: circle)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Members can propose tasks")
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(circle.membersCanProposeTasks
                            ? "Member changes queue for your review"
                            : "Only owner & admins can change tasks")
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                }
                .tint(Theme.alertGreen)
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func governanceBinding(for circle: FFCircle) -> Binding<Bool> {
        Binding(
            get: { circle.membersCanProposeTasks },
            set: { newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.setMembersCanProposeTasks(newValue, in: circle.id)
            }
        )
    }

    // MARK: - Pending requests

    @ViewBuilder
    private func pendingRequestsSection(for circle: FFCircle) -> some View {
        let pending = store.pendingRequests(forCircleId: circle.id)
        if !pending.isEmpty {
            sectionContainer(
                title: "Pending requests",
                eyebrow: "\(pending.count) AWAITING REVIEW"
            ) {
                VStack(spacing: 10) {
                    ForEach(pending) { request in
                        pendingRequestRow(request, in: circle)
                    }
                }
            }
        }
    }

    private func pendingRequestRow(_ request: CircleTaskRequest, in circle: FFCircle) -> some View {
        let requesterName: String = {
            if request.requesterId == store.currentUserId { return "You" }
            return store.friend(by: request.requesterId)?.displayName ?? "A member"
        }()

        let actionLabel: String = {
            switch request.type {
            case .add: return "wants to add"
            case .edit: return "wants to edit"
            case .delete: return "wants to remove"
            }
        }()

        let targetTitle: String = {
            if request.type == .edit,
               let id = request.existingTaskId,
               let existing = circle.tasks.first(where: { $0.id == id }) {
                return "\u{201C}\(existing.title)\u{201D} \u{2192} \u{201C}\(request.taskData.title)\u{201D}"
            }
            return "\u{201C}\(request.taskData.title)\u{201D}"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(requesterName) \(actionLabel)")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Text(targetTitle)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.rejectRequest(request.id)
                } label: {
                    Text("Reject")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.approveRequest(request.id)
                } label: {
                    Text("Approve")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.alertGreen)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Shared tasks

    @ViewBuilder
    private func sharedTasksSection(for circle: FFCircle) -> some View {
        let role = store.myRole(in: circle)
        let canAdd = store.canManageTasks(in: circle) || circle.membersCanProposeTasks

        sectionContainer(
            title: "Shared tasks",
            eyebrow: role == .owner ? "OWNER" : (role == .admin ? "ADMIN" : "MEMBER")
        ) {
            VStack(spacing: 10) {
                if circle.tasks.isEmpty && !showAddTaskForm {
                    Text("No shared tasks yet.")
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }

                ForEach(circle.tasks) { task in
                    sharedTaskRow(task, in: circle)
                }

                if showAddTaskForm {
                    addOrEditForm(for: circle)
                } else if canAdd {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editingTaskId = nil
                        draftTitle = ""
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAddTaskForm = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.sans(15, weight: .semibold))
                            Text(circle.requiresRequest(forUserId: store.currentUserId)
                                ? "Propose a task"
                                : "Add a task")
                                .font(.sans(14, weight: .medium))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18),
                                              style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sharedTaskRow(_ task: CircleTask, in circle: FFCircle) -> some View {
        let mayEdit = store.canManageTasks(in: circle) || circle.membersCanProposeTasks
        let needsRequest = circle.requiresRequest(forUserId: store.currentUserId)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(task.title)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if mayEdit {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editingTaskId = task.id
                    draftTitle = task.title
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAddTaskForm = true
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let applied = store.deleteOrProposeCircleTask(
                        circleId: circle.id,
                        existingTaskId: task.id
                    )
                    showBanner(applied
                        ? "Task removed."
                        : "Removal queued for review.")
                } label: {
                    Image(systemName: "trash")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(needsRequest
                            ? Theme.textPrimary.opacity(0.45)
                            : Theme.alertRed.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
    }

    private func addOrEditForm(for circle: FFCircle) -> some View {
        let isEditing = editingTaskId != nil
        let needsRequest = circle.requiresRequest(forUserId: store.currentUserId)
        let saveLabel: String = {
            if needsRequest {
                return isEditing ? "Propose edit" : "Propose add"
            }
            return isEditing ? "Save" : "Add"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            TextField("Task name", text: $draftTitle)
                .font(.sans(15, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                )

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    closeForm()
                } label: {
                    Text("Cancel")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    submitForm(in: circle)
                } label: {
                    Text(saveLabel)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Theme.textPrimary.opacity(0.3)
                                    : Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func submitForm(in circle: FFCircle) {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let applied: Bool
        if let id = editingTaskId,
           let existing = circle.tasks.first(where: { $0.id == id }) {
            var draft = CircleTaskDraft(from: existing)
            draft.title = trimmed
            applied = store.editOrProposeCircleTask(
                circleId: circle.id,
                existingTaskId: id,
                draft: draft
            )
            showBanner(applied ? "Task updated." : "Edit queued for review.")
        } else {
            let draft = CircleTaskDraft(title: trimmed)
            applied = store.addOrProposeCircleTask(circleId: circle.id, draft: draft)
            showBanner(applied ? "Task added." : "Task queued for review.")
        }
        closeForm()
    }

    private func closeForm() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showAddTaskForm = false
        }
        editingTaskId = nil
        draftTitle = ""
    }

    // MARK: - Members

    private func membersSection(for circle: FFCircle) -> some View {
        sectionContainer(
            title: "Members",
            eyebrow: "\(circle.memberIds.count) MEMBER\(circle.memberIds.count == 1 ? "" : "S")"
        ) {
            VStack(spacing: 10) {
                ForEach(circle.memberIds, id: \.self) { memberId in
                    memberRow(memberId: memberId, in: circle)
                }
            }
        }
    }

    private func memberRow(memberId: UUID, in circle: FFCircle) -> some View {
        let role = circle.role(forUserId: memberId)
        let isMe = memberId == store.currentUserId
        let displayName: String = {
            if isMe { return "You" }
            return store.friend(by: memberId)?.displayName ?? "Member"
        }()
        let initials: String = {
            if isMe { return "J" }
            return store.friend(by: memberId)?.initials ?? "?"
        }()
        let accent: Color = {
            if isMe { return Theme.textPrimary }
            if let f = store.friend(by: memberId) {
                return Color(hex: f.accentColorHex)
            }
            return Theme.textTertiary
        }()

        let viewerIsOwner = store.isOwner(of: circle)
        let viewerCanManage = store.canManageTasks(in: circle)
        let target = store.profileTarget(forMemberId: memberId)

        return HStack(spacing: 12) {
            Button {
                guard let target else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                profileTarget = target
            } label: {
                HStack(spacing: 12) {
                    FriendAvatarView(
                        friend: isMe ? nil : store.friend(by: memberId),
                        size: 36,
                        fallbackInitials: initials,
                        fallbackColor: accent
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.sans(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        roleChip(role)
                    }

                    if target != nil {
                        Image(systemName: "chevron.right")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
            .accessibilityLabel(isMe ? "Open your profile" : (target != nil ? "Open \(displayName)'s profile" : displayName))

            if !isMe {
                Menu {
                    if viewerIsOwner {
                        switch role {
                        case .owner:
                            EmptyView()
                        case .admin:
                            Button("Demote to member") {
                                store.demoteFromAdmin(userId: memberId, in: circle.id)
                            }
                        case .member:
                            Button("Promote to admin") {
                                store.promoteToAdmin(userId: memberId, in: circle.id)
                            }
                        }
                        if role != .owner {
                            Button("Transfer ownership", role: .destructive) {
                                store.transferOwnership(to: memberId, in: circle.id)
                            }
                        }
                    }
                    if viewerCanManage, role != .owner {
                        // Admins can only remove plain members, not other admins.
                        let canRemove = viewerIsOwner || role == .member
                        if canRemove {
                            Button("Remove from circle", role: .destructive) {
                                store.removeMember(userId: memberId, from: circle.id)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .opacity(viewerIsOwner || (viewerCanManage && role == .member) ? 1 : 0.3)
                .disabled(!(viewerIsOwner || (viewerCanManage && role == .member)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private func roleChip(_ role: CircleRole) -> some View {
        let label: String = {
            switch role {
            case .owner: return "OWNER"
            case .admin: return "ADMIN"
            case .member: return "MEMBER"
            }
        }()
        let color: Color = {
            switch role {
            case .owner: return Theme.sunWarm
            case .admin: return Theme.alertGreen
            case .member: return Theme.textPrimary.opacity(0.5)
            }
        }()
        return Text(label)
            .font(.sans(9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }

    // MARK: - Chrome

    @ViewBuilder
    private func sectionContainer<C: View>(
        title: String,
        eyebrow: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(eyebrow)
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            content()
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func bannerView(text: String) -> some View {
        Text(text)
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Theme.textCream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.92))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func showBanner(_ text: String) {
        bannerTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            transientBanner = text
        }
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(2.0))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transientBanner = nil
                }
            }
        }
    }
}

#Preview {
    let store = Store()
    return Group {
        if let parallel = store.circles.first(where: { $0.type == .parallel }) {
            CircleSettingsSheet(circleId: parallel.id)
        }
    }
    .environment(store)
}
