import CoreGraphics
import Foundation

enum AuthState: Sendable, Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
}

enum LibraryDelta: Sendable {
    /// Assets removed from, and inserted into or changed within, the fetch window.
    case incremental(removed: Set<String>, upserted: [any AssetDescriptor])
    /// PhotoKit could not describe the change incrementally; rescan.
    case reload
}

enum DeleteOutcome: Sendable, Equatable {
    /// The IDs that resolved and were submitted in the confirmed batch.
    case deleted(Set<String>)
    case cancelled
}

/// The only seam between app code and PhotoKit.
protocol PhotoLibraryClient: Sendable {
    func authorizationState() -> AuthState
    func requestAuthorization() async -> AuthState

    /// Synchronously enumerates assets created on or after `since`, newest first.
    /// Call off the main actor. Starts change observation for that window.
    func enumerateAssets(since: Date, _ body: (any AssetDescriptor, _ index: Int, _ total: Int) -> Void)

    /// Changes to the window from the most recent `enumerateAssets` call.
    var changes: AsyncStream<LibraryDelta> { get }

    /// Creation date of the oldest asset in the library. Call off the main actor.
    func earliestAssetDate() -> Date?

    /// Photos and videos created inside any of `windows`, oldest first. Call off the main actor.
    func reviewItems(in windows: [DateInterval]) -> [ReviewItem]

    /// Review items for specific assets, in the given order. Call off the main actor.
    func reviewItems(ids: [String]) -> [ReviewItem]

    /// Count and cover per calendar month across the whole library. Call off the main actor.
    func assetIndex() -> [AssetStamp]

    /// Sized members for the given IDs (unresolvable IDs are skipped). Call off the main actor.
    func members(for ids: [String]) -> [BucketMember]

    /// A small local image for analysis. Never downloads from iCloud; nil when the
    /// photo is not on this iPhone. Call off the main actor.
    func analysisImage(for id: String, maxPixels: Int) -> CGImage?

    /// Marks or unmarks a favorite in the user's library. No system prompt.
    func setFavorite(_ isFavorite: Bool, id: String) async throws

    /// One system-confirmed delete batch. A user cancel returns `.cancelled`.
    func delete(ids: [String]) async throws -> DeleteOutcome

    /// Writes the original file (the edited version when there is one) to a temporary
    /// file for sharing. The user asked for it, so this may fetch from iCloud.
    func exportOriginal(id: String) async throws -> URL
}
