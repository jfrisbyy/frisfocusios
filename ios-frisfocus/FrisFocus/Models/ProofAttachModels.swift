//
//  ProofAttachModels.swift
//  FrisFocus
//
//  Proofs become attachable: a composed clean card (overlay, captions,
//  stickers baked in) can land on a milestone's journey timeline or in
//  a note's media — outliving the 24h story. These types carry the
//  composed media and the attach destination through the share pipeline.
//

import Foundation

/// Everything the minimal journal-capture overlay needs — the date and
/// a small season wordmark. Deliberately quiet; the capture is the point.
struct ShareNoteContext: Equatable {
    var date: Date
    var seasonName: String

    /// "THURSDAY · JUN 11" — the journal's date language, uppercased.
    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMM d"
        return formatter.string(from: date).uppercased()
    }
}

/// Where a capture session can attach its composed card afterwards.
enum ProofAttachContext: Equatable {
    /// A free-standing share — the picker offers milestones and notes.
    case none
    /// Opened from a milestone — that journey is offered first and
    /// "Just save" lands straight on it.
    case milestone(UUID)
    /// Opened from the note composer — saved media returns to the
    /// composer through a callback instead of mutating the Store.
    case noteComposer
}

/// The composed CLEAN card (no attribution — it stays in the app),
/// ready to write into a journey or a note.
enum ComposedProofMedia {
    case photo(Data)
    case video(Data, duration: Double)
}

/// A picked attach destination from the proof save picker.
enum ProofAttachTarget: Equatable, Hashable {
    case milestone(UUID)
    case note(UUID)
    /// Pin to a repeatable Task for today — surfaces beside that task's
    /// entry in the stats day breakdown.
    case task(UUID)
    /// Pin to a one-time To-do for today.
    case todo(UUID)
    /// Save the composed card straight to the device photo library.
    case cameraRoll
}
