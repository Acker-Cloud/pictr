import Foundation
import Observation

/// The decision book on the main actor, persisted to Application Support.
@MainActor
@Observable
final class DecisionsModel {
    private(set) var book: DecisionBook

    @ObservationIgnored private let fileURL: URL?
    private static let writeQueue = DispatchQueue(label: "cloud.acker.pictr.decisions", qos: .utility)

    init(fileURL: URL? = DecisionsModel.defaultURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let book = try? JSONDecoder().decode(DecisionBook.self, from: data) {
            self.book = book
        } else {
            self.book = DecisionBook()
        }
    }

    static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "decisions.json")
    }

    var queueCount: Int { book.queue.count }

    @discardableResult
    func record(_ decision: Decision, for item: ReviewItem) -> Bool {
        let accepted = book.record(decision, for: item)
        if accepted { save() }
        return accepted
    }

    /// Several decisions with one write, for a compare.
    func record(_ pairs: [(Decision, ReviewItem)]) {
        for (decision, item) in pairs { book.record(decision, for: item) }
        save()
    }

    func restore(_ id: String, to record: DecisionBook.Record?) {
        book.restore(id, to: record)
        save()
    }

    func recordTaste(_ decision: Decision, for id: String) {
        book.recordTaste(decision, for: id)
        save()
    }

    func restoreTaste(_ id: String, to decision: Decision?) {
        book.restoreTaste(id, to: decision)
        save()
    }

    /// Keep from a grid or viewer, where only the ID is at hand.
    func markKept(_ id: String, creationDate: Date? = nil) {
        let item = ReviewItem(id: id, creationDate: creationDate, mediaKind: .image, duration: 0,
                              isFavorite: false, pixelWidth: 0, pixelHeight: 0)
        record(.keep, for: item)
    }

    func queue(ids: [String]) {
        book.queue(ids: ids)
        save()
    }

    func unqueue(_ ids: some Sequence<String>) {
        book.unqueue(ids)
        save()
    }

    func forgetLearning() {
        book.forgetLearning()
        save()
    }

    func startPlan(targetBytes: Int64) {
        book.startPlan(targetBytes: targetBytes)
        save()
    }

    func endPlan() {
        book.endPlan()
        save()
    }

    func finishApply(queued: [String], submitted: Set<String>, bytes: Int64) {
        book.finishApply(queued: queued, submitted: submitted, bytes: bytes)
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(book) else { return }
        // Serial queue keeps writes in order; a detached task per save could reorder.
        Self.writeQueue.async { try? data.write(to: fileURL, options: .atomic) }
    }
}
