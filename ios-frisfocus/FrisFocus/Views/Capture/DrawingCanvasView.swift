//
//  DrawingCanvasView.swift
//  FrisFocus
//
//  A PencilKit drawing surface laid over the capture editor's canvas.
//  Wraps `PKCanvasView` so the user can scribble freehand on a photo or
//  video with Apple's built-in tools (pen / eraser / colors / width).
//
//   - `isActive` engages draw mode: the canvas accepts touches and the
//     system tool picker floats at the bottom. When inactive the strokes
//     stay visible but the canvas ignores input so captions and task
//     stickers remain interactive underneath.
//   - `.anyInput` drawing policy is essential — it lets a finger draw on
//     devices (and the cloud preview) that have no Apple Pencil.
//
//  The strokes are read back by the editor at share time via
//  `PKDrawing.image(from:scale:)` and baked into the exported photo /
//  burned into the shared video.
//

import PencilKit
import SwiftUI

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    /// Whether draw mode is engaged.
    let isActive: Bool
    let toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.tool = PKInkingTool(.pen, color: .white, width: 8)
        toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.isUserInteractionEnabled = isActive
        toolPicker.setVisible(isActive, forFirstResponder: uiView)
        if isActive {
            // Becoming first responder reveals the floating tool picker.
            DispatchQueue.main.async {
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}
