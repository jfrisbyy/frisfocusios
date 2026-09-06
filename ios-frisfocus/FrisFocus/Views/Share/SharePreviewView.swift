//
//  SharePreviewView.swift
//  FrisFocus
//
//  Post-capture preview — the composed moment framed in the final 9:16
//  story shape (WYSIWYG with what posts), with the same destination
//  picker a normal proof gets:
//
//   • The destination pill — "Friends · 24h" by default — opens the
//     familiar chooser: the 24-hour story and/or hand-picked friends
//     and circles, any combination. Everything in-app is the CLEAN
//     card: no attribution line, no wordmark; identity is implicit.
//   • "Share outside" — the native iOS share sheet (Instagram,
//     iMessage, save to camera roll). The composite ALWAYS carries the
//     attribution line: orb glyph + "@USERNAME · FRISFOCUS". This rule
//     is baked into the destination, never a toggle.
//
//  One renderer, a destination parameter — identical overlay
//  composition, attribution added only for external/save. Everything
//  composites locally; zero API calls.
//

import AVFoundation
import PencilKit
import SwiftUI
import UIKit

/// Where the composed card goes when sent in-app. Mirrors the proof
/// editor's audience model: the public 24 h story plus any number of
/// hand-picked friends and circles.
private struct ShareCardAudience: Equatable {
    var everyone: Bool
    var friendIds: Set<UUID>
    var circleIds: Set<UUID>

    static let initial = ShareCardAudience(everyone: true, friendIds: [], circleIds: [])

    var isPristineEveryone: Bool {
        everyone && friendIds.isEmpty && circleIds.isEmpty
    }

    var hasPrivateRecipients: Bool {
        !friendIds.isEmpty || !circleIds.isEmpty
    }
}

struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: CaptureResult
    /// The card subject (day, milestone, or note) frozen together with
    /// the user's overlay choices at capture time.
    let composition: ShareCardComposition
    let username: String
    /// Where the composed card can attach afterwards — a milestone's
    /// journey, the note composer, or the free-standing picker.
    var attachContext: ProofAttachContext = .none
    /// Note-composer flow: saved media returns here instead of
    /// mutating the Store (the note doesn't exist yet).
    var onSavedToNoteComposer: ((NotePhoto) -> Void)? = nil
    /// Called after a successful post/share so the camera dismisses too.
    let onFinished: () -> Void

    @State private var isWorking: Bool = false
    @State private var sharePayload: SharePayload?
    @State private var postedConfirmation: String?
    /// The "who sees this" lesson, raised once — in the beat right
    /// after the first card is actually sent somewhere.
    @State private var destinationLesson: WalkthroughLesson?

    // Attach flow — the composed clean card kept around so it can land
    // on a journey or note after posting (or via "Just save").
    @State private var pendingAttach: ComposedProofMedia?
    @State private var attachChipVisible: Bool = false
    @State private var showAttachPicker: Bool = false
    @State private var didPost: Bool = false
    @State private var sheetPickHandled: Bool = false
    @State private var finishTask: Task<Void, Never>?
    /// The proof-library archive entry created for this card (posted or
    /// saved) — pin destinations append their names onto it.
    @State private var libraryItemId: UUID? = nil

    // Destination state — the same any-combination model as a proof.
    @State private var audience: ShareCardAudience = .initial
    @State private var showAudiencePanel: Bool = false

    // Edit layer — the same toolkit as the proof editor (text, task
    // stickers, freehand drawing), living on the 9:16 card and baked
    // into both the clean in-app card and the attributed export.
    @State private var captions: [CaptionBlock] = []
    @State private var taskStickers: [TaskStickerBlock] = []
    @State private var pkCanvas = PKCanvasView()
    @State private var pkToolPicker = PKToolPicker()
    @State private var isDrawing: Bool = false
    @State private var showTaskPicker: Bool = false
    @State private var activeBlockId: UUID? = nil
    @State private var isDraggingBlock: Bool = false
    @State private var draggingOverTrash: Bool = false
    /// Centerline guide — appears while a dragged block is magnetically
    /// snapped to the card's vertical center.
    @State private var showCenterGuide: Bool = false
    /// The story card's on-screen size — the canvas space block
    /// positions are normalized against.
    @State private var cardSize: CGSize = .zero

    /// Pinch-to-zoom framing for the media layer. The edit layer and
    /// the day-overlay chrome stay in card space on top; the zoom is
    /// baked into both the clean in-app card and the attributed export.
    @State private var mediaZoom: MediaZoom = MediaZoom()

    // Caption editor state (shared CaptionEditorOverlay).
    @State private var editingCaptionId: UUID? = nil
    @State private var draftText: String = ""
    @State private var draftStyle: CaptionStyle = .classic
    @State private var draftColor: Color? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if isDrawing {
                    drawingChrome
                } else {
                    topBar
                }

                // The story-shaped card — exactly the frame that posts.
                storyCard
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isDrawing {
                    bottomArea
                }
            }

            if editingCaptionId != nil {
                CaptionEditorOverlay(
                    text: $draftText,
                    style: $draftStyle,
                    color: $draftColor,
                    onCancel: cancelEditor,
                    onDone: commitEditor
                )
            }

            if isWorking {
                workingVeil
            }

            if let postedConfirmation {
                postedToast(postedConfirmation)
            }
        }
        .statusBarHidden()
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAttachPicker, onDismiss: {
            // Closed without picking: a posted card just finishes (the
            // post already happened); a "Just save" returns to the
            // preview so nothing is silently lost.
            if !sheetPickHandled && didPost { onFinished() }
            sheetPickHandled = false
        }) {
            ProofAttachPickerSheet(
                suggestedMilestoneId: suggestedMilestoneId,
                alreadyAttached: stickerTargets,
                onSave: { targets in
                    sheetPickHandled = true
                    showAttachPicker = false
                    attachAllAndFinish(targets)
                }
            )
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showTaskPicker) {
            TaskStickerPickerView { block in
                addTaskSticker(block)
            }
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .walkthroughLessonSheet($destinationLesson) { lesson in
            walkthrough.markSeen(lesson)
            walkthrough.release(lesson)
            // Hand the normal exit beat back — the attach chip still
            // gets its window before the editor closes itself.
            scheduleFinish(after: 3.4)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showAudiencePanel)
        .animation(.easeInOut(duration: 0.2), value: isDrawing)
        .animation(.easeInOut(duration: 0.18), value: editingCaptionId)
        .animation(.easeInOut(duration: 0.18), value: isDraggingBlock)
    }

    // MARK: - Story card (9:16 — WYSIWYG with the export)

    /// The captured media center-cropped into the 9:16 story shape with
    /// the live overlay on top — previewing the CLEAN in-app card (the
    /// attribution line only exists on the external composite).
    private var storyCard: some View {
        mediaLayer
            .overlay {
                editCanvas
            }
            .overlay {
                // The card-overlay chrome renders above the edit layer —
                // matching the export order — but never intercepts
                // touches, so blocks below stay draggable.
                ShareCompositionOverlayView(
                    composition: composition,
                    mode: .render(attributed: false),
                    username: username,
                    bottomPadding: 26
                )
                .allowsHitTesting(false)
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                if isDraggingBlock {
                    trashZone
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
    }

    // MARK: - Edit canvas (captions, stickers, drawing)

    /// The interactive edit layer on the story card. Tap an empty spot
    /// to drop a caption right there; drag / pinch / rotate blocks; drag
    /// to the bottom to delete — exactly like the proof editor.
    private var editCanvas: some View {
        GeometryReader { geo in
            ZStack {
                DrawingCanvasView(canvas: $pkCanvas, isActive: isDrawing, toolPicker: pkToolPicker)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(isDrawing)
                    .zIndex(isDrawing ? 50 : 0)

                ForEach(captions) { block in
                    captionBlockView(block, in: geo.size)
                }

                ForEach(taskStickers) { block in
                    stickerBlockView(block, in: geo.size)
                }

                // Snap guide — hairline down the card center while a
                // dragged block rides the magnetic band.
                if showCenterGuide {
                    Rectangle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        guard !isDrawing, !isWorking else { return }
                        if activeBlockId != nil {
                            activeBlockId = nil
                        } else {
                            addCaption(at: value.location, in: geo.size)
                        }
                    }
            )
            // Pinch on open canvas zooms the media; pinching a caption /
            // sticker still resizes that block (child gestures win).
            .modifier(MediaZoomGestureModifier(
                zoom: $mediaZoom,
                canvasSize: geo.size,
                isEnabled: !isDrawing && editingCaptionId == nil && !isWorking
            ))
            .onAppear { cardSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                cardSize = newSize
            }
        }
    }

    @ViewBuilder
    private func captionBlockView(_ block: CaptionBlock, in size: CGSize) -> some View {
        DraggableCaptionView(
            block: block,
            canvasSize: size,
            isActive: activeBlockId == block.id,
            onActivate: {
                if activeBlockId != block.id { activeBlockId = block.id }
            },
            onTapToEdit: { openEditor(for: block) },
            onCommitPosition: { newPos in
                if let idx = captions.firstIndex(where: { $0.id == block.id }) {
                    captions[idx].position = newPos
                }
            },
            onCommitScale: { newScale in
                if let idx = captions.firstIndex(where: { $0.id == block.id }) {
                    captions[idx].scale = newScale
                }
            },
            onCommitRotation: { newRotation in
                if let idx = captions.firstIndex(where: { $0.id == block.id }) {
                    captions[idx].rotation = newRotation
                }
            },
            onTrashHoverChanged: { over in
                if draggingOverTrash != over { draggingOverTrash = over }
            },
            onDropDelete: {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                captions.removeAll { $0.id == block.id }
                activeBlockId = nil
                draggingOverTrash = false
            },
            onDragStateChanged: { dragging in
                if isDraggingBlock != dragging { isDraggingBlock = dragging }
            },
            onCenterSnapChanged: { snapped in
                withAnimation(.easeInOut(duration: 0.12)) { showCenterGuide = snapped }
            }
        )
    }

    @ViewBuilder
    private func stickerBlockView(_ block: TaskStickerBlock, in size: CGSize) -> some View {
        DraggableStickerView(
            block: block,
            canvasSize: size,
            isActive: activeBlockId == block.id,
            onActivate: {
                if activeBlockId != block.id { activeBlockId = block.id }
            },
            onCommitPosition: { newPos in
                if let idx = taskStickers.firstIndex(where: { $0.id == block.id }) {
                    taskStickers[idx].position = newPos
                }
            },
            onCommitScale: { newScale in
                if let idx = taskStickers.firstIndex(where: { $0.id == block.id }) {
                    taskStickers[idx].scale = newScale
                }
            },
            onCommitRotation: { newRotation in
                if let idx = taskStickers.firstIndex(where: { $0.id == block.id }) {
                    taskStickers[idx].rotation = newRotation
                }
            },
            onTrashHoverChanged: { over in
                if draggingOverTrash != over { draggingOverTrash = over }
            },
            onDropDelete: {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                taskStickers.removeAll { $0.id == block.id }
                activeBlockId = nil
                draggingOverTrash = false
            },
            onDragStateChanged: { dragging in
                if isDraggingBlock != dragging { isDraggingBlock = dragging }
            },
            onCenterSnapChanged: { snapped in
                withAnimation(.easeInOut(duration: 0.12)) { showCenterGuide = snapped }
            }
        )
    }

    private var trashZone: some View {
        VStack(spacing: 4) {
            Image(systemName: draggingOverTrash ? "trash.fill" : "trash")
                .font(.system(size: 18, weight: .semibold))
            Text("drop to delete")
                .font(.sans(10, weight: .medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(
                draggingOverTrash
                    ? Color.red.opacity(0.78)
                    : Color.black.opacity(0.55)
            )
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .scaleEffect(draggingOverTrash ? 1.12 : 1.0)
        .allowsHitTesting(false)
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaLayer: some View {
        switch result {
        case .photo(let image):
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(mediaZoom.scale)
                    .offset(mediaZoom.offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        case .video(let url, _, _):
            VideoLoopView(url: url, gravity: .resizeAspectFill)
                .id(url)
                .scaleEffect(mediaZoom.scale)
                .offset(mediaZoom.offset)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel("Retake")

            Spacer()

            toolButton(icon: "textformat", label: "Add text") {
                addCaption()
            }

            toolButton(icon: "checklist", label: "Add a task sticker") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeBlockId = nil
                showTaskPicker = true
            }

            toolButton(icon: "scribble.variable", label: "Draw on the card") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeBlockId = nil
                withAnimation(.easeInOut(duration: 0.2)) { isDrawing = true }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    /// A round glyph-only tool button matching the proof editor's.
    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Minimal bar while draw mode is engaged — Undo, Clear, Done. The
    /// system tool picker floats at the bottom on its own.
    private var drawingChrome: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pkCanvas.undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.40)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pkCanvas.drawing = PKDrawing()
            } label: {
                Text("Clear")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(Color.black.opacity(0.40)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear drawing")

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) { isDrawing = false }
            } label: {
                Text("Done")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.textPrimary))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish drawing")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var bottomArea: some View {
        VStack(spacing: 12) {
            if showAudiencePanel {
                audiencePanel
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                destinationPill

                Button {
                    sendInApp()
                } label: {
                    HStack(spacing: 7) {
                        Text("Send")
                            .font(.sans(15, weight: .semibold))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x2C2C2A))
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(Capsule().fill(Color(hex: 0xFAEEDA)))
                }
                .accessibilityLabel("Send to \(audienceTitle)")
                .accessibilityHint("Sends the clean card, without the watermark")
            }
            .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button {
                    shareOutside()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Share outside")
                            .font(.sans(12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .accessibilityLabel("Share outside")
                .accessibilityHint("Opens the share sheet with your attributed card")

                Button {
                    justSave()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text(justSaveLabel)
                            .font(.sans(12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .accessibilityLabel(justSaveLabel)
                .accessibilityHint("Keeps the card on this device without posting")
            }
        }
        .padding(.bottom, 20)
        .disabled(isWorking)
    }

    /// "Just save" reads as its destination when the camera was opened
    /// from a milestone or the note composer.
    private var justSaveLabel: String {
        switch attachContext {
        case .milestone: return "Just save to journey"
        case .noteComposer: return "Just save to note"
        case .none: return "Just save"
        }
    }

    /// The milestone to offer first in the attach picker — the capture's
    /// own subject when there is one.
    private var suggestedMilestoneId: UUID? {
        if case .milestone(let id) = attachContext { return id }
        return nil
    }

    // MARK: - Destination pill

    private var destinationPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAudiencePanel.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(destinationTint.opacity(0.22))
                        .frame(width: 30, height: 30)
                    Image(systemName: audienceIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(destinationTint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(audienceTitle)
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(audienceSubtitle)
                        .font(.sans(10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Image(systemName: showAudiencePanel ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(Capsule().fill(Color.white.opacity(showAudiencePanel ? 0.16 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send to \(audienceTitle). Tap to change.")
    }

    private var audienceIcon: String {
        if audience.isPristineEveryone { return "person.2.fill" }
        let friendCount = audience.friendIds.count
        let circleCount = audience.circleIds.count
        if !audience.everyone && friendCount == 1 && circleCount == 0 { return "person.fill" }
        if !audience.everyone && friendCount == 0 && circleCount == 1 { return "circle.hexagongrid.fill" }
        return "person.3.fill"
    }

    private var destinationTint: Color {
        audience.isPristineEveryone ? Color(hex: 0xD87D44) : Color(hex: 0x8FB339)
    }

    private var audienceTitle: String {
        if audience.isPristineEveryone { return "Friends · 24h" }
        return summaryLabel(tokens: audienceTokens, empty: "Select destination")
    }

    private var audienceSubtitle: String {
        if audience.isPristineEveryone { return "Clean card · no watermark" }
        if audience.everyone { return "Story + a copy to each" }
        let count = audience.friendIds.count + audience.circleIds.count
        return count <= 1 ? "A private send · just them" : "A private send to each"
    }

    private var selectedCircles: [FFCircle] {
        audience.circleIds
            .compactMap { store.circle(by: $0) }
            .sorted { $0.name < $1.name }
    }

    private var selectedFriends: [Friend] {
        audience.friendIds
            .compactMap { store.friend(by: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var audienceTokens: [String] {
        var tokens: [String] = []
        if audience.everyone { tokens.append("Friends · 24h") }
        tokens.append(contentsOf: selectedCircles.map { $0.name })
        tokens.append(contentsOf: selectedFriends.map { $0.displayName })
        return tokens
    }

    private var privateTokens: [String] {
        selectedCircles.map { $0.name } + selectedFriends.map { $0.displayName }
    }

    private func summaryLabel(tokens: [String], empty: String) -> String {
        guard let first = tokens.first else { return empty }
        if tokens.count == 1 { return first }
        let others = tokens.count - 1
        return "\(first) + \(others) other\(others == 1 ? "" : "s")"
    }

    // MARK: - Audience chooser panel

    private var myCircles: [FFCircle] {
        store.circles.filter { $0.memberIds.contains(store.currentUserId) }
    }

    private var audiencePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Send to")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Button {
                    showAudiencePanel = false
                } label: {
                    Text("Done")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFAEEDA))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    audienceOptionRow(
                        icon: "person.2.fill",
                        title: "Friends · 24h",
                        subtitle: "Your public story",
                        tint: Color(hex: 0xD87D44),
                        selected: audience.everyone
                    ) { toggleEveryone() }

                    if !store.friends.isEmpty {
                        panelSectionLabel("FRIENDS")
                        ForEach(store.friends) { friend in
                            audienceFriendRow(friend)
                        }
                    }

                    if !myCircles.isEmpty {
                        panelSectionLabel("CIRCLES")
                        ForEach(myCircles) { circle in
                            audienceCircleRow(circle)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .frame(maxHeight: 280)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0x1E1C1B).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 18, y: 8)
    }

    private func panelSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func audienceOptionRow(
        icon: String,
        title: String,
        subtitle: String?,
        tint: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func audienceFriendRow(_ friend: Friend) -> some View {
        let selected = audience.friendIds.contains(friend.id)
        return Button { toggleFriend(friend.id) } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: friend, size: 34)
                Text(friend.displayName)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(friend.displayName)
        .accessibilityValue(selected ? "selected" : "not selected")
    }

    private func audienceCircleRow(_ circle: FFCircle) -> some View {
        let selected = audience.circleIds.contains(circle.id)
        let count = circle.memberIds.count
        return Button { toggleCircle(circle.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: 0xC59A5C).opacity(0.22)).frame(width: 34, height: 34)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC59A5C))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(circle.name)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text("\(count) member\(count == 1 ? "" : "s")")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                checkMark(selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(circle.name)
        .accessibilityValue(selected ? "selected" : "not selected")
    }

    private func checkMark(_ selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.3), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if selected {
                Circle().fill(Theme.alertGreen).frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    // MARK: - Audience selection

    private func toggleEveryone() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            audience.everyone.toggle()
            normalizeAudience()
        }
    }

    private func toggleFriend(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            if audience.isPristineEveryone { audience.everyone = false }
            if audience.friendIds.contains(id) {
                audience.friendIds.remove(id)
            } else {
                audience.friendIds.insert(id)
            }
            normalizeAudience()
        }
    }

    private func toggleCircle(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            if audience.isPristineEveryone { audience.everyone = false }
            if audience.circleIds.contains(id) {
                audience.circleIds.remove(id)
            } else {
                audience.circleIds.insert(id)
            }
            normalizeAudience()
        }
    }

    /// Never leave the send button with nowhere to go: if everything
    /// gets deselected, fall back to the public story.
    private func normalizeAudience() {
        if !audience.everyone && !audience.hasPrivateRecipients {
            audience.everyone = true
        }
    }

    // MARK: - Caption actions

    private func addCaption() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let block = CaptionBlock(
            text: "",
            position: CGPoint(x: 0.5, y: 0.42),
            style: .classic
        )
        captions.append(block)
        openEditor(for: block)
    }

    /// Adds a caption at the tapped point (normalized + clamped clear of
    /// the overlay cluster) and immediately opens the editor.
    private func addCaption(at location: CGPoint, in size: CGSize) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let nx = size.width > 0 ? min(0.9, max(0.1, location.x / size.width)) : 0.5
        let ny = size.height > 0 ? min(0.82, max(0.08, location.y / size.height)) : 0.5
        let block = CaptionBlock(
            text: "",
            position: CGPoint(x: nx, y: ny),
            style: .classic
        )
        captions.append(block)
        openEditor(for: block)
    }

    private func openEditor(for block: CaptionBlock) {
        editingCaptionId = block.id
        draftText = block.text
        draftStyle = block.style
        draftColor = block.color
        activeBlockId = block.id
    }

    private func commitEditor() {
        guard let id = editingCaptionId else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            captions.removeAll { $0.id == id }
            activeBlockId = nil
        } else if let idx = captions.firstIndex(where: { $0.id == id }) {
            captions[idx].text = trimmed
            captions[idx].style = draftStyle
            captions[idx].color = draftColor
        }
        editingCaptionId = nil
    }

    private func cancelEditor() {
        if let id = editingCaptionId,
           let idx = captions.firstIndex(where: { $0.id == id }),
           captions[idx].text.isEmpty {
            captions.remove(at: idx)
            activeBlockId = nil
        }
        editingCaptionId = nil
    }

    /// Drops a freshly-picked task sticker onto the card, gently
    /// staggered so successive picks don't stack perfectly.
    private func addTaskSticker(_ block: TaskStickerBlock) {
        var placed = block
        let step = CGFloat(taskStickers.count % 4)
        placed.position = CGPoint(x: 0.5, y: min(0.66, 0.36 + step * 0.07))
        taskStickers.append(placed)
        activeBlockId = placed.id
    }

    // MARK: - Edit layer rendering

    private var hasEdits: Bool {
        !captions.isEmpty || !taskStickers.isEmpty || !pkCanvas.drawing.strokes.isEmpty
    }

    /// Rasterizes the PencilKit drawing at the card's point size,
    /// preserving the dark-editor ink colors.
    private func drawingSnapshot() -> UIImage? {
        let drawing = pkCanvas.drawing
        guard !drawing.strokes.isEmpty, cardSize.width > 0, cardSize.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: cardSize), scale: UIScreen.main.scale)
        }
        return image
    }

    /// Renders the caption + sticker + drawing layer into one
    /// transparent image at the export's pixel size, laid out in the
    /// card's coordinate space so proportions match what the user saw.
    private func editLayerImage(at pixelSize: CGSize) -> UIImage? {
        let base = cardSize
        guard hasEdits, base.width > 0, base.height > 0, pixelSize.width > 1 else { return nil }
        let drawingImg = drawingSnapshot()
        let content = ZStack {
            Color.clear
                .frame(width: base.width, height: base.height)

            if let drawingImg {
                Image(uiImage: drawingImg)
                    .resizable()
                    .frame(width: base.width, height: base.height)
            }

            ForEach(captions) { block in
                CaptionBlockText(block: block)
                    .scaleEffect(block.scale)
                    .rotationEffect(block.rotation)
                    .position(x: block.position.x * base.width, y: block.position.y * base.height)
            }

            ForEach(taskStickers) { block in
                TaskStickerView(block: block)
                    .scaleEffect(block.scale)
                    .rotationEffect(block.rotation)
                    .position(x: block.position.x * base.width, y: block.position.y * base.height)
            }
        }
        .frame(width: base.width, height: base.height)

        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = false
        renderer.scale = pixelSize.width / max(base.width, 1)
        return renderer.uiImage
    }

    // MARK: - Veil + toast

    private var workingVeil: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Composing…")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.opacity)
    }

    private func postedToast(_ text: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0xFFC668))
                    Text(text)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .allowsHitTesting(false)

                if attachChipVisible {
                    attachChip
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .padding(.bottom, 140)
        }
        .transition(.opacity)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: attachChipVisible)
    }

    /// The quiet post-confirmation invitation — pin the designed card
    /// somewhere it outlives the 24h story.
    private var attachChip: some View {
        Button {
            chipTapped()
        } label: {
            HStack(spacing: 7) {
                HStack(spacing: -2) {
                    Image(systemName: "flag")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "leaf")
                        .font(.system(size: 8, weight: .semibold))
                        .offset(y: -4)
                }
                .foregroundStyle(Color(hex: 0xFFD98A))

                Text(attachChipLabel)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color(hex: 0x1E1C1B).opacity(0.94)))
            .overlay(Capsule().strokeBorder(Color(hex: 0xFFD98A).opacity(0.35), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachChipLabel)
        .accessibilityHint("Keeps the card beyond the 24 hour story")
    }

    private var attachChipLabel: String {
        switch attachContext {
        case .milestone: return "Add to the journey"
        case .noteComposer: return "Add to this note"
        case .none: return "Add to a milestone or note"
        }
    }

    private func chipTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        finishTask?.cancel()
        switch attachContext {
        case .milestone(let id):
            attachAndFinish(.milestone(id))
        case .noteComposer:
            saveToComposerAndFinish()
        case .none:
            showAttachPicker = true
        }
    }

    // MARK: - Destinations

    /// Composes the CLEAN card once (no attribution — it stays inside
    /// the app) and delivers it to every chosen destination: a story
    /// post and/or one private send per selected friend and circle.
    private func sendInApp() {
        guard !isWorking else { return }
        isWorking = true
        if showAudiencePanel { showAudiencePanel = false }
        if isDrawing { isDrawing = false }
        activeBlockId = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            guard let media = await composeCleanMedia() else {
                isWorking = false
                return
            }

            let mediaData: Data
            let mediaType: MediaType
            let duration: Double?
            switch media {
            case .photo(let data):
                mediaData = data
                mediaType = .photo
                duration = nil
            case .video(let data, let dur):
                mediaData = data
                mediaType = .video
                duration = dur
            }

            var toast = "Posted to your people"
            if audience.everyone {
                store.postMedia(
                    imageData: mediaData,
                    type: mediaType,
                    caption: nil,
                    circleId: nil,
                    attachedCircleTaskId: nil,
                    durationSeconds: duration
                )
            }
            // A circle destination is the circle's STORY — each selected
            // circle gets a real circle clip (so every member sees the
            // glowing new-story badge), never a buried private send.
            for circleId in audience.circleIds {
                store.postMedia(
                    imageData: mediaData,
                    type: mediaType,
                    caption: nil,
                    circleId: circleId,
                    attachedCircleTaskId: nil,
                    durationSeconds: duration
                )
            }
            if !audience.friendIds.isEmpty {
                store.sendDirectToFriends(
                    imageData: mediaData,
                    type: mediaType,
                    caption: nil,
                    friendIds: Array(audience.friendIds),
                    durationSeconds: duration
                )
            }
            if audience.hasPrivateRecipients {
                toast = audience.everyone
                    ? "Posted + sent to \(summaryLabel(tokens: privateTokens, empty: "your picks"))"
                    : "Sent to \(summaryLabel(tokens: privateTokens, empty: "your picks"))"
            }
            if audience.everyone || !audience.circleIds.isEmpty {
                libraryItemId = store.recordProofToLibrary(
                    imageData: mediaData,
                    type: mediaType,
                    duration: duration,
                    source: .posted
                )
            }

            isWorking = false
            didPost = true
            pendingAttach = media
            autoPinStickerSources(media)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.25)) {
                postedConfirmation = toast
                attachChipVisible = true
            }
            // The destination was just chosen for the first time — name
            // what it did, over the confirmation, while it's still true.
            // The auto-exit is pushed out rather than cancelled: a
            // lesson that somehow never appears must not be able to
            // strand the editor open.
            if walkthrough.claim(.whoSeesThis) {
                destinationLesson = .whoSeesThis
                scheduleFinish(after: 30)
            } else {
                scheduleFinish(after: 3.4)
            }
        }
    }

    /// Composes the CLEAN card (no attribution — it stays in the app)
    /// once, for posting and/or attaching.
    private func composeCleanMedia() async -> ComposedProofMedia? {
        switch result {
        case .photo(let image):
            let composed = ShareCardRenderer.compositePhoto(
                image,
                composition: composition,
                username: username,
                attributed: false,
                zoom: mediaZoom.scale,
                zoomOffset: mediaZoom.offset,
                zoomCanvas: cardSize,
                editLayer: { size in editLayerImage(at: size) }
            )
            guard let data = composed?.jpegData(compressionQuality: 0.9) else { return nil }
            return .photo(data)

        case .video(let url, _, let dur):
            let composedURL = await ShareCardRenderer.compositeVideo(
                at: url,
                composition: composition,
                username: username,
                attributed: false,
                animated: !reduceMotion,
                zoom: mediaZoom.scale,
                zoomOffset: mediaZoom.offset,
                zoomCanvas: cardSize,
                editLayer: { size in editLayerImage(at: size) }
            )
            guard let data = try? Data(contentsOf: composedURL ?? url) else { return nil }
            return .video(data, duration: dur)
        }
    }

    // MARK: - Attach flow

    /// "Just save" — compose the clean card and keep it on-device only.
    /// Nothing posts, nothing leaves the device.
    private func justSave() {
        guard !isWorking else { return }
        isWorking = true
        if showAudiencePanel { showAudiencePanel = false }
        if isDrawing { isDrawing = false }
        activeBlockId = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            guard let media = await composeCleanMedia() else {
                isWorking = false
                return
            }
            pendingAttach = media
            // "Just save" archives the clean card in the proof library
            // even when nothing posts — it's the user's permanent copy.
            if libraryItemId == nil {
                libraryItemId = store.recordProofToLibrary(media, source: .saved)
            }
            autoPinStickerSources(media)
            isWorking = false
            switch attachContext {
            case .milestone(let id):
                attachAndFinish(.milestone(id))
            case .noteComposer:
                saveToComposerAndFinish()
            case .none:
                showAttachPicker = true
            }
        }
    }

    /// Every target the proof is already pinned to via a task/to-do
    /// sticker on the card. The picker shows these pre-ticked + locked.
    private var stickerTargets: Set<ProofAttachTarget> {
        var result = Set<ProofAttachTarget>()
        for sticker in taskStickers {
            if let id = sticker.sourceTaskId { result.insert(.task(id)) }
            if let id = sticker.sourceTodoId { result.insert(.todo(id)) }
        }
        return result
    }

    /// Multi-select save — attach the composed proof to every newly
    /// ticked destination at once (camera roll handled with the
    /// attributed composite). Sticker-pinned items are skipped since
    /// they were already written.
    private func attachAllAndFinish(_ targets: Set<ProofAttachTarget>) {
        let newTargets = targets.subtracting(stickerTargets)
        let wantsCameraRoll = newTargets.contains(.cameraRoll)
        let pinTargets = newTargets.subtracting([.cameraRoll])

        var savedCount = 0
        var pinLabels: [String] = []
        if let media = pendingAttach {
            for target in pinTargets {
                let ok: Bool
                switch target {
                case .milestone(let id): ok = store.attachProof(media, toMilestone: id)
                case .note(let id): ok = store.attachProof(media, toNote: id)
                case .task(let id): ok = store.attachProof(media, toTaskId: id)
                case .todo(let id): ok = store.attachProof(media, toTodoId: id)
                case .cameraRoll: ok = false
                }
                if ok {
                    savedCount += 1
                    if let label = store.proofTargetLabel(target) { pinLabels.append(label) }
                }
            }
        }
        store.appendProofLibraryLabels(libraryItemId, labels: pinLabels)

        if wantsCameraRoll {
            // The camera-roll path composes the attributed card, saves,
            // toasts, and finishes — fold the pin count into its toast.
            saveToCameraRollAndFinish(alsoPinned: savedCount)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(savedCount > 0 ? .success : .error)
        withAnimation(.easeOut(duration: 0.22)) {
            attachChipVisible = false
            postedConfirmation = savedCount > 0
                ? (savedCount == 1 ? "Pinned in 1 place" : "Pinned in \(savedCount) places")
                : "Couldn't save — try again"
        }
        if savedCount > 0 || didPost {
            scheduleFinish(after: 0.9)
        } else {
            finishTask?.cancel()
            finishTask = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.2)) { postedConfirmation = nil }
            }
        }
    }

    /// A task / to-do sticker on the card auto-pins the composed proof
    /// to that item — the proof documents it without an extra step.
    private func autoPinStickerSources(_ media: ComposedProofMedia) {
        var taskIds = Set<UUID>()
        var todoIds = Set<UUID>()
        for sticker in taskStickers {
            if let id = sticker.sourceTaskId { taskIds.insert(id) }
            if let id = sticker.sourceTodoId { todoIds.insert(id) }
        }
        var labels: [String] = []
        for id in taskIds where store.attachProof(media, toTaskId: id) {
            if let label = store.proofTargetLabel(.task(id)) { labels.append(label) }
        }
        for id in todoIds where store.attachProof(media, toTodoId: id) {
            if let label = store.proofTargetLabel(.todo(id)) { labels.append(label) }
        }
        store.appendProofLibraryLabels(libraryItemId, labels: labels)
    }

    /// Writes the pending card onto the picked destination, confirms,
    /// and closes the camera.
    private func attachAndFinish(_ target: ProofAttachTarget) {
        if case .cameraRoll = target {
            saveToCameraRollAndFinish()
            return
        }
        guard let media = pendingAttach else {
            onFinished()
            return
        }
        let ok: Bool
        let confirmation: String
        switch target {
        case .milestone(let id):
            ok = store.attachProof(media, toMilestone: id)
            confirmation = ok ? "Added to the journey" : "Couldn't save — try again"
        case .note(let id):
            ok = store.attachProof(media, toNote: id)
            confirmation = ok ? "Added to the note" : "Couldn't save — try again"
        case .task(let id):
            ok = store.attachProof(media, toTaskId: id)
            confirmation = ok ? "Pinned to the task" : "Couldn't save — try again"
        case .todo(let id):
            ok = store.attachProof(media, toTodoId: id)
            confirmation = ok ? "Pinned to the to-do" : "Couldn't save — try again"
        case .cameraRoll:
            ok = false
            confirmation = "Couldn't save — try again"
        }
        if ok, let label = store.proofTargetLabel(target) {
            store.appendProofLibraryLabels(libraryItemId, labels: [label])
        }
        UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
        withAnimation(.easeOut(duration: 0.22)) {
            attachChipVisible = false
            postedConfirmation = confirmation
        }
        if ok || didPost {
            scheduleFinish(after: 0.9)
        } else {
            // A failed "Just save" returns to the preview after the toast.
            finishTask?.cancel()
            finishTask = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.2)) { postedConfirmation = nil }
            }
        }
    }

    /// Camera-roll destination — composes the ATTRIBUTED card (anything
    /// leaving the app carries the orb + @username line) and writes it
    /// into the photo library.
    private func saveToCameraRollAndFinish(alsoPinned: Int = 0) {
        guard !isWorking else { return }
        isWorking = true

        Task {
            let outcome: PhotoLibrarySaver.SaveOutcome
            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    composition: composition,
                    username: username,
                    attributed: true,
                    zoom: mediaZoom.scale,
                    zoomOffset: mediaZoom.offset,
                    zoomCanvas: cardSize,
                    editLayer: { size in editLayerImage(at: size) }
                )
                if let data = composed?.jpegData(compressionQuality: 0.9) {
                    outcome = await PhotoLibrarySaver.saveImage(data)
                } else {
                    outcome = .failed
                }

            case .video(let url, _, _):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    composition: composition,
                    username: username,
                    attributed: true,
                    animated: !reduceMotion,
                    zoom: mediaZoom.scale,
                    zoomOffset: mediaZoom.offset,
                    zoomCanvas: cardSize,
                    editLayer: { size in editLayerImage(at: size) }
                )
                outcome = await PhotoLibrarySaver.saveVideo(at: composedURL ?? url)
            }

            isWorking = false
            let ok = outcome == .saved
            let confirmation: String
            switch outcome {
            case .saved:
                confirmation = alsoPinned > 0
                    ? "Saved to camera roll + \(alsoPinned) more"
                    : "Saved to your camera roll"
            case .denied: confirmation = "Allow photo access in Settings to save"
            case .failed: confirmation = "Couldn't save — try again"
            }
            UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
            withAnimation(.easeOut(duration: 0.22)) {
                attachChipVisible = false
                postedConfirmation = confirmation
            }
            if ok || didPost {
                scheduleFinish(after: 1.1)
            } else {
                finishTask?.cancel()
                finishTask = Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.2)) { postedConfirmation = nil }
                }
            }
        }
    }

    /// Note-composer flow — the media file is written, then handed back
    /// to the still-open composer.
    private func saveToComposerAndFinish() {
        guard let media = pendingAttach, let saved = store.saveProofNoteMedia(media) else {
            onFinished()
            return
        }
        onSavedToNoteComposer?(saved)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.22)) {
            attachChipVisible = false
            postedConfirmation = "Added to your note"
        }
        scheduleFinish(after: 0.8)
    }

    /// Auto-close after a beat — cancelled the moment the user engages
    /// with the attach chip.
    private func scheduleFinish(after seconds: Double) {
        finishTask?.cancel()
        finishTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    /// External — attributed composite into the native share sheet
    /// (which also covers save-to-camera-roll, equally attributed).
    private func shareOutside() {
        guard !isWorking else { return }
        isWorking = true
        if showAudiencePanel { showAudiencePanel = false }
        if isDrawing { isDrawing = false }
        activeBlockId = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    composition: composition,
                    username: username,
                    attributed: true,
                    zoom: mediaZoom.scale,
                    zoomOffset: mediaZoom.offset,
                    zoomCanvas: cardSize,
                    editLayer: { size in editLayerImage(at: size) }
                )
                isWorking = false
                if let composed {
                    sharePayload = SharePayload(items: [composed])
                }

            case .video(let url, _, _):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    composition: composition,
                    username: username,
                    attributed: true,
                    animated: !reduceMotion,
                    zoom: mediaZoom.scale,
                    zoomOffset: mediaZoom.offset,
                    zoomCanvas: cardSize,
                    editLayer: { size in editLayerImage(at: size) }
                )
                isWorking = false
                if let composedURL {
                    sharePayload = SharePayload(items: [composedURL])
                } else {
                    // Compositing unavailable (no hardware decode path) —
                    // never strand the user; share the raw clip.
                    sharePayload = SharePayload(items: [url])
                }
            }
        }
    }
}

// MARK: - Share sheet plumbing

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
