//
//  CaptureReviewView.swift
//  FrisFocus
//
//  Instagram / Snapchat-style editor that lands after the shutter.
//  Accepts a `CaptureResult` (photo or video) and lets the user:
//
//   - Apply one of six filters (Original, B&W, Warm, Cool, Fade,
//     Vivid). Photos render the filtered `UIImage`; videos render
//     their first-frame thumbnail with a tinted overlay matching
//     the selected look.
//   - Add one or more **caption blocks**: free-floating text
//     overlays that can be placed anywhere on the canvas, scaled,
//     rotated, restyled, and edited. Eight text styles ship in the
//     style picker (Classic serif, Bold, Subtitle bar, Highlight,
//     Outline, Typewriter, Neon, Tag).
//   - Share to the right destination based on `CaptureMode`.
//
//  For photo posts the canvas + captions are flattened into the
//  final JPEG via `ImageRenderer` so the recipient sees exactly
//  what the author placed. Videos send the raw `.mov` bytes — the
//  caption layer is preserved in the local feed via the post's
//  caption text (joined with newlines as a fallback).
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import PencilKit
import SwiftUI
import UIKit

// MARK: - Share audience

/// Where a general-post moment goes when shared. Any combination is
/// allowed: `everyone` is the public 24h story, plus any number of
/// `circleIds` and `friendIds` for private sends. Private sends create
/// one `DirectShare` per recipient (each friend gets a personal copy; a
/// circle goes to its members) — selecting several is NOT a group
/// thread. Only meaningful for `.generalPost`; circle clips keep their
/// fixed destination.
private struct ShareAudience: Equatable {
    var everyone: Bool
    var friendIds: Set<UUID>
    var circleIds: Set<UUID>

    /// The opening default — public story only, nothing hand-picked.
    static let initial = ShareAudience(everyone: true, friendIds: [], circleIds: [])

    /// Pristine default: the public story and nothing else.
    var isPristineEveryone: Bool {
        everyone && friendIds.isEmpty && circleIds.isEmpty
    }

    /// Any hand-picked private recipients (friends and/or circles).
    var hasPrivateRecipients: Bool {
        !friendIds.isEmpty || !circleIds.isEmpty
    }
}

// MARK: - Filter catalog

enum CaptureFilter: String, CaseIterable, Identifiable {
    case original, bw, warm, cool, fade, vivid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .bw: return "B&W"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .fade: return "Fade"
        case .vivid: return "Vivid"
        }
    }

    var tintOverlay: Color {
        switch self {
        case .original: return .clear
        case .bw: return Color(white: 0.5).opacity(0.0)
        case .warm: return Color(hex: 0xE89A55).opacity(0.18)
        case .cool: return Color(hex: 0x4A7AAE).opacity(0.18)
        case .fade: return Color(hex: 0xF4E4D0).opacity(0.16)
        case .vivid: return Color(hex: 0xFF4F8B).opacity(0.10)
        }
    }

    func apply(to image: UIImage) -> UIImage {
        guard self != .original, let ci = CIImage(image: image) else { return image }
        let context = CIContext()
        var output: CIImage = ci

        switch self {
        case .original:
            return image
        case .bw:
            let f = CIFilter.colorControls()
            f.inputImage = output
            f.saturation = 0
            f.contrast = 1.10
            output = f.outputImage ?? output
        case .warm:
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = output
            temp.neutral = CIVector(x: 5500, y: 0)
            temp.targetNeutral = CIVector(x: 4200, y: 12)
            output = temp.outputImage ?? output
        case .cool:
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = output
            temp.neutral = CIVector(x: 5500, y: 0)
            temp.targetNeutral = CIVector(x: 7200, y: -8)
            output = temp.outputImage ?? output
        case .fade:
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.saturation = 0.78
            controls.brightness = 0.04
            controls.contrast = 0.92
            output = controls.outputImage ?? output
        case .vivid:
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.saturation = 1.35
            controls.contrast = 1.08
            output = controls.outputImage ?? output
        }

        guard let cg = context.createCGImage(output, from: ci.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Caption styling

/// The eight text styles offered in the caption editor. Each style
/// owns its font, fill color, background treatment, and stroke.
enum CaptionStyle: String, CaseIterable, Identifiable {
    case classic, bold, subtitle, highlight, outline, typewriter, neon, tag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .bold: return "Bold"
        case .subtitle: return "Subtitle"
        case .highlight: return "Highlight"
        case .outline: return "Outline"
        case .typewriter: return "Typewriter"
        case .neon: return "Neon"
        case .tag: return "Tag"
        }
    }

    /// Sample glyph shown in the style picker chip.
    var glyphSample: String { "Aa" }

    /// Filled styles paint their *background* with the chosen color (and
    /// flip the text to a contrasting black/white). Plain styles paint
    /// the *text* itself. Used by the color picker so one swatch does the
    /// intuitive thing per style.
    var isFilled: Bool {
        switch self {
        case .subtitle, .highlight, .typewriter, .tag: return true
        case .classic, .bold, .outline, .neon: return false
        }
    }
}

/// Curated caption colors offered as swatches in the editor. A leading
/// "Auto" option (represented by `nil`) keeps each style's natural look;
/// a trailing spectrum chip opens the full system picker for any shade.
let captionPalette: [Color] = [
    .white,
    Color(hex: 0x2C2C2A),
    Color(hex: 0xE0454C),
    Color(hex: 0xD87D44),
    Color(hex: 0xF2C14E),
    Color(hex: 0x8FB339),
    Color(hex: 0x3FA7B7),
    Color(hex: 0x4A7AAE),
    Color(hex: 0x7F77DD),
    Color(hex: 0xFF3D8B),
]

/// Picks legible text (near-black or white) for a chosen background fill,
/// based on perceived luminance.
func contrastingInk(on background: Color) -> Color {
    let ui = UIColor(background)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    let luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return luminance > 0.62 ? Color(hex: 0x2C2C2A) : .white
}

/// A free-floating piece of text painted over the canvas.
struct CaptionBlock: Identifiable, Equatable {
    let id: UUID
    var text: String
    /// Normalized position (0…1) in the canvas. (0.5, 0.5) is dead
    /// center; storing normalized coords keeps captions stable when
    /// the canvas resizes during keyboard transitions.
    var position: CGPoint
    var style: CaptionStyle
    var scale: CGFloat
    var rotation: Angle
    /// Chosen color. `nil` means "Auto" — the style renders with its
    /// natural built-in colors. When set, plain styles tint the text and
    /// filled styles tint the background.
    var color: Color?

    init(
        id: UUID = UUID(),
        text: String = "",
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        style: CaptionStyle = .classic,
        scale: CGFloat = 1.0,
        rotation: Angle = .zero,
        color: Color? = nil
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.style = style
        self.scale = scale
        self.rotation = rotation
        self.color = color
    }
}

// MARK: - Styled caption renderer

/// Renders a single caption block with the look defined by its
/// `CaptionStyle`. Used both inside the live canvas and inside the
/// flattened-image renderer so the exported JPEG matches what the
/// user saw.
struct CaptionBlockText: View {
    let block: CaptionBlock
    /// `true` while the block is being actively dragged / edited.
    /// We use this to brighten the placeholder treatment when empty.
    var isPlaceholder: Bool = false

    var body: some View {
        let displayText = block.text.isEmpty ? "tap to type" : block.text
        let fontSize: CGFloat = 24

        switch block.style {
        case .classic:
            Text(displayText)
                .font(.serif(fontSize, weight: .medium))
                .foregroundStyle(plainInk(.white))
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

        case .bold:
            Text(displayText.uppercased())
                .font(.sans(fontSize - 1, weight: .black))
                .tracking(0.6)
                .foregroundStyle(plainInk(.white))
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.65), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

        case .subtitle:
            Text(displayText)
                .font(.sans(fontSize - 4, weight: .semibold))
                .foregroundStyle(onFill(.white))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(fill(Color.black.opacity(0.78)))

        case .highlight:
            Text(displayText)
                .font(.sans(fontSize - 2, weight: .heavy))
                .foregroundStyle(onFill(Theme.textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(fill(Theme.textCream))

        case .outline:
            ZStack {
                ForEach(outlineOffsets, id: \.self) { offset in
                    Text(displayText)
                        .font(.sans(fontSize, weight: .black))
                        .foregroundStyle(Color.black)
                        .offset(x: offset.x, y: offset.y)
                }
                Text(displayText)
                    .font(.sans(fontSize, weight: .black))
                    .foregroundStyle(plainInk(.white))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

        case .typewriter:
            Text(displayText)
                .font(.system(size: fontSize - 4, weight: .medium, design: .monospaced))
                .foregroundStyle(onFill(Theme.textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(fill(Theme.textCream.opacity(0.94)))

        case .neon:
            let neonText = block.color ?? Color(hex: 0xFFE7F2)
            let glow = block.color ?? Color(hex: 0xFF3D8B)
            let glowFar = block.color ?? Color(hex: 0x6E66FF)
            Text(displayText)
                .font(.sans(fontSize, weight: .bold))
                .foregroundStyle(dim(neonText))
                .multilineTextAlignment(.center)
                .shadow(color: glow.opacity(0.95), radius: 6)
                .shadow(color: glow.opacity(0.85), radius: 14)
                .shadow(color: glowFar.opacity(0.55), radius: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

        case .tag:
            HStack(spacing: 4) {
                Text("#")
                    .font(.sans(fontSize - 6, weight: .heavy))
                    .foregroundStyle(onFill(Theme.alertGreen))
                Text(displayText)
                    .font(.sans(fontSize - 4, weight: .semibold))
                    .foregroundStyle(onFill(.white))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(fill(Color.black.opacity(0.55)))
            )
            .overlay(
                Capsule().strokeBorder((block.color ?? Theme.alertGreen).opacity(0.55), lineWidth: 0.8)
            )
        }
    }

    private var outlineOffsets: [CGPoint] {
        [
            CGPoint(x: -1.5, y: 0), CGPoint(x: 1.5, y: 0),
            CGPoint(x: 0, y: -1.5), CGPoint(x: 0, y: 1.5),
            CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
            CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)
        ]
    }

    /// Plain-style text fill: the chosen color, or `def` when Auto.
    private func plainInk(_ def: Color) -> Color {
        dim(block.color ?? def)
    }

    /// Filled-style background: the chosen color, or the style's natural
    /// `def` background when Auto.
    private func fill(_ def: Color) -> Color {
        block.color ?? def
    }

    /// Text drawn on top of a filled background — the style's natural
    /// `def` when Auto, otherwise an auto-contrasting black/white.
    private func onFill(_ def: Color) -> Color {
        dim(block.color == nil ? def : contrastingInk(on: block.color!))
    }

    private func dim(_ c: Color) -> Color {
        isPlaceholder ? c.opacity(0.55) : c
    }
}

// MARK: - CaptureReviewView

struct CaptureReviewView: View {
    @Environment(Store.self) private var store

    let result: CaptureResult
    let mode: CaptureMode
    let onPosted: () -> Void
    let onRetake: () -> Void
    /// Seeded onto the canvas when the editor opens — set when the camera
    /// was launched from a task / to-do card. The user can still add more
    /// via the "Add task" tool.
    var initialTaskSticker: TaskStickerBlock? = nil
    /// When the review opens from a friend's hub via "Send a proof,"
    /// this friend starts preselected as the private recipient.
    var initialDirectFriendId: UUID? = nil
    /// Live Proofs path: when set, the editor sends the finished proof to
    /// exactly one real account through this async closure (skipping the
    /// local store) and hides the audience chooser. `liveProofRecipientName`
    /// labels the fixed destination chip.
    var liveProofRecipientName: String? = nil
    var onSendLiveProof: ((_ data: Data, _ isVideo: Bool, _ duration: Double?, _ caption: String?) async -> Void)? = nil
    /// When resuming a saved draft, this carries the restored filter,
    /// captions, stickers, and drawing back onto the canvas. Non-nil also
    /// marks the session as draft-backed (posting or discarding clears
    /// the stored draft).
    var initialDraftState: CaptureEditorDraft? = nil

    // Caption state
    @State private var captions: [CaptionBlock] = []
    @State private var editingCaptionId: UUID? = nil
    @State private var draftText: String = ""
    @State private var draftStyle: CaptionStyle = .classic
    /// Chosen color for the caption being edited. `nil` is "Auto".
    @State private var draftColor: Color? = nil
    @FocusState private var captionFocused: Bool

    // Selection + trash state. In-flight drag/pinch/rotate values now
    // live inside `DraggableCaptionView` as @GestureState, so a gesture
    // never mutates `captions` until it ends — that's what keeps the
    // manipulation smooth (the old code rewrote the array every frame,
    // re-rendering the whole canvas including the background image).
    @State private var draggingOverTrash: Bool = false
    @State private var activeBlockId: UUID? = nil
    /// `true` only while a caption / task sticker is actively being
    /// dragged. The "drop to delete" zone keys off this so it appears on
    /// drag — not when an item is merely tapped to select.
    @State private var isDraggingBlock: Bool = false

    @State private var isPosting: Bool = false
    @State private var selectedFilter: CaptureFilter = .original
    @State private var filteredImageCache: [CaptureFilter: UIImage] = [:]
    @State private var thumbCache: [CaptureFilter: UIImage] = [:]
    @State private var canvasSize: CGSize = .zero

    /// Downscaled bases for the live canvas and the filter chips. The
    /// camera hands back a full-resolution photo (often 12MP+);
    /// compositing that texture on every drag frame is what made moving
    /// captions / stickers feel heavy, and running CIFilters over it on
    /// the main thread hitched the filter strip. The canvas renders from
    /// `displayBase` (capped near export resolution, so the flattened
    /// JPEG is unchanged) and the 54pt chips from a tiny `chipBase`.
    @State private var displayBase: UIImage?
    @State private var chipBase: UIImage?

    @State private var showDiscardConfirm: Bool = false

    // Save-to-camera-roll state. `isSaving` swaps the top-bar download glyph
    // for a spinner; `showSaveDenied` raises the Settings prompt when
    // add-only photo access is off.
    @State private var isSaving: Bool = false
    @State private var showSaveDenied: Bool = false

    // Share destination (general posts only). Circle clips keep their
    // fixed destination and never show the chooser.
    @State private var audience: ShareAudience = .initial
    @State private var showAudiencePanel: Bool = false
    @State private var sentToast: String? = nil

    // Task sticker state. Stickers share the active-selection + trash
    // plumbing with captions (ids are unique across both) and bake into
    // the exported photo alongside the caption layer.
    @State private var taskStickers: [TaskStickerBlock] = []
    @State private var showTaskPicker: Bool = false

    // Freehand drawing (PencilKit). The canvas + tool picker persist for
    // the editor's lifetime; `isDrawing` engages draw mode (canvas accepts
    // input + the system palette shows). Strokes are baked into the
    // exported photo and burned into shared videos.
    @State private var pkCanvas = PKCanvasView()
    @State private var pkToolPicker = PKToolPicker()
    @State private var isDrawing: Bool = false

    private var sourceImage: UIImage {
        switch result {
        case .photo(let image): return image
        case .video(_, let thumb, _): return thumb ?? UIImage()
        }
    }

    private var filteredImage: UIImage {
        if let cached = filteredImageCache[selectedFilter] { return cached }
        let out = selectedFilter.apply(to: displayBase ?? sourceImage)
        filteredImageCache[selectedFilter] = out
        return out
    }

    private var isEditing: Bool { editingCaptionId != nil }

    /// True when leaving would lose real work — drives the discard /
    /// save-draft confirmation instead of silently destroying edits.
    private var hasEdits: Bool {
        !captions.isEmpty
            || !taskStickers.isEmpty
            || selectedFilter != .original
            || !pkCanvas.drawing.strokes.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            mediaCanvas
            overlayChrome
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .confirmationDialog(
            "Leave this post?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Save draft") {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                CaptureDraftStore.save(
                    result: result,
                    filter: selectedFilter,
                    captions: captions,
                    stickers: taskStickers,
                    drawing: pkCanvas.drawing
                )
                onRetake()
            }
            Button("Discard", role: .destructive) {
                // Discarding a restored draft throws the stored copy
                // away too — otherwise an untouched draft stays put.
                if initialDraftState != nil { CaptureDraftStore.clear() }
                onRetake()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save a draft to pick this up later, or discard your edits.")
        }
        .alert("Photos access needed", isPresented: $showSaveDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("FrisFocus needs permission to add to your photos. You can turn it on in Settings.")
        }
        .sheet(isPresented: $showTaskPicker) {
            TaskStickerPickerView { block in
                addTaskSticker(block)
            }
            .environment(store)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .task { await prepareScaledBases() }
        .task {
            // Resuming a draft: restore the whole composition first so
            // the seed below (which checks for emptiness) never doubles.
            if let draft = initialDraftState {
                captions = draft.captions
                taskStickers = draft.stickers
                selectedFilter = draft.filter
                pkCanvas.drawing = draft.drawing
            }
            if var seed = initialTaskSticker, taskStickers.isEmpty {
                seed.position = CGPoint(x: 0.5, y: 0.6)
                taskStickers = [seed]
            }
            // "Send a proof" from a friend hub preselects that friend as
            // the private recipient (no public story by default).
            if let friendId = initialDirectFriendId,
               audience == .initial,
               store.friend(by: friendId) != nil {
                audience = ShareAudience(everyone: false, friendIds: [friendId], circleIds: [])
            }
        }
    }

    // MARK: - Overlay chrome

    /// Chrome, editor, trash and toast layers. The implicit animations
    /// live here — scoped away from `mediaCanvas` — so selection / drag
    /// state flips never schedule an animated layout pass over the
    /// background image and the live sticker/caption layer.
    @ViewBuilder
    private var overlayChrome: some View {
        Group {
            if !isEditing && !isDrawing {
                chromeLayer
            }
            if isDrawing {
                drawingChrome
            }
            if isEditing {
                captionEditorOverlay
            }
            if isDraggingBlock && !isEditing && !isDrawing {
                trashOverlay
            }
            if let sentToast {
                sentToastView(sentToast)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isEditing)
        .animation(.easeInOut(duration: 0.18), value: activeBlockId)
        .animation(.easeInOut(duration: 0.18), value: isDraggingBlock)
        .animation(.easeInOut(duration: 0.2), value: isDrawing)
        .animation(.easeInOut(duration: 0.2), value: sentToast)
    }

    /// Builds the downscaled display / chip bases off the main thread,
    /// then resets the filter caches so they re-fill at display size.
    private func prepareScaledBases() async {
        let source = sourceImage
        guard source.size.width > 0, source.size.height > 0 else { return }
        let display = await source.scaledDown(maxPixelDimension: 2800)
        let chip = await source.scaledDown(maxPixelDimension: 200)
        displayBase = display ?? source
        chipBase = chip ?? source
        filteredImageCache = [:]
        thumbCache = [:]
    }

    // MARK: - Media canvas

    @ViewBuilder
    private var mediaCanvas: some View {
        GeometryReader { geo in
            ZStack {
                // Photos render the filtered still; a just-recorded video
                // plays live on a loop (with sound) so the user reviews
                // the actual clip — the filter look stays a tint overlay,
                // matching what exports.
                if case .video(let url, _, _) = result {
                    VideoLoopView(url: url, gravity: .resizeAspectFill)
                        .id(url)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    Image(uiImage: filteredImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                if isVideo {
                    selectedFilter.tintOverlay
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                }

                if case .video(_, _, let dur) = result {
                    VStack {
                        videoBadge(duration: dur)
                            .padding(.top, 60)
                        Spacer()
                    }
                }

                // Freehand drawing layer. Sits beneath captions/stickers
                // so text stays legible; becomes interactive and rises to
                // the top only while draw mode is engaged.
                DrawingCanvasView(canvas: $pkCanvas, isActive: isDrawing, toolPicker: pkToolPicker)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(isDrawing)
                    .zIndex(isDrawing ? 50 : 0)

                // Caption layer
                ForEach(captions) { block in
                    captionView(block, in: geo.size)
                }

                // Task sticker layer (sits above captions)
                ForEach(taskStickers) { block in
                    stickerView(block, in: geo.size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        // While drawing, taps belong to the canvas.
                        guard !isDrawing else { return }
                        // If a caption is selected, the first tap just
                        // clears the selection. Otherwise drop a fresh
                        // caption right where the finger landed and open
                        // the editor so the user can start typing.
                        if activeBlockId != nil {
                            activeBlockId = nil
                        } else {
                            addCaption(at: value.location, in: geo.size)
                        }
                    }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .ignoresSafeArea()
    }

    private var isVideo: Bool {
        if case .video = result { return true }
        return false
    }

    private func videoBadge(duration: Double) -> some View {
        let total = Int(duration.rounded())
        return HStack(spacing: 5) {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(String(format: "0:%02d", total))
                .font(.sans(11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    // MARK: - Caption block view

    /// Wires a single caption block to the parent's state. All the
    /// in-flight gesture work happens inside `DraggableCaptionView`;
    /// the closures here only fire on gesture *end* (or on a discrete
    /// selection / trash-threshold change), so `captions` is touched
    /// rarely rather than on every frame.
    @ViewBuilder
    private func captionView(_ block: CaptionBlock, in size: CGSize) -> some View {
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
            }
        )
    }

    // MARK: - Task sticker block view

    /// Wires a single task sticker to the parent's state. Mirrors
    /// `captionView` — all in-flight gesture work lives inside
    /// `DraggableStickerView`, so `taskStickers` is only touched on
    /// gesture end / discrete selection changes.
    @ViewBuilder
    private func stickerView(_ block: TaskStickerBlock, in size: CGSize) -> some View {
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
            }
        )
    }

    /// Drops a freshly-picked task sticker onto the canvas, gently
    /// staggered so successive picks don't stack perfectly, and selects
    /// it so the user can reposition immediately.
    private func addTaskSticker(_ block: TaskStickerBlock) {
        var placed = block
        let step = CGFloat(taskStickers.count % 4)
        placed.position = CGPoint(x: 0.5, y: min(0.72, 0.42 + step * 0.07))
        taskStickers.append(placed)
        activeBlockId = placed.id
    }

    // MARK: - Drawing chrome

    /// Minimal top bar shown while draw mode is engaged. The system tool
    /// picker (pen / eraser / colors / width) floats at the bottom on its
    /// own; here we offer Undo, Clear, and Done.
    private var drawingChrome: some View {
        VStack {
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
            .padding(.top, 8)

            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Chrome layer

    private var chromeLayer: some View {
        ZStack {
            // Dimming scrim behind the chooser. Catches taps on the
            // photo so they collapse the panel instead of dropping a
            // caption.
            if showAudiencePanel {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeAudiencePanel() }
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    if showAudiencePanel {
                        audiencePanel
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        captionToolRow
                            .padding(.horizontal, 22)

                        filterStrip
                    }

                    bottomBar
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)
                }
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                )
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            chromeButton(systemName: "chevron.left") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if hasEdits {
                    showDiscardConfirm = true
                } else {
                    onRetake()
                }
            }
            .accessibilityLabel("Retake")

            Spacer()

            if case .circleClip(_, let task) = mode, let task {
                earnedBadge(taskTitle: task.title)
            }

            Spacer()

            HStack(spacing: 10) {
                saveButton

                chromeButton(systemName: "xmark") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showDiscardConfirm = true
                }
                .accessibilityLabel("Discard")
            }
        }
    }

    /// Download-arrow button that saves the composed (edited) photo/video to
    /// the camera roll. Swaps to a spinner while the save runs so the user
    /// gets feedback on the slower video path.
    private var saveButton: some View {
        Button {
            saveToCameraRoll()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.black.opacity(0.40)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Save to camera roll")
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.40)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func earnedBadge(taskTitle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
            Text(taskTitle)
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.alertGreen.opacity(0.18)))
        .overlay(Capsule().strokeBorder(Theme.alertGreen.opacity(0.55), lineWidth: 0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earned \(taskTitle)")
    }

    // MARK: - Caption tool row

    /// "Add text" + (if a block is selected) Edit / Style / Delete
    /// quick actions.
    private var captionToolRow: some View {
        HStack(spacing: 10) {
            Button {
                addCaption()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "textformat")
                        .font(.system(size: 12, weight: .semibold))
                    Text(captions.isEmpty ? "add text" : "add another")
                        .font(.sans(13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeBlockId = nil
                showTaskPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                    Text("add task")
                        .font(.sans(13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a task sticker")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeBlockId = nil
                withAnimation(.easeInOut(duration: 0.2)) { isDrawing = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 12, weight: .semibold))
                    Text("draw")
                        .font(.sans(13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Draw on the photo")

            if let activeId = activeBlockId,
               let block = captions.first(where: { $0.id == activeId }) {
                Button {
                    openEditor(for: block)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit caption")

                Button {
                    cycleStyle(for: block)
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cycle style")
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CaptureFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 92)
    }

    private func filterChip(_ filter: CaptureFilter) -> some View {
        let isSelected = (filter == selectedFilter)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedFilter = filter
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let thumbImage = thumb(for: filter) {
                        Image(uiImage: thumbImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 54, height: 54)
                    }

                    if isVideo {
                        filter.tintOverlay
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Theme.textCream : Color.white.opacity(0.25),
                            lineWidth: isSelected ? 2 : 0.6
                        )
                )

                Text(filter.label)
                    .font(.sans(10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.label) filter")
    }

    /// Chip thumbnails are filtered from the tiny `chipBase` — never
    /// the full-resolution source. Returns `nil` (a neutral placeholder
    /// chip) for the first frames until the base is prepared.
    private func thumb(for filter: CaptureFilter) -> UIImage? {
        if let cached = thumbCache[filter] { return cached }
        guard let base = chipBase else { return nil }
        let img = filter.apply(to: base)
        thumbCache[filter] = img
        return img
    }

    // MARK: - Bottom bar (destination + share)

    private var bottomBar: some View {
        HStack(spacing: 12) {
            destinationRow

            Button {
                post()
            } label: {
                HStack(spacing: 6) {
                    if isPosting {
                        ProgressView().progressViewStyle(.circular).tint(Theme.textCream)
                    }
                    Text(shareButtonText)
                        .font(.sans(14, weight: .semibold))
                    if !isPosting {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.textCream)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Capsule().fill(Theme.textPrimary))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(isPosting)
            .opacity(isPosting ? 0.7 : 1.0)
            .accessibilityLabel(isPrivateSend ? "Send a proof" : "Share")
        }
    }

    private var destinationRow: some View {
        Group {
            if canChooseAudience {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if showAudiencePanel {
                        closeAudiencePanel()
                    } else {
                        activeBlockId = nil
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            showAudiencePanel = true
                        }
                    }
                } label: {
                    destinationPill(expandable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send to \(audienceTitle). Tap to change.")
            } else {
                destinationPill(expandable: false)
            }
        }
    }

    /// True when this editor is wired to send to one real account (the
    /// live Proofs thread) rather than the local store.
    private var isLiveProof: Bool { onSendLiveProof != nil }

    /// Only general posts can pick a destination; a circle clip is
    /// pinned to the circle it documents, and a live proof is pinned to
    /// its one real recipient.
    private var canChooseAudience: Bool {
        if isLiveProof { return false }
        if case .generalPost = mode { return true }
        return false
    }

    private func destinationPill(expandable: Bool) -> some View {
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
            if expandable {
                Image(systemName: showAudiencePanel ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(showAudiencePanel ? 0.16 : 0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .contentShape(Capsule())
    }

    private var audienceIcon: String {
        if isLiveProof { return "person.fill" }
        switch mode {
        case .circleClip:
            return "circle.hexagongrid.fill"
        case .generalPost:
            if audience.isPristineEveryone { return "person.2.fill" }
            let friendCount = audience.friendIds.count
            let circleCount = audience.circleIds.count
            // A single private target gets a precise glyph; anything
            // mixed (or story + private) reads as a small group.
            if !audience.everyone && friendCount == 1 && circleCount == 0 { return "person.fill" }
            if !audience.everyone && friendCount == 0 && circleCount == 1 { return "circle.hexagongrid.fill" }
            return "person.3.fill"
        }
    }

    private var destinationTint: Color {
        if isLiveProof { return Color(hex: 0x8FB339) }
        switch mode {
        case .circleClip:
            return Color(hex: 0xC59A5C)
        case .generalPost:
            return audience.isPristineEveryone ? Color(hex: 0xD87D44) : Color(hex: 0x8FB339)
        }
    }

    private var audienceTitle: String {
        if isLiveProof { return "To \(liveProofRecipientName ?? "your friend")" }
        switch mode {
        case .circleClip(let circle, _):
            return circle.name
        case .generalPost:
            if audience.isPristineEveryone { return "Friends · 24h" }
            return summaryLabel(tokens: audienceTokens, empty: "Select destination")
        }
    }

    private var audienceSubtitle: String {
        if isLiveProof { return "A private proof \u{00B7} just them" }
        switch mode {
        case .circleClip:
            return "Archived in the circle's story"
        case .generalPost:
            if audience.isPristineEveryone { return "Disappears in a day" }
            if audience.everyone { return "Public story + a proof to each" }
            let count = audience.friendIds.count + audience.circleIds.count
            return count <= 1 ? "A proof · just them" : "A proof to each"
        }
    }

    /// Selected circles, resolved and name-sorted for a stable label.
    private var selectedCircles: [FFCircle] {
        audience.circleIds
            .compactMap { store.circle(by: $0) }
            .sorted { $0.name < $1.name }
    }

    /// Selected friends, resolved and name-sorted for a stable label.
    private var selectedFriends: [Friend] {
        audience.friendIds
            .compactMap { store.friend(by: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Human tokens for the current selection — story first, then
    /// circles, then friends — a stable order for the pill label.
    private var audienceTokens: [String] {
        var tokens: [String] = []
        if audience.everyone { tokens.append("Friends · 24h") }
        tokens.append(contentsOf: selectedCircles.map { $0.name })
        tokens.append(contentsOf: selectedFriends.map { $0.displayName })
        return tokens
    }

    /// Private recipients only (circles, then friends) — for the toast.
    private var privateTokens: [String] {
        selectedCircles.map { $0.name } + selectedFriends.map { $0.displayName }
    }

    /// Collapses tokens into "A", "A + 1 other", "A + 3 others", etc.
    private func summaryLabel(tokens: [String], empty: String) -> String {
        guard let first = tokens.first else { return empty }
        if tokens.count == 1 { return first }
        let others = tokens.count - 1
        return "\(first) + \(others) other\(others == 1 ? "" : "s")"
    }

    /// True when the current selection includes any private recipient
    /// (friends and/or circles) — drives the "Send" vs "Share" label.
    private var isPrivateSend: Bool {
        if isLiveProof { return true }
        guard canChooseAudience else { return false }
        return audience.hasPrivateRecipients
    }

    // MARK: - Audience chooser panel

    /// Circles the current user belongs to — the only ones they can
    /// send into.
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
                Button { closeAudiencePanel() } label: {
                    Text("Done")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
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
                        selected: isEveryoneSelected
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
            .frame(maxHeight: 300)
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
        let selected = isFriendSelected(friend.id)
        return Button { toggleFriend(friend.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: friend.accentColorHex)).frame(width: 34, height: 34)
                    Text(friend.initials)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.textCream)
                }
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
        let selected = isCircleSelected(circle.id)
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

    private var isEveryoneSelected: Bool { audience.everyone }

    private func isFriendSelected(_ id: UUID) -> Bool { audience.friendIds.contains(id) }

    private func isCircleSelected(_ id: UUID) -> Bool { audience.circleIds.contains(id) }

    /// Toggle the public story. It coexists with private recipients, so
    /// you can post to your story *and* send to people in one shot.
    private func toggleEveryone() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.16)) {
            audience.everyone.toggle()
            normalizeAudience()
        }
    }

    /// Friends and circles combine freely — any number of each. The
    /// first private pick from the pristine default flips intent away
    /// from the public story, so a single tap means "just this person".
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

    /// Never leave the share button with nowhere to go: if everything
    /// gets deselected, fall back to the public story.
    private func normalizeAudience() {
        if !audience.everyone && !audience.hasPrivateRecipients {
            audience.everyone = true
        }
    }

    private func closeAudiencePanel() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            showAudiencePanel = false
        }
    }

    // MARK: - Sent confirmation toast

    private func sentToastView(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                Text(text)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color(hex: 0x1E1C1B).opacity(0.96)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.4), radius: 14, y: 6)
            Spacer()
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    // MARK: - Trash overlay (shown when dragging a block)

    private var trashOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
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
                Spacer()
            }
            .padding(.bottom, 30)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Caption editor overlay (text + style picker)

    private var captionEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { commitEditor() }

            VStack(spacing: 18) {
                Spacer()

                // Live preview of the draft block.
                CaptionBlockText(
                    block: CaptionBlock(
                        text: draftText,
                        style: draftStyle,
                        color: draftColor
                    ),
                    isPlaceholder: draftText.isEmpty
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)

                Spacer()

                TextField(
                    "",
                    text: $draftText,
                    prompt: Text("type something")
                        .foregroundStyle(Color.white.opacity(0.45)),
                    axis: .vertical
                )
                .font(.sans(18, weight: .medium))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(1...5)
                .focused($captionFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                )
                .padding(.horizontal, 22)

                stylePicker
                    .padding(.bottom, 2)

                colorPickerRow
                    .padding(.bottom, 6)

                HStack {
                    Button("Cancel") {
                        cancelEditor()
                    }
                    .foregroundStyle(Color.white.opacity(0.75))
                    .font(.sans(14, weight: .medium))

                    Spacer()

                    Button("Done") {
                        commitEditor()
                    }
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.textPrimary))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .transition(.opacity)
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CaptionStyle.allCases) { style in
                    styleChip(style)
                }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 64)
    }

    // MARK: - Color picker

    private var colorPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 11) {
                autoColorChip
                ForEach(Array(captionPalette.enumerated()), id: \.offset) { _, swatch in
                    colorSwatch(swatch)
                }
                spectrumChip
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 46)
    }

    private var autoColorChip: some View {
        let selected = (draftColor == nil)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            draftColor = nil
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 30, height: 30)
                Image(systemName: "a.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(4)
            .overlay(
                Circle().strokeBorder(selected ? Theme.textCream : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Automatic color")
    }

    private func colorSwatch(_ color: Color) -> some View {
        let selected = (draftColor == color)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            draftColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6))
                .padding(4)
                .overlay(
                    Circle().strokeBorder(selected ? Theme.textCream : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caption color")
    }

    private var spectrumChip: some View {
        let custom = (draftColor != nil) && !captionPalette.contains(where: { $0 == draftColor })
        return ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 30, height: 30)
            ColorPicker(
                "",
                selection: Binding(
                    get: { draftColor ?? .white },
                    set: { draftColor = $0 }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .scaleEffect(0.82)
            .frame(width: 26, height: 26)
        }
        .padding(4)
        .overlay(
            Circle().strokeBorder(custom ? Theme.textCream : Color.clear, lineWidth: 2)
        )
        .accessibilityLabel("More colors")
    }

    private func styleChip(_ style: CaptionStyle) -> some View {
        let isSelected = style == draftStyle
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.14)) {
                draftStyle = style
            }
        } label: {
            VStack(spacing: 4) {
                CaptionBlockText(
                    block: CaptionBlock(text: style.glyphSample, style: style)
                )
                .scaleEffect(0.55)
                .frame(width: 50, height: 32)
                .clipped()

                Text(style.label)
                    .font(.sans(9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
            }
            .frame(width: 64)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.textCream : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.label) style")
    }

    // MARK: - Caption actions

    private func addCaption() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let block = CaptionBlock(
            text: "",
            position: CGPoint(x: 0.5, y: 0.5),
            style: .classic
        )
        captions.append(block)
        openEditor(for: block)
    }

    /// Adds a caption at the tapped point (normalized + clamped so it
    /// stays clear of the top/bottom chrome) and immediately opens the
    /// editor — tapping the canvas should prompt for text straight away.
    private func addCaption(at location: CGPoint, in size: CGSize) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let nx = size.width > 0 ? min(0.9, max(0.1, location.x / size.width)) : 0.5
        let ny = size.height > 0 ? min(0.86, max(0.12, location.y / size.height)) : 0.5
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
        // Pop the keyboard after the overlay renders.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            captionFocused = true
        }
    }

    private func commitEditor() {
        guard let id = editingCaptionId else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Empty text → drop the block silently.
            captions.removeAll { $0.id == id }
            activeBlockId = nil
        } else if let idx = captions.firstIndex(where: { $0.id == id }) {
            captions[idx].text = trimmed
            captions[idx].style = draftStyle
            captions[idx].color = draftColor
        }
        editingCaptionId = nil
        captionFocused = false
    }

    private func cancelEditor() {
        // If the block was freshly added with no text, drop it.
        if let id = editingCaptionId,
           let idx = captions.firstIndex(where: { $0.id == id }),
           captions[idx].text.isEmpty {
            captions.remove(at: idx)
            activeBlockId = nil
        }
        editingCaptionId = nil
        captionFocused = false
    }

    private func cycleStyle(for block: CaptionBlock) {
        guard let idx = captions.firstIndex(where: { $0.id == block.id }) else { return }
        let all = CaptionStyle.allCases
        guard let curIdx = all.firstIndex(of: block.style) else { return }
        let next = all[(curIdx + 1) % all.count]
        UISelectionFeedbackGenerator().selectionChanged()
        captions[idx].style = next
    }

    // MARK: - Post

    private var shareButtonText: String {
        if isPosting {
            if isVideo { return "Rendering\u{2026}" }
            return isPrivateSend ? "Sending\u{2026}" : "Sharing\u{2026}"
        }
        return isPrivateSend ? "Send proof" : "Share"
    }

    /// Rasterizes the current PencilKit drawing into an image sized to the
    /// editor canvas (points), preserving the dark-editor ink colors.
    /// Returns nil when nothing has been drawn.
    private func drawingSnapshot() -> UIImage? {
        let drawing = pkCanvas.drawing
        guard !drawing.strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: UIScreen.main.scale)
        }
        return image
    }

    /// The video filter look is a simple tint wash in the editor; the same
    /// tint is burned into the exported clip. `nil` for looks with no tint.
    private func videoTintColor() -> UIColor? {
        switch selectedFilter {
        case .original, .bw: return nil
        case .warm, .cool, .fade, .vivid: return UIColor(selectedFilter.tintOverlay)
        }
    }

    /// Renders the caption + sticker + drawing layer into one transparent
    /// image at the video's pixel size, laid out in the editor's canvas
    /// coordinate space so proportions match exactly what the user saw.
    @MainActor
    private func overlayImage(at videoSize: CGSize) -> UIImage? {
        let base = canvasSize
        guard base.width > 0, base.height > 0, videoSize.width > 0 else { return nil }
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
        renderer.scale = videoSize.width / max(base.width, 1)
        return renderer.uiImage
    }

    /// Resolves the bytes to send for a video. When there are overlays or a
    /// filter tint, it burns them into a fresh clip first. Every clip is
    /// then re-encoded to capped-quality H.264 .mp4 (`VideoTranscoder`)
    /// before it touches the network — a raw 30s `.mov` drops to a few MB.
    /// Falls back to the raw recording if rendering/transcode fails.
    private func resolveVideoData(url: URL) async -> Data? {
        let hasOverlays = !captions.isEmpty || !taskStickers.isEmpty || !pkCanvas.drawing.strokes.isEmpty
        let tint = videoTintColor()

        var sourceURL = url
        if hasOverlays || tint != nil {
            let burned = await VideoOverlayExporter.export(sourceURL: url, tint: tint) { renderSize in
                hasOverlays ? overlayImage(at: renderSize) : nil
            }
            if let burned { sourceURL = burned }
        }

        // Snapchat-style outbound compression: capped-quality H.264 in an
        // .mp4 container, optimized for network streaming.
        if let compressed = await VideoTranscoder.compressForUpload(sourceURL: sourceURL),
           let data = try? Data(contentsOf: compressed) {
            return data
        }
        return try? Data(contentsOf: sourceURL)
    }

    /// For photos we flatten the filtered image + caption + drawing layers
    /// into a single JPEG so the recipient sees what the user composed.
    @MainActor
    private func flattenedPhoto() -> Data? {
        let size = canvasSize == .zero ? CGSize(width: filteredImage.size.width, height: filteredImage.size.height) : canvasSize
        let drawingImg = drawingSnapshot()

        let renderer = ImageRenderer(
            content: ZStack {
                Image(uiImage: filteredImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()

                if let drawingImg {
                    Image(uiImage: drawingImg)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }

                ForEach(captions) { block in
                    CaptionBlockText(block: block)
                        .scaleEffect(block.scale)
                        .rotationEffect(block.rotation)
                        .position(
                            x: block.position.x * size.width,
                            y: block.position.y * size.height
                        )
                }

                ForEach(taskStickers) { block in
                    TaskStickerView(block: block)
                        .scaleEffect(block.scale)
                        .rotationEffect(block.rotation)
                        .position(
                            x: block.position.x * size.width,
                            y: block.position.y * size.height
                        )
                }
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }

    private var joinedCaptionText: String {
        captions
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func post() {
        guard !isPosting else { return }
        isPosting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if showAudiencePanel { closeAudiencePanel() }

        if isDrawing { withAnimation(.easeInOut(duration: 0.2)) { isDrawing = false } }

        let captionToSend = joinedCaptionText

        Task { @MainActor in
            // Resolve the media bytes once; the public story and the
            // private direct shares all consume the same payload. Photos
            // flatten instantly; videos burn overlays in (a beat slower).
            let mediaData: Data?
            let mediaType: MediaType
            let duration: Double?
            switch result {
            case .photo:
                mediaData = (captions.isEmpty && taskStickers.isEmpty && pkCanvas.drawing.strokes.isEmpty)
                    ? filteredImage.jpegData(compressionQuality: 0.85)
                    : flattenedPhoto()
                mediaType = .photo
                duration = nil
            case .video(let url, _, let dur):
                mediaData = await resolveVideoData(url: url)
                mediaType = .video
                duration = dur
            }

            // Live Proofs: send to exactly one real account and skip the
            // local store entirely. Requires real media bytes.
            if let onSendLiveProof {
                guard let mediaData else { isPosting = false; return }
                await onSendLiveProof(
                    mediaData,
                    mediaType == .video,
                    duration,
                    captionToSend.isEmpty ? nil : captionToSend
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    sentToast = "Proof sent to \(liveProofRecipientName ?? "your friend")"
                }
                try? await Task.sleep(for: .milliseconds(950))
                if initialDraftState != nil { CaptureDraftStore.clear() }
                isPosting = false
                onPosted()
                return
            }

            var toast: String? = nil

            switch mode {
            case .circleClip(let circle, let task):
                _ = store.postMedia(
                    imageData: mediaData,
                    type: mediaType,
                    caption: captionToSend,
                    circleId: circle.id,
                    attachedCircleTaskId: task?.id,
                    durationSeconds: duration
                )
            case .generalPost:
                // Any combination: a public story post (when `everyone`
                // is on) and/or one private send covering every selected
                // friend and circle. They share the same composed media.
                if audience.everyone {
                    _ = store.postMedia(
                        imageData: mediaData,
                        type: mediaType,
                        caption: captionToSend,
                        circleId: nil,
                        attachedCircleTaskId: nil,
                        durationSeconds: duration
                    )
                }
                if audience.hasPrivateRecipients {
                    store.sendDirect(
                        imageData: mediaData,
                        type: mediaType,
                        caption: captionToSend,
                        friendIds: Array(audience.friendIds),
                        circleIds: Array(audience.circleIds),
                        durationSeconds: duration
                    )
                    toast = "Proof sent to \(summaryLabel(tokens: privateTokens, empty: "your picks"))"
                }
            }

            if let toast {
                withAnimation(.easeOut(duration: 0.2)) { sentToast = toast }
                try? await Task.sleep(for: .milliseconds(950))
            } else {
                try? await Task.sleep(for: .milliseconds(220))
            }
            // A posted draft is done — clear the stored copy.
            if initialDraftState != nil { CaptureDraftStore.clear() }
            isPosting = false
            onPosted()
        }
    }

    // MARK: - Save to camera roll

    /// The composed photo bytes for the current edit — flattened with
    /// captions / stickers / drawing when present, otherwise the filtered
    /// still on its own. A touch higher quality than the shared copy since
    /// it's the keepsake landing in the user's library.
    @MainActor
    private func composedPhotoData() -> Data? {
        let untouched = captions.isEmpty && taskStickers.isEmpty && pkCanvas.drawing.strokes.isEmpty
        return untouched
            ? filteredImage.jpegData(compressionQuality: 0.9)
            : flattenedPhoto()
    }

    /// Resolves the edited video to a file URL for saving — burns the
    /// overlays / tint into a fresh clip when present, otherwise hands back
    /// the original recording untouched.
    private func resolveVideoURL(url: URL) async -> URL? {
        let hasOverlays = !captions.isEmpty || !taskStickers.isEmpty || !pkCanvas.drawing.strokes.isEmpty
        let tint = videoTintColor()
        guard hasOverlays || tint != nil else { return url }
        let burned = await VideoOverlayExporter.export(sourceURL: url, tint: tint) { renderSize in
            hasOverlays ? overlayImage(at: renderSize) : nil
        }
        return burned ?? url
    }

    /// Saves the composed photo / video to the device camera roll. Surfaces a
    /// calm confirmation toast on success and a gentle Settings prompt when
    /// access is off. Independent of sharing — the editor stays open after.
    private func saveToCameraRoll() {
        guard !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if showAudiencePanel { closeAudiencePanel() }
        if isDrawing { withAnimation(.easeInOut(duration: 0.2)) { isDrawing = false } }

        Task { @MainActor in
            let outcome: PhotoLibrarySaver.SaveOutcome
            switch result {
            case .photo:
                if let data = composedPhotoData() {
                    outcome = await PhotoLibrarySaver.saveImage(data)
                } else {
                    outcome = .failed
                }
            case .video(let url, _, _):
                if let fileURL = await resolveVideoURL(url: url) {
                    outcome = await PhotoLibrarySaver.saveVideo(at: fileURL)
                } else {
                    outcome = .failed
                }
            }

            isSaving = false

            switch outcome {
            case .saved:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await flashToast(isVideo ? "Video saved to your camera roll" : "Saved to your camera roll")
            case .denied:
                showSaveDenied = true
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                await flashToast("Couldn’t save — please try again")
            }
        }
    }

    /// Shows the shared confirmation toast for a beat, then fades it out. The
    /// post flow sets `sentToast` and then dismisses; here we self-clear so
    /// the editor stays put after a save.
    @MainActor
    private func flashToast(_ text: String) async {
        withAnimation(.easeOut(duration: 0.2)) { sentToast = text }
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.easeIn(duration: 0.25)) { sentToast = nil }
    }
}

// MARK: - Draggable caption

/// A single caption painted on the canvas, with all of its live
/// manipulation held in `@GestureState`.
///
/// Why this exists as its own view: the previous implementation rewrote
/// the parent's `captions` array on every drag/pinch/rotate frame, which
/// re-rendered the entire canvas — including the full-resolution
/// background image — on each touch move and made dragging choppy. Here,
/// the in-flight translation / scale / rotation never touch the parent.
/// `@GestureState` resets automatically when the gesture ends, and we
/// commit the final value to the model exactly once via the `onCommit*`
/// closures. Selection and the trash-hover flag only fire on discrete
/// changes, so the parent re-renders a couple of times per gesture
/// rather than every frame.
private struct DraggableCaptionView: View {
    let block: CaptionBlock
    let canvasSize: CGSize
    let isActive: Bool
    let onActivate: () -> Void
    let onTapToEdit: () -> Void
    let onCommitPosition: (CGPoint) -> Void
    let onCommitScale: (CGFloat) -> Void
    let onCommitRotation: (Angle) -> Void
    let onTrashHoverChanged: (Bool) -> Void
    let onDropDelete: () -> Void
    /// Fires `true` the instant a drag begins and `false` when it ends, so
    /// the parent reveals the "drop to delete" zone only while an item is
    /// actually being dragged (not on a tap-to-select).
    let onDragStateChanged: (Bool) -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero

    @State private var isDragging: Bool = false
    @State private var wasOverTrash: Bool = false

    private var pixelPos: CGPoint {
        CGPoint(
            x: block.position.x * canvasSize.width,
            y: block.position.y * canvasSize.height
        )
    }

    var body: some View {
        CaptionBlockText(block: block, isPlaceholder: block.text.isEmpty)
            .scaleEffect(block.scale * gestureScale)
            .rotationEffect(block.rotation + gestureRotation)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .padding(-6)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .onTapGesture { onTapToEdit() }
            .offset(dragTranslation)
            .position(pixelPos)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onActivate()
                    onDragStateChanged(true)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                let predictedY = pixelPos.y + value.translation.height
                let over = predictedY > canvasSize.height - 110
                if over != wasOverTrash {
                    wasOverTrash = over
                    onTrashHoverChanged(over)
                }
            }
            .onEnded { value in
                isDragging = false
                if wasOverTrash {
                    onDropDelete()
                } else {
                    let dx = value.translation.width / max(canvasSize.width, 1)
                    let dy = value.translation.height / max(canvasSize.height, 1)
                    let newPos = CGPoint(
                        x: min(1, max(0, block.position.x + dx)),
                        y: min(1, max(0, block.position.y + dy))
                    )
                    onCommitPosition(newPos)
                }
                if wasOverTrash {
                    wasOverTrash = false
                    onTrashHoverChanged(false)
                }
                onDragStateChanged(false)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onChanged { _ in onActivate() }
            .onEnded { value in
                let next = min(4.0, max(0.5, block.scale * value.magnification))
                onCommitScale(next)
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .updating($gestureRotation) { value, state, _ in
                state = value.rotation
            }
            .onChanged { _ in onActivate() }
            .onEnded { value in
                onCommitRotation(block.rotation + value.rotation)
            }
    }
}

// MARK: - Downscaling

private extension UIImage {
    /// Aspect-preserving downscale capped at `maxPixelDimension` on the
    /// longest side, decoded and drawn off the main thread via the async
    /// thumbnail API. Returns `nil` when the image is already small
    /// enough (caller keeps the original).
    func scaledDown(maxPixelDimension: CGFloat) async -> UIImage? {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > maxPixelDimension, longestSide > 0 else { return nil }
        let factor = maxPixelDimension / longestSide
        let target = CGSize(width: pixelWidth * factor, height: pixelHeight * factor)
        return await byPreparingThumbnail(ofSize: target)
    }
}
