import Foundation

/// Last known photo dates, so Lookback opens instantly and refreshes behind.
struct AssetIndexCache: Sendable {
    let fileURL: URL?

    init(fileURL: URL? = AssetIndexCache.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "asset-index.json")
    }

    func load() -> [AssetStamp]? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([AssetStamp].self, from: data)
    }

    func save(_ index: [AssetStamp]) {
        guard let fileURL, let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
