//
//  MilestoneDetailView.swift
//  FrisFocus
//
//  One milestone's full page: header with title, target week, reward,
//  and progress; then three living sections — Steps (checkable smaller
//  goals, reorderable), Journey (the chronological photo / voice-memo
//  timeline documenting the process), and Notes (journal entries linked
//  to this goal). Completing the milestone credits its reward to today
//  with a quiet celebration moment that grows a warm "Share this
//  milestone" prompt; a quiet share control (header + menu) opens the
//  milestone share camera anytime — mid-journey shares simply show
//  current progress instead of LANDED.
//
//  Reads the milestone live from the Store by id so every mutation
//  reflects immediately; if the milestone is deleted elsewhere the page
//  falls back gracefully.
//

import PhotosUI
import SwiftUI
import UIKit

struct MilestoneDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID

    @State private var newStepTitle: String = ""
    @State private var editingStep: MilestoneStep? = nil
    @State private var stepsEditMode: EditMode = .inactive
    @State private var showComposer: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showRecorder: Bool = false
    @State private var viewingAttachment: MilestoneAttachment? = nil
    @State private var showNotePicker: Bool = false
    @State private var showNewNote: Bool = false
    /// Drives the small completion celebration on the header flag.
    @State private var celebrate: Bool = false
    /// The warm post-completion invitation to share the moment.
    @State private var showSharePrompt: Bool = false
    @State private var showShareCamera: Bool = false

    @FocusState private var newStepFocused: Bool

    var body: some View {
        ZStack {
            Theme.paperCream.ignoresSafeArea()

            if let milestone = store.milestone(by: milestoneId) {
                content(for: milestone)
            } else {
                missingState
            }

            if showSharePrompt {
                sharePromptOverlay
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showSharePrompt)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.milestone(by: milestoneId) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            openShareCamera()
                        } label: {
                            Label("Share milestone", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showComposer = true
                        } label: {
                            Label("Edit milestone", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete milestone", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    }
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            MilestoneComposerSheet(editing: store.milestone(by: milestoneId))
        }
        .sheet(item: $editingStep) { step in
            MilestoneStepEditorSheet(milestoneId: milestoneId, step: step)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRecorder) {
            VoiceMemoRecorderSheet { completed in
                store.addMilestoneVoiceMemo(
                    filename: completed.filename,
                    duration: completed.duration,
                    to: milestoneId
                )
            }
        }
        .sheet(isPresented: $showNotePicker) {
            MilestoneNoteLinkSheet(milestoneId: milestoneId)
        }
        .sheet(isPresented: $showNewNote) {
            NewNoteFormView {
                // Link the note that was just written to this milestone.
                if let newest = store.notes.max(by: { $0.createdAt < $1.createdAt }),
                   Date().timeIntervalSince(newest.createdAt) < 30 {
                    store.linkNote(newest.id, to: milestoneId)
                }
            }
        }
        .fullScreenCover(item: $viewingAttachment) { attachment in
            MilestonePhotoViewer(attachment: attachment)
        }
        .fullScreenCover(isPresented: $showShareCamera) {
            if let milestone = store.milestone(by: milestoneId) {
                ShareCameraView(subject: .milestone(store.milestoneShareContext(for: milestone)))
            }
        }
        .confirmationDialog(
            "Delete this milestone?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete milestone", role: .destructive) {
                if let milestone = store.milestone(by: milestoneId) {
                    store.deleteMilestone(milestone)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its steps, journey media, and any points it credited are removed. Linked notes stay in your journal.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    store.addMilestonePhoto(image, to: milestoneId)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for milestone: Milestone) -> some View {
        List {
            Section {
                headerCard(milestone)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: Theme.pageHorizontalPadding, bottom: 6, trailing: Theme.pageHorizontalPadding))
            }

            stepsSection(milestone)
            journeySection(milestone)
            notesSection(milestone)

            Section {
                completionControl(milestone)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: Theme.pageHorizontalPadding, bottom: 40, trailing: Theme.pageHorizontalPadding))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $stepsEditMode)
    }

    // MARK: - Header card

    @ViewBuilder
    private func headerCard(_ milestone: Milestone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowText(
                    text: milestone.isCompleted ? "Milestone · landed" : "Milestone · week \(milestone.weekNumber)",
                    opacity: 0.55
                )
                Spacer()

                Button {
                    openShareCamera()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share this milestone")
                .accessibilityHint("Opens the share camera with the milestone card")

                Image(systemName: milestone.isCompleted ? "flag.checkered" : "flag")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(milestone.isCompleted ? Theme.alertGreen : Theme.sunShadow)
                    .scaleEffect(celebrate ? 1.35 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.5), value: celebrate)
            }

            Text(milestone.title.isEmpty ? "Untitled milestone" : milestone.title)
                .font(.serif(26, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(milestone.pointValue)")
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(milestone.isCompleted ? Theme.alertGreen : Theme.textPrimary)
                Text("pts")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))

                Spacer()

                Text(rewardModeText(milestone))
                    .font(.serifItalic(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            // Progress bar
            let done = milestone.steps.filter(\.isCompleted).count
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.textPrimary.opacity(0.08))
                        Capsule()
                            .fill(milestone.isCompleted ? Theme.alertGreen.opacity(0.7) : Theme.sunOuter)
                            .frame(width: max(0, proxy.size.width * milestone.stepProgress))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: milestone.stepProgress)
                    }
                }
                .frame(height: 5)

                if !milestone.steps.isEmpty {
                    Text("\(done)/\(milestone.steps.count)")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func rewardModeText(_ milestone: Milestone) -> String {
        milestone.pointsPerStep
            ? "points land step by step"
            : "the reward lands at completion"
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepsSection(_ milestone: Milestone) -> some View {
        Section {
            ForEach(milestone.sortedSteps) { step in
                stepRow(step, in: milestone)
                    .listRowBackground(Color.white.opacity(0.5))
                    .listRowSeparatorTint(Theme.textPrimary.opacity(0.06))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteMilestoneStep(step, from: milestoneId)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onMove { source, destination in
                store.moveMilestoneSteps(in: milestoneId, from: source, to: destination)
            }

            // Inline add field
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                TextField("Break it into a smaller goal…", text: $newStepTitle)
                    .font(.serifItalic(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($newStepFocused)
                    .submitLabel(.done)
                    .onSubmit(addStep)
                if !newStepTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addStep) {
                        Text("Add")
                            .font(.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader(
                "Steps",
                trailing: milestone.steps.count > 1 ? (stepsEditMode == .active ? "Done" : "Reorder") : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    stepsEditMode = stepsEditMode == .active ? .inactive : .active
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: MilestoneStep, in milestone: Milestone) -> some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.toggleMilestoneStep(step, in: milestoneId)
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(step.isCompleted ? Theme.alertGreen : Theme.textPrimary.opacity(0.3), lineWidth: 1.4)
                        .frame(width: 22, height: 22)
                    if step.isCompleted {
                        Circle().fill(Theme.alertGreen).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.paperCream)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.isCompleted ? "Mark step incomplete" : "Mark step complete")

            Button {
                editingStep = step
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(step.isCompleted ? 0.45 : 0.95))
                        .strikethrough(step.isCompleted, color: Theme.textPrimary.opacity(0.4))
                    if milestone.pointsPerStep, step.pointValue > 0 {
                        Text("+\(step.pointValue) pts on check-off")
                            .font(.sans(10, weight: .regular))
                            .foregroundStyle(
                                step.isCompleted
                                    ? Theme.alertGreen.opacity(0.8)
                                    : Theme.textPrimary.opacity(0.45)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits this step")
        }
        .padding(.vertical, 2)
    }

    private func addStep() {
        let trimmed = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.addMilestoneStep(to: milestoneId, title: trimmed)
        newStepTitle = ""
        newStepFocused = true
    }

    // MARK: - Journey

    @ViewBuilder
    private func journeySection(_ milestone: Milestone) -> some View {
        Section {
            let timeline = milestone.attachments.sorted { $0.createdAt < $1.createdAt }

            if timeline.isEmpty {
                Text("Document the process — a photo of the work, a voice note about where it stands.")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(timeline) { attachment in
                    journeyRow(attachment)
                        .listRowBackground(Color.white.opacity(0.5))
                        .listRowSeparatorTint(Theme.textPrimary.opacity(0.06))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.deleteMilestoneAttachment(attachment, from: milestoneId)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    journeyAddLabel("photo", systemImage: "photo")
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showRecorder = true
                } label: {
                    journeyAddLabel("voice memo", systemImage: "mic")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader("Journey")
        }
    }

    @ViewBuilder
    private func journeyAddLabel(_ label: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .regular))
            Text(label)
                .font(.sans(12, weight: .medium))
        }
        .foregroundStyle(Theme.textPrimary.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(
            Capsule().strokeBorder(Theme.textPrimary.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func journeyRow(_ attachment: MilestoneAttachment) -> some View {
        switch attachment.kind {
        case .photo:
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewingAttachment = attachment
            } label: {
                HStack(spacing: 12) {
                    MilestoneThumbView(attachment: attachment, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo")
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        Text(journeyDateText(attachment.createdAt))
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open photo full screen")

        case .voiceMemo:
            MilestoneMemoRow(attachment: attachment, dateText: journeyDateText(attachment.createdAt))
        }
    }

    private func journeyDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d · h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Notes

    @ViewBuilder
    private func notesSection(_ milestone: Milestone) -> some View {
        Section {
            let linked = store.linkedNotes(for: milestone)

            if linked.isEmpty {
                Text("Journal entries about this goal can live right here.")
                    .font(.serifItalic(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(linked) { note in
                    linkedNoteRow(note)
                        .listRowBackground(Color.white.opacity(0.5))
                        .listRowSeparatorTint(Theme.textPrimary.opacity(0.06))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                store.unlinkNote(note.id, from: milestoneId)
                            } label: {
                                Label("Unlink", systemImage: "link.badge.plus")
                            }
                            .tint(Theme.alertAmber)
                        }
                }
            }

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNotePicker = true
                } label: {
                    journeyAddLabel("link a note", systemImage: "link")
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewNote = true
                } label: {
                    journeyAddLabel("new note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader("Notes")
        }
    }

    @ViewBuilder
    private func linkedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let label = note.label, !label.isEmpty {
                    Text(label)
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                }
                Spacer()
                Text(journeyDateText(note.createdAt))
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            if let body = note.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(body)
                    .font(.serif(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .lineLimit(3)
            } else if !note.voiceMemos.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                    Text("Voice memo")
                        .font(.sans(11, weight: .regular))
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Completion

    @ViewBuilder
    private func completionControl(_ milestone: Milestone) -> some View {
        VStack(spacing: 10) {
            if milestone.isCompleted {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.uncompleteMilestone(milestone)
                } label: {
                    Text("Mark as not done")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(
                            Capsule().strokeBorder(Theme.textPrimary.opacity(0.2), lineWidth: 0.5)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: complete) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Mark milestone complete")
                            .font(.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.warmWheat)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.alertGreen)
                    .clipShape(Capsule())
                    .shadow(color: Theme.alertGreen.opacity(0.25), radius: 8, y: 2)
                }
                .buttonStyle(.plain)

                Text(completionFootnote(milestone))
                    .font(.serifItalic(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func completionFootnote(_ milestone: Milestone) -> String {
        if milestone.pointsPerStep {
            return "Credits the remainder of the \(milestone.pointValue) pts to today — step credits already landed on their own days."
        }
        return "Credits \(milestone.pointValue) pts to today — it can push the day well past your daily target."
    }

    private func complete() {
        guard let milestone = store.milestone(by: milestoneId) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            store.completeMilestone(milestone)
            celebrate = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.3)) { celebrate = false }
            try? await Task.sleep(for: .milliseconds(200))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSharePrompt = true
        }
    }

    private func openShareCamera() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showSharePrompt = false
        showShareCamera = true
    }

    // MARK: - Share prompt (post-completion)

    /// The warm invitation that grows out of the completion moment —
    /// a glow, a spring, never a loud popup. One tap opens the share
    /// camera with the LANDED overlay ready; easy to wave off.
    private var sharePromptOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.sunWarm.opacity(0.45), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 36
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.alertGreen)
                }

                VStack(spacing: 4) {
                    Text("Milestone landed")
                        .font(.serif(21, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Capture the moment — this one's worth telling.")
                        .font(.serifItalic(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Button {
                    openShareCamera()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Share this milestone")
                            .font(.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x2C2C2A))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: 0xFFD98A), Color(hex: 0xF0B860)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .shadow(color: Color(hex: 0xF0A340).opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSharePrompt = false
                } label: {
                    Text("Not now")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .frame(height: 38)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.paperCream)
                    .shadow(color: Color.black.opacity(0.22), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { showSharePrompt = false }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(
        _ text: String,
        trailing: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.sans(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))

            Spacer()

            if let trailing, let trailingAction {
                Button(action: trailingAction) {
                    Text(trailing.uppercased())
                        .font(.sans(9, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .textCase(nil)
    }

    // MARK: - Missing fallback

    private var missingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("This milestone is gone")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("It may have been removed on another device.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(40)
    }
}

// MARK: - Inline voice memo row

/// One voice memo in the journey timeline — plays inline with a small
/// progress readout.
private struct MilestoneMemoRow: View {
    let attachment: MilestoneAttachment
    let dateText: String

    @State private var player = AudioPlayerService()

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().strokeBorder(Theme.textPrimary.opacity(0.15), lineWidth: 0.5)
                        )
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .offset(x: player.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause voice memo" : "Play voice memo")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Text("Voice memo\(durationText)")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.textPrimary.opacity(0.1)).frame(height: 3)
                        Capsule()
                            .fill(Theme.sunOuter)
                            .frame(width: max(0, proxy.size.width * player.progress), height: 3)
                    }
                }
                .frame(height: 3)

                Text(dateText)
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
        }
        .padding(.vertical, 4)
        .onDisappear { player.stop() }
    }

    private var durationText: String {
        guard let duration = attachment.duration, duration > 0 else { return "" }
        return " · \(duration.voiceMemoTimeString)"
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if player.isPlaying {
            player.toggle()
        } else if let url = attachment.url {
            if player.progress > 0 {
                player.toggle()
            } else {
                player.load(url: url)
                player.toggle()
            }
        }
    }
}

// MARK: - Full-screen photo viewer

/// Minimal full-screen viewer for a journey photo — black ground,
/// fit-to-screen image, tap or the close control to dismiss.
private struct MilestonePhotoViewer: View {
    let attachment: MilestoneAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image = MilestoneMediaStore.image(for: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Still syncing…")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close photo")
        }
        .onTapGesture { dismiss() }
    }
}
