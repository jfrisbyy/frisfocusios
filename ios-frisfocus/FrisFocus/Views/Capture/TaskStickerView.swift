//
//  TaskStickerView.swift
//  FrisFocus
//
//  A "task sticker" — a free-floating mini card that paints a Task or
//  To-do over a captured photo / video, mirroring the home-screen card
//  (checkbox + title, no point value). Used in two places:
//
//   - The capture editor's live canvas, where it can be dragged,
//     pinched, rotated, and trashed (via `DraggableStickerView`).
//   - The flattened-image renderer (`ImageRenderer`) so the exported
//     JPEG matches exactly what the author placed.
//
//  Attaching a sticker is a purely visual tag — it never completes or
//  mutates the underlying Task/To-do. The checked state is a snapshot
//  captured at the moment the sticker is created.
//

import SwiftUI
import UIKit

// MARK: - Model

/// A free-floating task/to-do card painted over the canvas. Stores a
/// self-contained snapshot (title + checked state + kind) so the
/// gesture-heavy canvas never has to read back into the Store while a
/// drag is in flight — the same performance discipline the caption
/// blocks follow.
struct TaskStickerBlock: Identifiable, Equatable {
    let id: UUID
    var title: String
    /// Whether the item reads as done (green check + strikethrough).
    var isChecked: Bool
    /// `true` for a repeatable Task (circular checkbox); `false` for a
    /// one-time To-do (square checkbox).
    var isTask: Bool
    /// Must-Do tasks render a red accent on the empty checkbox, matching
    /// the home card. Always `false` for to-dos.
    var isMust: Bool
    /// Source ids kept for potential future tagging; the sticker itself
    /// is baked into the shared media, so these are not required for
    /// rendering.
    var sourceTaskId: UUID?
    var sourceTodoId: UUID?

    /// Normalized position (0…1) in the canvas. (0.5, 0.5) is dead
    /// center; normalized coords keep the sticker stable across canvas
    /// resizes (e.g. keyboard transitions).
    var position: CGPoint
    var scale: CGFloat
    var rotation: Angle

    init(
        id: UUID = UUID(),
        title: String,
        isChecked: Bool,
        isTask: Bool,
        isMust: Bool = false,
        sourceTaskId: UUID? = nil,
        sourceTodoId: UUID? = nil,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1.0,
        rotation: Angle = .zero
    ) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
        self.isTask = isTask
        self.isMust = isMust
        self.sourceTaskId = sourceTaskId
        self.sourceTodoId = sourceTodoId
        self.position = position
        self.scale = scale
        self.rotation = rotation
    }
}

extension TaskStickerBlock {
    /// Build a sticker from a repeatable Task. `isChecked` is resolved by
    /// the caller from the Store (today's log) so this stays Store-free.
    init(task: FFTask, isChecked: Bool, at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.init(
            title: task.title,
            isChecked: isChecked,
            isTask: true,
            isMust: false,
            sourceTaskId: task.id,
            position: position
        )
    }

    /// Build a sticker from a one-time To-do. The done state comes
    /// straight off the model.
    init(todo: Todo, at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.init(
            title: todo.title,
            isChecked: todo.isCompleted,
            isTask: false,
            isMust: false,
            sourceTodoId: todo.id,
            position: position
        )
    }
}

// MARK: - Renderer

/// Paints a single task sticker as a mini white card. Mirrors the home
/// card's checkbox + title treatment (no point value).
struct TaskStickerView: View {
    let block: TaskStickerBlock

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            checkbox

            Text(block.title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(block.isChecked ? 0.5 : 1.0))
                .strikethrough(block.isChecked, color: Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Geometry-based fill + shadow instead of a content `.shadow` on a
        // `.clipShape`d card. A shape shadow skips the per-composite
        // offscreen alpha pass that a content shadow + clip force, so the
        // card tracks the finger smoothly while dragging over the
        // full-resolution background.
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .fixedSize()
    }

    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            if block.isTask {
                taskBox
            } else {
                todoBox
            }

            if block.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.warmWheat)
            } else if block.isTask && block.isMust {
                Circle()
                    .fill(Theme.alertRed.opacity(0.18))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
    }

    @ViewBuilder
    private var taskBox: some View {
        if block.isChecked {
            Circle()
                .fill(Theme.alertGreen)
                .frame(width: 22, height: 22)
        } else {
            Circle()
                .stroke(block.isMust ? Theme.alertRed : Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var todoBox: some View {
        if block.isChecked {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.alertGreen)
                .frame(width: 22, height: 22)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }
}

// MARK: - Draggable wrapper

/// A task sticker on the canvas with all live manipulation held in
/// `@GestureState`, so an in-flight drag / pinch / rotate never rewrites
/// the parent's model (and never re-renders the full-resolution
/// background). The final value commits exactly once on gesture end —
/// the same approach `DraggableCaptionView` uses to keep dragging smooth.
struct DraggableStickerView: View {
    let block: TaskStickerBlock
    let canvasSize: CGSize
    let isActive: Bool
    let onActivate: () -> Void
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
        TaskStickerView(block: block)
            .scaleEffect(block.scale * gestureScale)
            .rotationEffect(block.rotation + gestureRotation)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius + 2, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .padding(-5)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .onTapGesture { onActivate() }
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
                let next = min(3.0, max(0.5, block.scale * value.magnification))
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
