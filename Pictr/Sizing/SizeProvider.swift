import Foundation
import UniformTypeIdentifiers

struct AssetSize: Sendable, Equatable {
    var bytes: Int64
    var isEstimated: Bool
}

protocol SizeProvider: Sendable {
    func size(of asset: some AssetDescriptor) -> AssetSize?
}

/// Exact size: sum of every resource's reported byte count. Nil if any is missing.
struct ResourceSizeProvider: SizeProvider {
    func size(of asset: some AssetDescriptor) -> AssetSize? {
        guard !asset.resources.isEmpty else { return nil }
        var total: Int64 = 0
        for resource in asset.resources {
            guard let bytes = resource.byteCount, bytes >= 0 else { return nil }
            total += bytes
        }
        return AssetSize(bytes: total, isEstimated: false)
    }
}

/// Estimate from pixel dimensions and type (photos) or duration and bitrate (video).
struct EstimatedSizeProvider: SizeProvider {
    /// Nominal bitrate for iPhone video (roughly 1080p30 HEVC to 4K30 HEVC midpoint).
    static let videoBytesPerSecond: Double = 3_500_000
    /// Typical Live Photo paired video length.
    static let livePhotoVideoSeconds: Double = 3

    func size(of asset: some AssetDescriptor) -> AssetSize? {
        let bytes: Double
        switch asset.mediaKind {
        case .video:
            bytes = max(asset.duration, 0) * Self.videoBytesPerSecond
        case .image:
            let pixels = Double(max(asset.pixelWidth, 0)) * Double(max(asset.pixelHeight, 0))
            var photo = pixels * Self.bytesPerPixel(for: asset.uniformTypeIdentifier)
            if asset.isLivePhoto {
                photo += Self.livePhotoVideoSeconds * Self.videoBytesPerSecond
            }
            bytes = photo
        case .other:
            return nil
        }
        return AssetSize(bytes: Int64(bytes.rounded()), isEstimated: true)
    }

    static func bytesPerPixel(for identifier: String?) -> Double {
        guard let identifier, let type = UTType(identifier) else { return 0.5 }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return 0.25 }
        if type.conforms(to: .png) { return 1.5 }
        if type.conforms(to: .rawImage) { return 2.0 }
        if type.conforms(to: .jpeg) { return 0.5 }
        return 0.5
    }
}

/// Tries `primary`, falls back to `fallback`.
struct FallbackSizeProvider<Primary: SizeProvider, Fallback: SizeProvider>: SizeProvider {
    var primary: Primary
    var fallback: Fallback

    func size(of asset: some AssetDescriptor) -> AssetSize? {
        primary.size(of: asset) ?? fallback.size(of: asset)
    }
}

extension SizeProvider where Self == FallbackSizeProvider<ResourceSizeProvider, EstimatedSizeProvider> {
    static var standard: Self {
        FallbackSizeProvider(primary: ResourceSizeProvider(), fallback: EstimatedSizeProvider())
    }
}
