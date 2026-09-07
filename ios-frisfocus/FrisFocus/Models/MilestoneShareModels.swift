//
//  MilestoneShareModels.swift
//  FrisFocus
//
//  Data for sharing a milestone — the season's biggest moments. The
//  milestone share camera renders a live overlay (flag mark, serif
//  title, progress / LANDED stamp, points, season name, timeline, and
//  a strip of journey photos) entirely from these values. Everything
//  is computed locally; no API calls anywhere in the flow.
//

import Foundation
import UIKit

/// One journey photo pre-loaded as a small thumbnail for the overlay
/// strip. Equality compares ids only — the pixels never change for a
/// given attachment.
struct MilestoneJourneyThumb: Identifiable, Equatable {
    let id: UUID
    let image: UIImage

    static func == (lhs: MilestoneJourneyThumb, rhs: MilestoneJourneyThumb) -> Bool {
        lhs.id == rhs.id
    }
}

/// Everything the milestone overlay needs, frozen at the moment the
/// camera opens. Mid-journey shares show current progress; landed
/// ones get the checkered flag and the LANDED stamp.
struct ShareMilestoneContext: Equatable {
    var title: String
    var isLanded: Bool
    var stepsDone: Int
    var stepsTotal: Int
    var pointValue: Int
    var seasonName: String
    var weekNumber: Int
    var completedDate: Date?
    var journeyThumbs: [MilestoneJourneyThumb]

    /// "WEEK 2 → LANDED JUN 11" once complete; "AIMED AT WEEK 2" on
    /// the road.
    var timelineText: String {
        if isLanded, let completedDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "WEEK \(weekNumber) → LANDED \(formatter.string(from: completedDate).uppercased())"
        }
        return "AIMED AT WEEK \(weekNumber)"
    }

    /// "3 OF 5 STEPS" mid-journey (or "IN MOTION" without steps);
    /// the landed state renders the stamp instead.
    var progressText: String {
        guard !isLanded else { return "LANDED" }
        if stepsTotal > 0 { return "\(stepsDone) OF \(stepsTotal) STEPS" }
        return "IN MOTION"
    }
}

/// The user's disclosure choices for the milestone card. The title and
/// flag mark have no toggle — they are the card. Persisted so choices
/// stick between shares.
struct MilestoneShareOptions: Equatable, Codable {
    var showProgress: Bool = true
    var showPoints: Bool = true
    var showSeasonName: Bool = true
    var showTimeline: Bool = true
    var showJourneyStrip: Bool = true

    private static let defaultsKey = "share.milestone.options"

    /// The last-used options, or the defaults on first share.
    static func load() -> MilestoneShareOptions {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let saved = try? JSONDecoder().decode(MilestoneShareOptions.self, from: data)
        else {
            return MilestoneShareOptions()
        }
        return saved
    }

    /// Remember the current choices for next time.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - Context builder

extension Store {
    /// Freezes a milestone into its share context, pre-loading up to
    /// five journey photos as small thumbnails for the overlay strip.
    func milestoneShareContext(for milestone: Milestone, journeyThumbs: [MilestoneJourneyThumb]? = nil) -> ShareMilestoneContext {
        let thumbs: [MilestoneJourneyThumb] = journeyThumbs ?? milestone.photoAttachments
            .suffix(5)
            .compactMap { attachment in
                guard let image = MilestoneMediaStore.image(for: attachment) else { return nil }
                return MilestoneJourneyThumb(
                    id: attachment.id,
                    image: Self.shareThumb(image, maxDimension: 280)
                )
            }
        return ShareMilestoneContext(
            title: milestone.title.isEmpty ? "Untitled milestone" : milestone.title,
            isLanded: milestone.isCompleted,
            stepsDone: milestone.steps.filter(\.isCompleted).count,
            stepsTotal: milestone.steps.count,
            pointValue: milestone.pointValue,
            seasonName: currentSeason.name,
            weekNumber: milestone.weekNumber,
            completedDate: milestone.completedDate,
            journeyThumbs: thumbs
        )
    }

    /// Downscales a journey photo to a small square-ish thumb so the
    /// overlay renders fast on the live viewfinder and in the export.
    private static func shareThumb(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
