import Foundation
#if canImport(Photos)
import Photos
#endif

/// Backs the "Save to \"Apollo\" Album" setting
/// (`GeneralSettings.saveToApolloAlbum`): when on, saved media (downloaded
/// videos, GIFs, images) goes into a dedicated `PHAssetCollection` named
/// "Apollo" as well as the Camera Roll.
///
/// Every save call site should route through `save(_:as:)` so album
/// membership stays one shared piece of logic.
public enum PhotoAlbumSaver {
    public enum Kind {
        case video(URL)
        case imageData(Data)
        case imageFile(URL)
        /// Original GIF bytes, written with the GIF type so Photos keeps
        /// the animation (matches Reborn's own GIF-save behavior).
        case gifData(Data)
    }

    #if canImport(Photos)
    private static let albumTitle = "Phoebus"

    /// Saves `kind` to the photo library, honoring
    /// `GeneralSettings.saveToApolloAlbum`. If the setting is on, this
    /// looks up (or creates) a `PHAssetCollection` named "Apollo" and
    /// adds the newly-created asset to it. If album lookup/creation or
    /// the add-to-album step fails for any reason, the asset has
    /// already landed in the Camera Roll via the creation request
    /// itself - the media is never silently lost, only the extra
    /// album-membership step is skipped.
    public static func save(_ kind: Kind, useApolloAlbum: Bool) async throws {
        var createdAssetIdentifier: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request: PHAssetChangeRequest?
                switch kind {
                case .video(let fileURL):
                    request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                case .imageFile(let fileURL):
                    request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                case .imageData(let data):
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: data, options: nil)
                    request = nil
                    createdAssetIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
                case .gifData(let data):
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = "com.compuserve.gif"
                    options.originalFilename = "Image.gif"
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: data, options: options)
                    request = nil
                    createdAssetIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
                }
                if let request {
                    createdAssetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? SaveError.creationFailed)
                }
            }
        }

        guard useApolloAlbum, let assetIdentifier = createdAssetIdentifier else { return }
        // Best-effort: the asset is already safely in the Camera Roll
        // by this point, so a failure here (permission edge case, a
        // concurrent album delete, etc.) must never surface as an
        // error to the caller - that would incorrectly imply the save
        // itself failed.
        try? await addAsset(withIdentifier: assetIdentifier, toAlbumNamed: albumTitle)
    }

    private static func addAsset(withIdentifier identifier: String, toAlbumNamed title: String) async throws {
        let collection = try await findOrCreateAlbum(named: title)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
                      let changeRequest = PHAssetCollectionChangeRequest(for: collection) else { return }
                changeRequest.addAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? SaveError.albumUpdateFailed)
                }
            }
        }
    }

    /// Looks up the user's existing "Apollo" album by title, creating it if it
    /// doesn't exist yet.
    private static func findOrCreateAlbum(named title: String) async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let found = existing.firstObject {
            return found
        }

        var createdIdentifier: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                createdIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? SaveError.albumCreationFailed)
                }
            }
        }
        guard let createdIdentifier,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [createdIdentifier], options: nil).firstObject else {
            throw SaveError.albumCreationFailed
        }
        return created
    }

    public enum SaveError: LocalizedError {
        case creationFailed
        case albumCreationFailed
        case albumUpdateFailed

        public var errorDescription: String? {
            switch self {
            case .creationFailed: return "Couldn't save the media."
            case .albumCreationFailed: return "Couldn't create the \"Phoebus\" album."
            case .albumUpdateFailed: return "Couldn't add the media to the \"Phoebus\" album."
            }
        }
    }

    public static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }
    #endif
}
