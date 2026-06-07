//
//  PhotoLibrarySaver.swift
//  FrisFocus
//
//  Saves a composed moment from the capture editor into the device camera
//  roll using add-only photo-library authorization. Both the still and the
//  burned-in video path land here.
//
//  Every entry point is `nonisolated` so the PhotoKit work (authorization
//  prompt + the change request, both of which call back on a private queue)
//  stays off the main actor. Callers `await` the result on the main actor and
//  drive the editor's UI from there.
//

import Photos
import UIKit

enum PhotoLibrarySaver {
    /// The outcome of a save attempt. `denied` is distinct from `failed` so
    /// the editor can offer a Settings prompt only when access is the issue.
    enum SaveOutcome: Equatable {
        case saved
        case denied
        case failed
    }

    /// Saves a flattened photo (JPEG bytes) to the camera roll.
    nonisolated static func saveImage(_ data: Data) async -> SaveOutcome {
        guard await ensureAuthorized() else { return .denied }
        return await performChanges {
            PHAssetCreationRequest.forAsset()
                .addResource(with: .photo, data: data, options: nil)
        }
    }

    /// Saves a video file (the edited clip on disk) to the camera roll. The
    /// source file is copied, never moved, so an in-flight share can still
    /// read the original recording.
    nonisolated static func saveVideo(at fileURL: URL) async -> SaveOutcome {
        guard await ensureAuthorized() else { return .denied }
        return await performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            PHAssetCreationRequest.forAsset()
                .addResource(with: .video, fileURL: fileURL, options: options)
        }
    }

    // MARK: - Authorization

    /// Resolves add-only authorization, requesting it once when undetermined.
    nonisolated private static func ensureAuthorized() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let updated = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return updated == .authorized || updated == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Change request

    /// Wraps `performChanges` in an async call, mapping success/failure to a
    /// `SaveOutcome`. The change block runs on PhotoKit's private queue.
    nonisolated private static func performChanges(_ changes: @escaping () -> Void) async -> SaveOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<SaveOutcome, Never>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, _ in
                continuation.resume(returning: success ? .saved : .failed)
            }
        }
    }
}
