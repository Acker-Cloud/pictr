import Foundation

enum AssetMediaKind: Sendable, Equatable {
    case image
    case video
    case other
}

/// One file backing an asset (photo, paired video, full-size edit, ...).
struct ResourceRecord: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case photo
        case video
        case pairedVideo
        case fullSizePhoto
        case fullSizeVideo
        case other
    }

    var kind: Kind
    var uniformTypeIdentifier: String?
    /// Exact on-disk size if PhotoKit exposed it; nil when unreadable.
    var byteCount: Int64?
    /// Whether the file is on this iPhone; nil when PhotoKit did not say.
    var isLocallyAvailable: Bool?
}

/// Plain-value view of an asset. PhotoKit adapts PHAsset to this; tests use fakes.
protocol AssetDescriptor: Sendable {
    var id: String { get }
    var creationDate: Date? { get }
    var mediaKind: AssetMediaKind { get }
    var isScreenshot: Bool { get }
    var isScreenRecording: Bool { get }
    var isLivePhoto: Bool { get }
    var isFavorite: Bool { get }
    var isHidden: Bool { get }
    var burstIdentifier: String? { get }
    /// True when the frame was picked by the user or automatically by the camera.
    var isBurstPick: Bool { get }
    /// The burst's cover frame in Photos.
    var representsBurst: Bool { get }
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    var duration: TimeInterval { get }
    var uniformTypeIdentifier: String? { get }
    var resources: [ResourceRecord] { get }
}

enum Availability: Sendable, Equatable {
    case onDevice
    case cloudOnly
    case unknown
}

extension AssetDescriptor {
    /// Availability of the primary photo or video file.
    var availability: Availability {
        let primary = resources.filter { $0.kind == .photo || $0.kind == .video }
        guard !primary.isEmpty else { return .unknown }
        if primary.contains(where: { $0.isLocallyAvailable == false }) { return .cloudOnly }
        if primary.allSatisfy({ $0.isLocallyAvailable == true }) { return .onDevice }
        return .unknown
    }
}

/// An asset paired with its computed size.
struct ScannedAsset: Sendable {
    var descriptor: any AssetDescriptor
    var size: AssetSize
}
