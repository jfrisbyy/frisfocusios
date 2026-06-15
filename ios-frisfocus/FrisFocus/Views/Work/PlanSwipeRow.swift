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

import SwiftUI
import UIKit

struct PlanSwipeRow<Content: View>: View {
    /// Swipe-right action — mark the item done.
    let onComplete: () -> Void
    /// Swipe-left action — take the item off today.
    let onRemove: () -> Void
    @ViewBuilder var content: Content

    @State private var offsetX: CGFloat = 0

    /// Distance the drag must pass to fire an action.
    private let threshold: CGFloat = 78
    /// Soft cap so the card never slides clean off the row.
    private let maxDrag: CGFloat = 130

    private var progress: CGFloat {
        min(1, abs(offsetX) / threshold)
    }

    var body: some View {
        ZStack {
            swipeBacking
            content
                .offset(x: offsetX)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: offsetX)
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 22)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Only follow clearly-horizontal drags so the vertical
                // scroll and the card's tap/long-press are left alone.
                guard abs(dx) > abs(dy) else { return }
                offsetX = max(-maxDrag, min(maxDrag, dx))
            }
            .onEnded { value in
                let dx = value.translation.width
                if dx > threshold {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onComplete()
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
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(
                (isRight ? Theme.alertGreen : Theme.alertRed)
                    .opacity(Double(progress) * (isRight ? 0.9 : 0.75))
            )
            .overlay(alignment: isRight ? .leading : .trailing) {
                Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .opacity(Double(progress))
            }
            .opacity(offsetX == 0 ? 0 : 1)
    }
}
