import Foundation

/// What takes space in the Cleanup window: by kind, by year, the largest items, and
/// where the files are. Pure over sized assets.
struct LibraryInsights: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable, Identifiable {
        case photos, livePhotos, videos, screenshots, screenRecordings, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .photos: "Photos"
            case .livePhotos: "Live Photos"
            case .videos: "Videos"
            case .screenshots: "Screenshots"
            case .screenRecordings: "Screen recordings"
            case .other: "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .photos: "photo"
            case .livePhotos: "livephoto"
            case .videos: "video.fill"
            case .screenshots: "camera.viewfinder"
            case .screenRecordings: "record.circle"
            case .other: "doc"
            }
        }

        init(_ asset: any AssetDescriptor) {
            switch asset.mediaKind {
            case .video: self = asset.isScreenRecording ? .screenRecordings : .videos
            case .image: self = asset.isScreenshot ? .screenshots : asset.isLivePhoto ? .livePhotos : .photos
            case .other: self = .other
            }
        }
    }

    struct Slice: Sendable, Equatable, Identifiable {
        var kind: Kind
        var count: Int
        var bytes: Int64
        var hasEstimates = false
        var id: Kind { kind }
    }

    struct Year: Sendable, Equatable, Identifiable {
        var year: Int
        var count: Int
        var bytes: Int64
        var hasEstimates = false
        var id: Int { year }
    }

    struct Item: Sendable, Equatable, Identifiable {
        var id: String
        var kind: Kind
        var date: Date?
        var bytes: Int64
        var isEstimated: Bool
    }

    var count = 0
    var bytes: Int64 = 0
    var hasEstimates = false
    /// Kinds present, largest first.
    var kinds: [Slice] = []
    /// Dated items by capture year, oldest first.
    var years: [Year] = []
    var undatedBytes: Int64 = 0
    var largest: [Item] = []
    var onDeviceBytes: Int64 = 0
    var cloudOnlyBytes: Int64 = 0
    var unknownBytes: Int64 = 0

    static let empty = LibraryInsights()

    static func make(from assets: [ScannedAsset], top: Int = 10, calendar: Calendar = .current) -> LibraryInsights {
        var result = LibraryInsights()
        var kinds: [Kind: Slice] = [:]
        var years: [Int: Year] = [:]
        var items: [Item] = []
        items.reserveCapacity(assets.count)

        for asset in assets {
            let d = asset.descriptor
            let bytes = asset.size.bytes
            let kind = Kind(d)
            result.count += 1
            result.bytes += bytes
            result.hasEstimates = result.hasEstimates || asset.size.isEstimated
            kinds[kind, default: Slice(kind: kind, count: 0, bytes: 0)].count += 1
            kinds[kind]?.bytes += bytes
            if asset.size.isEstimated { kinds[kind]?.hasEstimates = true }
            if let date = d.creationDate {
                let year = calendar.component(.year, from: date)
                years[year, default: Year(year: year, count: 0, bytes: 0)].count += 1
                years[year]?.bytes += bytes
                if asset.size.isEstimated { years[year]?.hasEstimates = true }
            } else {
                result.undatedBytes += bytes
            }
            switch d.availability {
            case .onDevice: result.onDeviceBytes += bytes
            case .cloudOnly: result.cloudOnlyBytes += bytes
            case .unknown: result.unknownBytes += bytes
            }
            items.append(Item(id: d.id, kind: kind, date: d.creationDate, bytes: bytes, isEstimated: asset.size.isEstimated))
        }

        result.kinds = kinds.values.sorted { $0.bytes == $1.bytes ? $0.kind.rawValue < $1.kind.rawValue : $0.bytes > $1.bytes }
        result.years = years.values.sorted { $0.year < $1.year }
        result.largest = Array(items.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }.prefix(top))
        return result
    }
}
