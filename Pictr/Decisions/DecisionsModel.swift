import Foundation
import Observation

/// The decision book on the main actor, persisted to Application Support.
@MainActor
@Observable
final class DecisionsModel {
    private(set) var book: DecisionBook
    /// Something the owner should know: saved decisions set aside, or saving failing.
    var problem: Problem?

    struct Problem: Equatable {
        var title: String
        var message: String
    }

    @ObservationIgnored private let fileURL: URL?
    /// False while a saved book exists but can't be read, such as when Pictr was woken before
    /// the first unlock. Nothing is saved over it until it has been read and folded in.
    @ObservationIgnored private var isLoaded: Bool
    @ObservationIgnored private var saveFailing = false
    @ObservationIgnored private var unsavedReported = false
    private nonisolated static let writeQueue = DispatchQueue(label: "cloud.acker.pictr.decisions", qos: .utility)

    private enum Saved {
        case book(DecisionBook)
        case missing
        case unreadable
        case corrupt
    }

    init(fileURL: URL? = DecisionsModel.defaultURL) {
        self.fileURL = fileURL
        book = DecisionBook()
        isLoaded = false
        switch Self.read(fileURL) {
        case let .book(saved):
            book = saved
            isLoaded = true
        case .missing:
            isLoaded = true
        case .unreadable:
            break
        case .corrupt:
            isLoaded = setAsideCorrupt()
        }
    }

    /// The Ready to Delete count as last saved, for App Intents. Nil when it can't be read.
    nonisolated static func savedQueueCount(at fileURL: URL? = DecisionsModel.defaultURL) -> Int? {
        switch read(fileURL) {
        case let .book(book): book.queue.count
        case .missing: 0
        case .unreadable, .corrupt: nil
        }
    }

    /// Shows a problem unless one is already showing. True if it was shown.
    @discardableResult
    private func report(_ new: Problem) -> Bool {
        guard problem == nil else { return false }
        problem = new
        return true
    }

    /// Moves an undecodable file aside and says so. True once it is out of the way and safe
    /// to save; false leaves it in place and nothing is saved over it.
    private func setAsideCorrupt() -> Bool {
        guard let kept = Self.setAside(fileURL) else { return false }
        report(Problem(title: "Saved decisions couldn't be read",
                       message: "Pictr started fresh and kept the old file as \(kept). Nothing in your library changed."))
        return true
    }

    private nonisolated static func read(_ fileURL: URL?) -> Saved {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else { return .unreadable }
        guard let book = try? JSONDecoder().decode(DecisionBook.self, from: data) else { return .corrupt }
        return .book(book)
    }

    /// Moves an undecodable file out of the way so it is never overwritten. Returns its new name.
    private nonisolated static func setAside(_ fileURL: URL?) -> String? {
        guard let fileURL else { return nil }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.omitted).timeSeparator(.omitted))
        let name = "decisions-unreadable-\(stamp).json"
        let target = fileURL.deletingLastPathComponent().appending(path: name)
        return (try? FileManager.default.moveItem(at: fileURL, to: target)) != nil ? name : nil
    }

    /// Reads a book that couldn't be read at launch and folds it in. True once it is safe to save.
    @discardableResult
    func reloadIfNeeded() -> Bool {
        guard !isLoaded else { return true }
        switch Self.read(fileURL) {
        case let .book(saved):
            book.absorb(saved)
            isLoaded = true
        case .missing:
            isLoaded = true
        case .unreadable:
            break
        case .corrupt:
            isLoaded = setAsideCorrupt()
        }
        return isLoaded
    }

    /// Lets tests wait for queued writes.
    nonisolated static func waitForWrites() {
        writeQueue.sync {}
    }

    /// The book as last saved, for readers outside the main actor (App Intents).
    nonisolated static func savedBook(at fileURL: URL? = DecisionsModel.defaultURL) -> DecisionBook {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let book = try? JSONDecoder().decode(DecisionBook.self, from: data)
        else { return DecisionBook() }
        return book
    }

    nonisolated static var defaultURL: URL? {
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
        // Never write over a saved book that couldn't be read or moved aside yet.
        guard reloadIfNeeded() else {
            if !unsavedReported {
                unsavedReported = report(Problem(
                    title: "Couldn't save decisions",
                    message: "Pictr can't read its saved decisions, so it won't save over them. New decisions last only until Pictr closes."))
            }
            return
        }
        guard let fileURL, let data = try? JSONEncoder().encode(book) else { return }
        // Serial queue keeps writes in order; a detached task per save could reorder.
        Self.writeQueue.async {
            let saved = (try? data.write(to: fileURL, options: .atomic)) != nil
            // The main queue keeps results in write order; separate Tasks might not.
            DispatchQueue.main.async { MainActor.assumeIsolated { self.noteSave(succeeded: saved) } }
        }
    }

    /// Says so once when saving starts failing, not on every swipe.
    private func noteSave(succeeded: Bool) {
        if succeeded {
            saveFailing = false
        } else if !saveFailing {
            saveFailing = report(Problem(title: "Couldn't save decisions",
                                         message: "Pictr will keep trying. If this iPhone is full, free up some space."))
        }
    }
}
