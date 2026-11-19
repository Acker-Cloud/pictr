import SwiftUI

/// Quick Select: a month as a grid. Pick the ones to delete, keep the rest in one tap.
struct QuickSelectView: View {
    let title: String
    let items: [ReviewItem]

    @Environment(DecisionsModel.self) private var decisions
    @Environment(LibraryModel.self) private var library
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var thumbnails = ThumbnailProvider()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
    /// Undecided items, with favorites as Pictr knows them now: one can be made in the viewer
    /// after it was selected here.
    private var shown: [ReviewItem] {
        items.filter { decisions.book.decision(for: $0.id) == nil }.map { item in
            var item = item
            item.isFavorite = library.isFavorite(item)
            return item
        }
    }
    private var selectable: [ReviewItem] { shown.filter { !$0.isFavorite } }
    private var chosen: [ReviewItem] { selectable.filter { selected.contains($0.id) } }
    private var others: [ReviewItem] { shown.filter { $0.isFavorite || !selected.contains($0.id) } }
    private var allSelected: Bool { !selectable.isEmpty && selectable.allSatisfy { selected.contains($0.id) } }

    var body: some View {
        ScrollView {
            Text("Tap the ones to delete. Favorites are protected. Touch and hold to look closer.")
                .font(Theme.Typeface.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, Theme.Space.x2)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(shown) { item in
                    cell(item)
                        .onTapGesture { toggle(item) }
                        .photoContextMenu(id: item.id, in: shown.map(\.id), presenter: viewer,
                                          decisions: decisions, provider: thumbnails, isFavorite: item.isFavorite)
                }
            }
        }
        .background(PictrBackground())
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView("All sorted", systemImage: "checkmark.circle",
                                       description: Text("Every photo here has a decision."))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Select none" : "Select all") {
                    selected = allSelected ? [] : Set(selectable.map(\.id))
                }
                .disabled(selectable.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) { if !shown.isEmpty { actions } }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func cell(_ item: ReviewItem) -> some View {
        let isSelected = selected.contains(item.id)
        return Thumb(id: item.id, provider: thumbnails, pixels: 110 * displayScale)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if isSelected { Color.black.opacity(0.3) } }
            .overlay(alignment: .topTrailing) {
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Theme.Palette.accent : Color.black.opacity(0.35))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if item.mediaKind == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Photo")
            .accessibilityValue(item.isFavorite ? "Favorite, protected" : isSelected ? "Selected" : "")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: Theme.Space.x2) {
            VStack(spacing: Theme.Space.x2) {
                Button {
                    for item in chosen { decisions.record(.trash, for: item) }
                    selected = []
                } label: {
                    Text("Add \(chosen.count) to Ready to Delete").frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .disabled(chosen.isEmpty)

                Button {
                    for item in others { decisions.record(.keep, for: item) }
                    if chosen.isEmpty { dismiss() }
                } label: {
                    Text(chosen.isEmpty ? "Keep all \(others.count)" : "Keep the other \(others.count)")
                        .frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
                .disabled(others.isEmpty)
            }
        }
        .padding(Theme.Space.x4)
    }

    private func toggle(_ item: ReviewItem) {
        guard !item.isFavorite else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }
}
