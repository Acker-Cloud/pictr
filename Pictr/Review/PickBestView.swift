import SwiftUI

/// Compare the shots of one moment and keep the best. Two panes, each swipes through
/// the moment; with Zoom Lock on, pinching or panning one moves both. Nothing starts
/// picked, and the rest queue only when you tap the button that says so.
struct PickBestView: View {
    let items: [ReviewItem]
    var mode: DeckMode = .decide
    /// One decision per item, in order.
    let onCommit: ([Decision]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var loader = ImageLoader()
    @State private var thumbnails = ThumbnailProvider()
    @State private var topIndex = 0
    @State private var bottomIndex = 1
    @State private var picks: Set<String> = []
    @State private var zoomLock = true
    @State private var shared = ZoomState()
    @State private var top = ZoomState()
    @State private var bottom = ZoomState()

    private enum Slot { case top, bottom }

    private var thumbPixels: CGFloat { 64 * displayScale }
    /// Favorites are protected, so they count as kept whether picked or not.
    private func isKept(_ item: ReviewItem) -> Bool { item.isFavorite || picks.contains(item.id) }
    private var keptCount: Int { items.filter(isKept).count }
    private var restCount: Int { items.count - keptCount }

    var body: some View {
        NavigationStack {
            VStack(spacing: 2) {
                pane(.top)
                pane(.bottom)
            }
            .background(Color.black)
            .safeAreaInset(edge: .bottom) { tray }
            .navigationTitle("Pick the best")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $zoomLock) { Label("Zoom Lock", systemImage: zoomLock ? "lock.fill" : "lock.open") }
                        .toggleStyle(.button)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sensoryFeedback(.selection, trigger: picks)
            .onAppear {
                thumbnails.prepare(ids: items.map(\.id), targetSize: CGSize(width: thumbPixels, height: thumbPixels))
            }
            .onDisappear { thumbnails.stop() }
        }
    }

    // MARK: Panes

    private func pane(_ slot: Slot) -> some View {
        let index = slot == .top ? topIndex : bottomIndex
        let item = items[min(index, items.count - 1)]
        let kept = isKept(item)
        return ZoomPane(id: item.id, loader: loader, state: zoomBinding(slot)) { step(slot, by: $0) }
            .overlay(alignment: .topLeading) { position(of: item, at: index) }
            .overlay(alignment: .topTrailing) { pickButton(for: item) }
            .overlay {
                Rectangle()
                    .stroke(kept ? Theme.Palette.textPrimary.opacity(0.8) : .clear, lineWidth: 3)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Next shot") { step(slot, by: 1) }
            .accessibilityAction(named: "Previous shot") { step(slot, by: -1) }
    }

    private func zoomBinding(_ slot: Slot) -> Binding<ZoomState> {
        if zoomLock { return $shared }
        return slot == .top ? $top : $bottom
    }

    private func position(of item: ReviewItem, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(index + 1) of \(items.count)").font(Theme.Typeface.captionMedium)
            if let date = item.creationDate {
                Text(date.formatted(.dateTime.hour().minute().second())).font(Theme.Typeface.caption)
            }
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x1 + 2)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .padding(Theme.Space.x3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func pickButton(for item: ReviewItem) -> some View {
        if item.isFavorite {
            Label("Favorite", systemImage: "heart.fill")
                .font(Theme.Typeface.captionMedium)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x2)
                .glassEffect()
                .padding(Theme.Space.x3)
                .accessibilityLabel("Favorite, always kept")
        } else {
            let picked = picks.contains(item.id)
            Button { toggle(item.id) } label: {
                Label(picked ? "Keeping" : "Keep", systemImage: picked ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typeface.captionMedium)
            }
            .buttonStyle(.glass)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(Theme.Space.x3)
            .accessibilityLabel(picked ? "Keeping this shot" : "Keep this shot")
        }
    }

    // MARK: Tray

    private var tray: some View {
        VStack(spacing: Theme.Space.x3) {
            filmstrip
            Button { commit() } label: {
                Text(commitTitle).frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
            .disabled(keptCount == 0)

            Text(footnote)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Space.x4)
    }

    private var commitTitle: String {
        if keptCount == 0 { return "Pick the shots to keep" }
        if restCount == 0 { return "Keep all \(items.count)" }
        let rest = mode == .train ? "would delete \(restCount)" : "add \(restCount) to Ready to Delete"
        return "Keep \(keptCount), \(rest)"
    }

    private var footnote: String {
        mode == .train
            ? "Swipe either photo to bring up another shot. Training queues nothing."
            : "Swipe either photo to bring up another shot. Nothing is deleted until you confirm in Ready to Delete."
    }

    /// Every shot in the moment. Tap one to bring it up in the bottom pane; touch and hold to keep it.
    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.x2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        filmstripCell(item, at: index).id(index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .onChange(of: bottomIndex) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }

    private func filmstripCell(_ item: ReviewItem, at index: Int) -> some View {
        let showing = index == topIndex || index == bottomIndex
        let kept = isKept(item)
        return Button { show(index) } label: {
            Thumb(id: item.id, provider: thumbnails, pixels: thumbPixels)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(showing ? Theme.Palette.textPrimary : .white.opacity(0.1), lineWidth: showing ? 2 : 1))
                .overlay(alignment: .bottomTrailing) {
                    if kept {
                        Image(systemName: item.isFavorite ? "heart.fill" : "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(3)
                            .glassEffect(.regular, in: .circle)
                            .padding(3)
                    }
                }
                .opacity(kept || showing ? 1 : 0.7)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if !item.isFavorite {
                Button(kept ? "Don't keep" : "Keep", systemImage: kept ? "circle" : "checkmark.circle") { toggle(item.id) }
            }
        }
        .accessibilityLabel("Shot \(index + 1)\(kept ? ", keeping" : "")")
        .accessibilityAction(named: kept ? "Don't keep" : "Keep") { if !item.isFavorite { toggle(item.id) } }
    }

    // MARK: Actions

    /// Moves a pane to the next shot that isn't already in the other pane.
    private func step(_ slot: Slot, by delta: Int) {
        let current = slot == .top ? topIndex : bottomIndex
        let other = slot == .top ? bottomIndex : topIndex
        var next = current + delta
        if next == other { next += delta }
        guard items.indices.contains(next) else { return }
        withAnimation(Theme.Motion.base) {
            if slot == .top { topIndex = next } else { bottomIndex = next }
        }
    }

    private func show(_ index: Int) {
        guard index != topIndex, index != bottomIndex else { return }
        withAnimation(Theme.Motion.base) { bottomIndex = index }
    }

    private func toggle(_ id: String) {
        if picks.contains(id) { picks.remove(id) } else { picks.insert(id) }
    }

    private func commit() {
        guard keptCount > 0 else { return }
        onCommit(items.map { isKept($0) ? .keep : .trash })
        dismiss()
    }
}
