import Foundation
import FoundationModels
import Observation

/// Optional plain-English summary of what Pictr has learned, written by Apple's
/// on-device language model. Off by default. Uses `SystemLanguageModel.default`
/// only, never Private Cloud Compute, so nothing leaves the iPhone.
@MainActor
@Observable
final class AppleIntelligence {
    private static let enabledKey = "appleIntelligence.enabled"

    enum Status: Equatable {
        case available
        case notEligible
        case notEnabled
        case notReady
        case unavailable
    }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { summary = nil }
        }
    }
    private(set) var summary: String?
    private(set) var isGenerating = false
    private(set) var failure: String?
    @ObservationIgnored private var summarized: TasteSummary?

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible: .notEligible
            case .appleIntelligenceNotEnabled: .notEnabled
            case .modelNotReady: .notReady
            @unknown default: .unavailable
            }
        }
    }

    var statusText: String {
        switch status {
        case .available: "Available on this iPhone."
        case .notEligible: "This iPhone doesn't support Apple Intelligence."
        case .notEnabled: "Turn on Apple Intelligence in the Settings app to use this."
        case .notReady: "Apple Intelligence is still downloading. Try again later."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    var canSummarize: Bool { isEnabled && status == .available }

    func summarize(_ facts: TasteSummary) async {
        guard canSummarize, !facts.deletes.isEmpty || !facts.keeps.isEmpty else {
            summary = nil
            return
        }
        guard facts != summarized || summary == nil, !isGenerating else { return }
        isGenerating = true
        failure = nil
        defer { isGenerating = false }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
        do {
            summary = try await session.respond(to: Self.prompt(facts)).content
            summarized = facts
        } catch {
            failure = "Couldn't write a summary: \(error.localizedDescription)"
        }
    }

    nonisolated static let instructions = """
        You write for a photo cleanup app. In two short sentences, tell the person \
        which kinds of photos they tend to delete and which they tend to keep. \
        Use only the facts given. Plain words, second person, no praise, no emoji, \
        no dashes, no lists. Do not invent subjects or numbers.
        """

    nonisolated static func prompt(_ facts: TasteSummary) -> String {
        func line(_ subjects: [TasteSummary.Subject]) -> String {
            subjects.isEmpty ? "none yet"
                : subjects.map { "\($0.name) (\($0.deletes) deleted, \($0.keeps) kept)" }.joined(separator: "; ")
        }
        return """
            Decisions so far: \(facts.labelCount).
            Subjects mostly deleted: \(line(facts.deletes)).
            Subjects mostly kept: \(line(facts.keeps)).
            """
    }
}
