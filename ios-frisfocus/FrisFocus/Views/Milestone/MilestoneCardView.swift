//
//  MilestoneCardView.swift
//  FrisFocus
//
//  One milestone as a pinned card on the paper — serif title, a quiet
//  week/points eyebrow, a slim warm-gold progress bar that fills as
//  steps complete, and small photo thumbnails peeking out of the card
//  when the journey has been documented.
//
//  Completed milestones read quietly with their completion date; the
//  next one in motion gets a warm glow and slightly more presence.
//  Shared by the homepage zone and the season-options board.
//

import SwiftUI

struct MilestoneCardView: View {
    let milestone: Milestone
    /// The next not-yet-completed milestone gets the warm emphasis.
    var isNext: Bool = false

    private static let completedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(eyebrowText)
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(eyebrowColor)

                Spacer(minLength: 0)

                Text("\(milestone.pointValue)")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(
                        milestone.isCompleted
                            ? Theme.alertGreen
                            : Theme.textPrimary.opacity(isNext ? 0.9 : 0.7)
                    )
                + Text(" pts")
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }

            Text(milestone.title.isEmpty ? "Untitled milestone" : milestone.title)
                .font(.serif(isNext ? 19 : 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(milestone.isCompleted ? 0.55 : 1))
                .strikethrough(milestone.isCompleted, color: Theme.textPrimary.opacity(0.35))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            progressRow

            if !milestone.photoAttachments.isEmpty {
                thumbnailStrip
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isNext ? Theme.sunWarm.opacity(0.6) : Theme.textPrimary.opacity(0.08),
                    lineWidth: isNext ? 1 : 0.5
                )
        )
        .shadow(
            color: isNext ? Theme.sunWarm.opacity(0.28) : Theme.textPrimary.opacity(0.05),
            radius: isNext ? 10 : 4,
            y: 2
        )
        .scaleEffect(isNext ? 1.0 : 0.985, anchor: .leading)
    }

    // MARK: - Pieces

    private var cardFill: Color {
        if milestone.isCompleted { return Color.white.opacity(0.45) }
        return Color.white.opacity(isNext ? 0.85 : 0.65)
    }

    private var eyebrowText: String {
        if let completed = milestone.completedDate {
            return "DONE · \(Self.completedFormatter.string(from: completed).uppercased())"
        }
        var parts: [String] = []
        if let target = milestone.targetDate {
            parts.append("BY \(Self.completedFormatter.string(from: target).uppercased())")
        }
        if isNext {
            parts.append("IN MOTION")
        } else if parts.isEmpty {
            parts.append("UPCOMING")
        }
        return parts.joined(separator: " · ")
    }

    private var eyebrowColor: Color {
        if milestone.isCompleted { return Theme.alertGreen.opacity(0.8) }
        return isNext ? Theme.sunShadow : Theme.textPrimary.opacity(0.5)
    }

    private var progressRow: some View {
        let done = milestone.steps.filter(\.isCompleted).count
        let total = milestone.steps.count

        return HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(milestone.isCompleted ? Theme.alertGreen.opacity(0.7) : Theme.sunOuter)
                        .frame(width: max(0, proxy.size.width * milestone.stepProgress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: milestone.stepProgress)
                }
            }
            .frame(height: 4)

            if total > 0 {
                Text("\(done)/\(total)")
                    .font(.sans(10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .monospacedDigit()
            }
        }
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 6) {
            ForEach(milestone.photoAttachments.suffix(4)) { attachment in
                MilestoneThumbView(attachment: attachment, size: 34)
            }
            if milestone.photoAttachments.count > 4 {
                Text("+\(milestone.photoAttachments.count - 4)")
                    .font(.sans(10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// A small rounded thumbnail for a journey attachment — photos load
/// directly, videos show a poster frame with a play badge, and proof
/// attachments carry the thin signature-color edge. Quiet placeholder
/// while the file is still downloading from sync.
struct MilestoneThumbView: View {
    let attachment: MilestoneAttachment
    var size: CGFloat = 34

    @State private var videoPoster: UIImage? = nil

    private var displayImage: UIImage? {
        attachment.kind == .video ? videoPoster : MilestoneMediaStore.image(for: attachment)
    }

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(width: size, height: size)
            .overlay {
                if let image = displayImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: attachment.kind == .video ? "video" : "photo")
                        .font(.system(size: size * 0.32, weight: .light))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        attachment.isProof ? Theme.sunWarm.opacity(0.85) : Theme.textPrimary.opacity(0.08),
                        lineWidth: attachment.isProof ? 1.2 : 0.5
                    )
            )
            .overlay {
                if attachment.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: size * 0.26, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .allowsHitTesting(false)
                }
            }
            .task(id: attachment.filename) {
                guard attachment.kind == .video, let url = attachment.url else { return }
                videoPoster = await VideoThumbnailService.thumbnail(for: url, maxDimension: max(160, size * 3))
            }
    }
}
