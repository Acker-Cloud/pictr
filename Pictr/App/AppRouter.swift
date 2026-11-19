import Foundation
import Observation

enum AppTab: Hashable {
    case today, lookback, cleanup, queue
}

/// Which tab is showing, and screens a Shortcut asked for. Shared so App Intents
/// running in the app can reach it.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .today
    /// Set by the Shuffle shortcut; Today opens a shuffle deck and clears it.
    var pendingShuffle = false

    func open(_ tab: AppTab, shuffle: Bool = false) {
        self.tab = tab
        if shuffle { pendingShuffle = true }
    }

    struct Destination: Equatable {
        var tab: AppTab
        var shuffle: Bool
    }

    /// Widget taps arrive as pictr://today or pictr://shuffle.
    nonisolated static func destination(for url: URL) -> Destination? {
        guard url.scheme == "pictr" else { return nil }
        switch url.host() {
        case "today": return Destination(tab: .today, shuffle: false)
        case "shuffle": return Destination(tab: .today, shuffle: true)
        default: return nil
        }
    }

    func open(_ url: URL) {
        guard let destination = Self.destination(for: url) else { return }
        open(destination.tab, shuffle: destination.shuffle)
    }
}
