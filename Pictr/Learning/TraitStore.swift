import Foundation
import Vision

/// What learning knows about each decided or analysed photo: classifier tags and
/// the feature print. Persisted, because deleted photos can't be re-read later.
/// Contains no images and never leaves this iPhone.
struct TraitStore: Codable, Sendable {
    var tags: [String: SubjectTags] = [:]
    var prints: [String: FeaturePrintObservation] = [:]

    static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "taste-traits.json")
    }

    /// Nil when a saved store exists but can't be read yet, such as before the first unlock
    /// after a restart. Starting empty then would let the next save overwrite it.
    static func load(from url: URL?) -> TraitStore? {
        guard let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return TraitStore() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(TraitStore.self, from: data)) ?? TraitStore()
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        // Readable once the iPhone has been unlocked since it started, so a Shortcut or
        // Siri request that wakes Pictr on a locked phone still finds it.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Adds saved entries this store doesn't have yet; its own entries win.
    mutating func merge(_ saved: TraitStore) {
        tags.merge(saved.tags) { mine, _ in mine }
        prints.merge(saved.prints) { mine, _ in mine }
    }

    /// Drops photos that are neither decided nor in the current window.
    mutating func prune(keeping ids: Set<String>) {
        tags = tags.filter { ids.contains($0.key) }
        prints = prints.filter { ids.contains($0.key) }
    }
}
