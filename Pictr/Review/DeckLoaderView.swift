import SwiftUI

/// Loads deck items off the main actor, then shows the deck.
struct DeckLoaderView: View {
    let title: String
    let load: @Sendable () -> [ReviewItem]
    var showsQuickSelect = true

    @Environment(DecisionsModel.self) private var decisions
    @State private var items: [ReviewItem]?
    @State private var all: [ReviewItem] = []
    @State private var showsGrid = false
    @AppStorage(Prefs.batchSize) private var batchSize = 0

    var body: some View {
        Group {
            if let items {
                if items.isEmpty {
                    ContentUnavailableView("Nothing left to review", systemImage: "checkmark.circle",
                                           description: Text("Everything here already has a decision."))
                        .settingsToolbar()
                } else {
                    DeckView(title: title, items: items)
                }
            } else {
                ProgressView()
                    .settingsToolbar()
            }
        }
        .background(PictrBackground())
        .navigationTitle(title)
        .toolbar {
            if showsQuickSelect {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Quick Select", systemImage: "square.grid.3x3") { showsGrid = true }
                        .disabled(all.isEmpty)
                }
            }
        }
        .navigationDestination(isPresented: $showsGrid) {
            QuickSelectView(title: title, items: all)
        }
        .task {
            guard items == nil else { return }
            let load = load
            let loaded = await Task.detached(priority: .userInitiated) { load() }.value
            all = loaded
            let undecided = loaded.filter { decisions.book.decision(for: $0.id) == nil }
            items = batchSize > 0 ? Array(undecided.prefix(batchSize)) : undecided
        }
    }
}
