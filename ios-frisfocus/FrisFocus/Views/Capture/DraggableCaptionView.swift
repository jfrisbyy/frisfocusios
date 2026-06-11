//
//  DraggableCaptionView.swift
//  FrisFocus
//
//  A single caption painted on an edit canvas, with all of its live
//  manipulation held in `@GestureState`.
//
//  Why this exists as its own view: rewriting the parent's `captions`
//  array on every drag/pinch/rotate frame re-renders the entire canvas
//  — including the full-resolution background image — on each touch
//  move and makes dragging choppy. Here, the in-flight translation /
//  scale / rotation never touch the parent. `@GestureState` resets
//  automatically when the gesture ends, and we commit the final value
//  to the model exactly once via the `onCommit*` closures.
//
//  The drag gesture reads in the GLOBAL coordinate space. The view is
//  scaled and rotated beneath the gesture, so a local-space translation
//  would be measured in the transformed space — divided by the scale
//  and rotated with the block — while `.offset` moves in parent space.
//  Global space keeps the item exactly under the finger regardless of
//  how it has been pinched or tilted.
//
//  Shared by the proof editor and the overlay-post preview.
//

import SwiftUI
import UIKit

struct DraggableCaptionView: View {
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
        // Global space: translations match the finger on screen even
        // when the block is scaled or rotated (see header comment).
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
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
