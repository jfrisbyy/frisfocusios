//
//  ShareCardSubject.swift
//  FrisFocus
//
//  The share camera and preview work on one of two card subjects: a
//  day (or week) with its sun-state mark, or a milestone with its flag
//  mark. `ShareCardSubject` is what an entry point hands the camera;
//  `ShareCardComposition` pairs the subject with the user's frozen
//  disclosure choices for the preview and the renderer.
//

import Foundation

/// What the share camera is composing over.
enum ShareCardSubject: Equatable {
    case day(ShareDayContext)
    case milestone(ShareMilestoneContext)
    /// A capture headed for the journal — minimal overlay (date plus a
    /// small season wordmark), no disclosure layers.
    case note(ShareNoteContext)
}

/// A subject plus its overlay options — everything the preview and the
/// renderer need to draw the exact card the viewfinder showed.
enum ShareCardComposition: Equatable {
    case day(ShareDayContext, ShareOverlayOptions)
    case milestone(ShareMilestoneContext, MilestoneShareOptions)
    case note(ShareNoteContext)
}
