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
}
