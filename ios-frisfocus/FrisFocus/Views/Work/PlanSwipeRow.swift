//
//  PlanSwipeRow.swift
//  FrisFocus
//
//  Wraps a Today's Plan card with hidden horizontal swipe shortcuts:
//  swipe right to mark done (green backing), swipe left to take the
//  item off today (muted red backing). The card snaps back if the
//  drag doesn't pass the trigger threshold. Only clearly-horizontal
//  drags engage, so vertical scrolling and the card's own tap /
//  long-press stay intact.
//
//  Once an item is finished, the right-swipe changes meaning: instead
//  of re-completing it, it opens the camera to capture proof (warm sun
//  backing + camera glyph). This is the hidden swipe-to-capture gesture
//  the mechanics tour teaches.
//

import SwiftUI
import UIKit

struct PlanSwipeRow<Content: View>: View {
    /// Swipe-right action — mark the item done.
    let onComplete: () -> Void
    /// Swipe-left action — take the item off today.
    let onRemove: () -> Void
    /// Whether the wrapped item is already finished today. When true, the
    /// right-swipe captures proof instead of re-completing.
    var isCompleted: Bool = false
    /// Right-swipe on a finished item — open the proof camera.
    var onCaptureProof: (() -> Void)? = nil
    @ViewBuilder var content: Content

    @State private var offsetX: CGFloat = 0
    /// Per-drag verdict, decided once from the first clear movement and
    /// then held: `true` follows the finger sideways, `false` leaves the
    /// whole drag to the scroll view. Nil until the drag has shown its
    /// direction.
    @State private var horizontalLock: Bool?

    /// Distance the drag must pass to fire an action.
    private let threshold: CGFloat = 78
    /// Soft cap so the card never slides clean off the row.
    private let maxDrag: CGFloat = 130
    /// How far a drag travels before its direction is judged. Small on
    /// purpose — the verdict has to land before the scroll view's own
    /// pan takes the touch for itself.
    private let decideAfter: CGFloat = 8

    private var progress: CGFloat {
        min(1, abs(offsetX) / threshold)
    }

    var body: some View {
        ZStack {
            swipeBacking
            content
                .offset(x: offsetX)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: offsetX)
        // Simultaneous, not exclusive. This row lives inside the home's
        // vertical ScrollView, and `.gesture(DragGesture(minimumDistance:
        // 22))` never won: the scroll view claims any touch that moves
        // ~10pt in ANY direction, so by the time 22pt had passed the
        // drag was already someone else's and the row sat still — the
        // swipe lesson taught a gesture that did not exist. Running
        // alongside the scroll, the row decides for itself from the
        // first few points whether this drag is sideways, and only then
        // follows it; a vertical drag is judged once and ignored for
        // the rest of its life, so scrolling stays exactly as it was.
        .simultaneousGesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: decideAfter, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if horizontalLock == nil {
                    // A clearly sideways start — a real swipe, not a
                    // scroll that happens to wobble.
                    horizontalLock = abs(dx) > abs(dy) * 1.4
                }
                guard horizontalLock == true else { return }
                offsetX = max(-maxDrag, min(maxDrag, dx))
            }
            .onEnded { value in
                defer { horizontalLock = nil }
                guard horizontalLock == true else { return }
                let dx = value.translation.width
                if dx > threshold {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isCompleted, let onCaptureProof {
                        onCaptureProof()
                    } else {
                        onComplete()
                    }
                } else if dx < -threshold {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRemove()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offsetX = 0
                }
            }
    }

    /// Colored backing revealed under the card as it slides: green from
    /// the leading edge for "done", muted red from the trailing edge for
    /// "take off today". Fades in with the drag and carries an icon.
    @ViewBuilder
    private var swipeBacking: some View {
        let isRight = offsetX >= 0
        // A finished item's right-swipe captures proof — warm sun backing
        // and a camera glyph instead of the green check.
        let captureMode = isRight && isCompleted && onCaptureProof != nil
        let fill: Color = captureMode ? Theme.sunOuter : (isRight ? Theme.alertGreen : Theme.alertRed)
        let glyph = captureMode ? "camera.fill" : (isRight ? "checkmark.circle.fill" : "xmark.circle")
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(fill.opacity(Double(progress) * (isRight ? 0.9 : 0.75)))
            .overlay(alignment: isRight ? .leading : .trailing) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .opacity(Double(progress))
            }
            .opacity(offsetX == 0 ? 0 : 1)
    }
}
