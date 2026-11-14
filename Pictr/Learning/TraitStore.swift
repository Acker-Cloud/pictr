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

    static func load(from url: URL?) -> TraitStore {
        guard let url, let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(TraitStore.self, from: data)
        else { return TraitStore() }
        return store
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Drops photos that are neither decided nor in the current window.
    mutating func prune(keeping ids: Set<String>) {
        tags = tags.filter { ids.contains($0.key) }
        prints = prints.filter { ids.contains($0.key) }
    }
}
